#!/usr/bin/perl -w

use strict;

# Use only locally, not in CircleCI. Requires RPM perl-Data-Dumper
# use Data::Dumper;


$::specdir = "/tmp/specs";

# usage: ci-config-rebuild [branch]

# Names to ignore (part of other packages or not being built on Circle-CI for any reason)
my %ignore = (
    "smartmet-test-data" => 1,
    "smartmet-engine-grid-test" => 1,
    "smartmet-SFCGAL-libs" => 1,
    "smartmet-library-spine-plugin-test" => 1,
    "smartmet-trajectory-formats" => 1,
    "smartmet-trajectory" => 1
    );

$::default_branch = "master";

%::modules = (
    "smartmet-plugin-admin"                 => { "branch" => "", "spec" => ""},
    "smartmet-plugin-autocomplete"          => {},
    "smartmet-plugin-backend"               => {},
    "smartmet-plugin-cross_section"         => {},
    "smartmet-plugin-download"              => {},
    "smartmet-plugin-frontend"              => {},
    "smartmet-plugin-grid-admin"            => {},
    "smartmet-plugin-grid-gui"              => {},
    "smartmet-plugin-meta"                  => {},
    "smartmet-plugin-textgen"               => {},
    "smartmet-plugin-timeseries"            => {},
    "smartmet-plugin-trajectory"            => {},
    "smartmet-plugin-wfs"                   => {},
    "smartmet-plugin-wms"                   => {},
    "smartmet-qdcontour"                    => {},
    "smartmet-qdcontour2"                   => {},
    "smartmet-qdtools"                      => {},
    "smartmet-shapetools"                   => {},
    "smartmet-frontier"                     => {},
    "smartmet-tools-grid"                   => {},
    "smartmet-cropper"                      => {},
    );

# https://raw.githubusercontent.com/fmidev/smartmet-library-grid-files/master/smartmet-library-grid-files.spec
sub getspec($$$)
{
    my $module = get_module_name(shift);
    my $branch = get_branch($module);
    my $spec   = get_spec_name($module);
    
    my $url = "https://raw.githubusercontent.com/fmidev/$module/$branch/$spec.spec";
    print STDERR "\tFetching $url\n";
    system( "curl", "-s", "-o", "$::specdir/$module$spec-$branch", "$url" ) == 0
	or die("Unable to fetch spec file for $module");
}

# Collect dependencies to these variables
# Hash keys are module names, values are arrays with dependants
%::testdeps  = ();
%::builddeps = ();

%::modulenames = ();
%::branchnames = ();

sub scan($)
{
    my $module = get_module_name(shift);
    my $branch = get_branch($module);
    my $spec   = get_spec_name($module);

    # By default the spec is named according to the module

    if(!$spec) { $spec = "$module"; }

    # Unique name for the module/branch combination.
    my $moduleid = ($branch eq "master" ? "$module" : "$module-$branch");

    my %buildreq = ();      # Contents from Buildrequires lines, use hashes to void duplicates
    my %testreq  = ();      # Contents from Requires and #TestRequires lines

    # Only scan modules not already scanned
    if ( !$::builddeps{"$moduleid"} )
    {
	print STDERR "Processing $module branch $branch\n";
	if ( !-r "$::specdir/$module$spec-$branch" )
	{
	    getspec( $module, $branch, $spec );
	}
	open( FH, "$::specdir/$module$spec-$branch" )
	    or die("Unable to read $::specdir/$module$spec-$branch: $!");
	
	while (my $line = <FH>)
	{
	    if (    $line =~ m/^(Requires:)(.*)$/
		    || $line =~ m/^#(TestRequires:)(.*)$/
		    || $line =~ m/^(BuildRequires:)(.*)$/ )
	    {
		my $tag = $1;
		my $b   = $2;
		$b =~ s/\s*//;        # Remove ws after tag
		$b =~ s/\s.*$//;      # Remove ws+others after module name
		$b =~ s/-devel$//;    # Remove devel end, will be produced as part of the binary package
		
		if ( $b =~ m/^smartmet-/ && $b ne $module )
		{
		    # do not build smartmet-test-data etc due to git-lfs limitations, the source is not available etc
		    if ( ! $ignore{$b} )
		    {
			print STDERR "\t$tag $b\n";
			if ( $tag =~ m/^BuildRequires/ )
			{
			    $buildreq{"$b"} = 1;
			}
			else
			{
			    $testreq{"$b"} = 1;
			}
		    }
		}
	    }
	}

	close(FH);

	$::builddeps{"$moduleid"} = [ sort keys %buildreq ];
	$::testdeps{"$moduleid"}  = [ sort keys %testreq ];
	$::modulenames{"$moduleid"} = $module;
	$::branchnames{"$moduleid"} = $branch;

	#		$::testrules{$module}   = "test-$module:\n  <<: *test_defaults\n";
	#		$::buildrules{$module}  = "build-$module:\n  <<: *build_defaults\n";
	#		$::jobs{"test-$module"} = "        requires:
	#          - build-" . join( "\n          - build-", @testreq ) . "\n";
	#		$::jobs{"build-$module"} = "        requires:
	#          - build-" . join( "\n          - build-", @buildreq ) . "\n";
	
    }

    foreach my $mod ( keys %buildreq ) { scan($mod, "master"); }
    foreach my $mod ( keys %testreq )  { scan($mod, "master"); }
}

mkdir($::specdir);

# Fetch node packages, then scan all their requirements

foreach my $module (keys %::modules)
{
    scan($module);
}

# print STDERR Dumper(\%::testdeps );
# print STDERR Dumper(\%::builddeps );

my $allmodules = join(" ", sort keys %{ \%::builddeps } );

my $currenttemplate        = "";
my $currenttemplatename    = "";
my $currenttemplatestartln = 0;    # Save start line number for use in error prints
my $currenttemplateindent  = 0;
my $lineno                 = 0;
my @prejobs                = ();
my @postjobs               = ();

while (<STDIN>)
{
    my $ln = $_;
    $lineno++;
    
    # Special tags
    if ( $ln =~ m/^#timestamp/ )
    {
	$ln = "#timestamp " . `LC_ALL=C date`;
    }

    # Start of template? Save line to buffer and go to next line
    if ( $ln =~ m/^#template (\S+)/ )
    {
	if ($currenttemplatename)
	{
	    die "error: $currenttemplatename already started on line $lineno - enclosing templates not allowed\n";
	}
	$currenttemplatename    = $1;
	$currenttemplate        = "";
	$currenttemplateindent  = 0;
	$currenttemplatestartln = $lineno;
	
	# Debug
	# print STDERR "****** Encountered template $currenttemplatename, going to next line\n";
    }
    elsif ( $ln =~ m/^#end/ )
    {
	# End of template? Print out lines in buffer and end template
	if ( !$currenttemplatename )
	{
	    print STDERR "warning: #end clause without recognized template beginning on line $lineno\n";
	}
	else
	{
	    if ( $currenttemplatename eq "build" )
	    {
		foreach my $module ( sort keys %::builddeps )
		{
		    my $modulename = $::modulenames{$module};
		    my $branchname = $::branchnames{$module};

		    my $c = $currenttemplate;
		    $c =~ s/smartmet-[a-z0-9-]+:/$module:/sg;
		    $c =~ s/module: smartmet-[a-z0-9-]+/module: $modulename/sg;
		    print $c;
		}
	    }
	    elsif ( $currenttemplatename eq "test" )
	    {
		foreach my $module ( sort keys %::testdeps )
		{
		    if (require_tests($module))
		    {
			my $c = $currenttemplate;
			$c =~ s/smartmet-[a-z0-9-]+/$module/sg;
			print $c;
		    }
		}
	    }
	    elsif ( $currenttemplatename eq "pre" || $currenttemplatename eq "post" )
	    {
		# Pre an post template is passed as is, only read the job name for dependency tree setup
		# Remove comments before checking the job name
		my $c = $currenttemplate;
		$c =~ s/#.*//m;
		if ( $c =~ m/\s*([^ :]*)/s )
		{
		    if ( $currenttemplatename eq "pre" )
		    {
			push @prejobs, $1;
		    }
		    elsif ( $currenttemplatename eq "post" )
		    {
			push @postjobs, $1;
		    }
		    else
		    {
			die("How did we get to this line??? Processing post/pre but templataname is $currenttemplatename!");
		    }
		}
		print $currenttemplate;
	    }
	    elsif ( $currenttemplatename eq "deptree" )
	    {
		# Building the workflow dependency tree is a bit special: we don't actually use the
		# the template for anything except detecting the indentation
		foreach my $module ( sort @prejobs )
		{
		    print ' ' x $currenttemplateindent . "- $module\n";
		}
		foreach my $module ( sort keys %::builddeps )
		{
		    my $branchname = $::branchnames{$module};

		    my $value = $::builddeps{$module};

		    my $c     = ' ' x $currenttemplateindent . "- build-$module";

		    if ( ($value && scalar @$value > 0) || (scalar @prejobs >0) )
		    {
			$c .= ":\n" . ( ' ' x ( $currenttemplateindent + 3 ) ) . "requires:\n";
			foreach my $dep (sort @prejobs)
			{
			    $c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- $dep\n";
			}
			foreach my $dep (sort @$value)
			{
			    if (require_tests($dep))
			    {
				$c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- test-$dep\n";
			    }
			    else
			    {
				$c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- build-$dep\n";
			    }
			}
		    }
		    else
		    {
			$c .= "\n";
		    }

		    if( $branchname ne "master")
		    {
			$c .= ( ' ' x ( $currenttemplateindent + 3 ) )  . "filters:\n";
			$c .= ( ' ' x ( $currenttemplateindent + 5 ) ) . "branches:\n";
			$c .= ( ' ' x ( $currenttemplateindent + 7 ) ) . "only:\n";
			$c .= ( ' ' x ( $currenttemplateindent + 9 ) ) . "- $branchname\n";
		    }

		    print $c;
		}
		foreach my $module ( sort keys %::testdeps )
		{
		    if (require_tests($module))
		    {
			my $value = $::testdeps{$module};
			my $c     = ' ' x $currenttemplateindent . "- test-$module";
			$c .= ":\n"
			    . ( ' ' x ( $currenttemplateindent + 3 ) )
			    . "requires:\n"
			    . ( ' ' x ( $currenttemplateindent + 4 ) )
			    . "- build-$module\n";
			if ( $value && scalar @$value > 0 )
			{
			    foreach my $dep (@$value)
			    {
				if (require_tests($dep))
				{
				    $c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- test-$dep\n";
				}
				else
				{
				    $c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- build-$dep\n";
				}
			    }
			}
			print $c;
		    }
		}
		if ( scalar @postjobs )
		{
		    # Post jobs require that we build and test all modules first
		    foreach my $postjobname (@postjobs)
		    {
			my $c = ' ' x $currenttemplateindent . "- " . $postjobname . ":\n"
			    . ( ' ' x ( $currenttemplateindent + 3 ) ) . "requires:\n";
			foreach my $dep ( sort keys %::builddeps )
			{
			    $c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- build-$dep\n";
			}
			foreach my $dep ( sort keys %::testdeps )
			{
			    if (require_tests($dep))
			    {
				$c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- test-$dep\n";
			    }
			}
			
			print $c;
		    }
		}
	    }
	    else
	    {
		print $currenttemplate;
	    }
	}
	$currenttemplatename   = "";
	$currenttemplate       = "";
	$currenttemplateindent = 0;
    }
    elsif ($currenttemplatename)
    {
	# In template? ( But not end, that would have been detected previously) Save line in buffer and go to next line
	if ( $currenttemplateindent < 0 )
	{
	    next;    # Reading repetitive lines
	}
	if ( $ln =~ m/^( +)/ )
	{
	    # Only check lines which are not completely whitespace or just a commeent
	    if ( $ln !~ m/^\s*$/ || $ln !~ m/^\s*#.*$/ )
	    {
		my $indentation = length $1;    # How many spaces we have
		if ( $indentation <= $currenttemplateindent )
		{
		    # If indentation is now the same or less, ignore this and the rest until template end.
		    # They are just repetition of the same jobs/workflow parts
		    $currenttemplateindent = -1;
		    next;
		}
		if ( $currenttemplateindent == 0 )
		{
		    $currenttemplateindent = $indentation;
		}
	    }
	}

	$currenttemplate .= $ln;
	next;
    }
    
    $ln =~ s/<MODULES>/$allmodules/;
    print $ln;
}

#print Dumper(\%::test_required_cache);


sub get_module_name($)
{
    my $module = shift;
    # Remove .git and parts of URL if they accidentally got into module
    $module =~ s%[.]git$%%;
    $module =~ s%^.*/%%;
    return $module;
}

sub get_branch($)
{
    my $module = get_module_name(shift);
    my $tmp = $::modules{$module}{"branch"};
    if (defined($tmp) and ($tmp ne ""))
    {
	return $tmp;
    }
    else
    {
	return $::default_branch;
    }
}

sub get_spec_name($)
{
    my $module = get_module_name(shift);
    my $tmp = $::modules{$module}{"spec"};
    if (defined($tmp) and ($tmp ne ""))
    {
	return $tmp;
    }
    else
    {
	return $module;
    }
}

%::tests_required_cache = ();

sub require_tests($)
{
    my $module = get_module_name(shift);
    my $branch = get_branch($module);
    my $spec   = get_spec_name($module);

    my $cached = $::test_required_cache{$module};

    if (defined $cached)
    {
	if ($cached eq 'yes')
	{
	    return 1;
	}
	elsif ($cached eq 'no')
	{
	    return 0;
	}
	else
	{
	    die "Not supposed to be here";
	}
    }
    else
    {
	my $url = "https://raw.githubusercontent.com/fmidev/$module/$branch/.circleci/disable-tests-in-ci";
	my $result = system( "curl -s -f $url >/dev/null 2>&1" );
	if ($result == 0)
	{
	    $::test_required_cache{$module} = 'no';
	    return 0;
	}
	else
	{
	    $::test_required_cache{$module} = 'yes';
	    return 1;
	}
    }
}
