#!/usr/bin/perl -w

use strict;
use Data::Dumper;
$::specdir = "/tmp/specs";

# usage: ci-config-rebuild [branch]

# https://raw.githubusercontent.com/fmidev/smartmet-library-grid-files/master/smartmet-library-grid-files.spec
sub getspec($$) {
	my $module = shift;
	my $branch = shift;
	if ( !$branch ) { $branch = "master" }

	# Remove .git and parts of URL if they accidentally got into module
	$module =~ s%[.]git$%%;
	$module =~ s%^.*/%%;
	my $url = "https://raw.githubusercontent.com/fmidev/$module/$branch/$module.spec";
	system( "curl", "-s", "-o", "$::specdir/$module.spec", "$url" ) == 0
	  or die("Unable to fetch spec file for $module");
}

# Collect dependencies to these variables
# Hash keys are module names, values are arrays with dependants
%::testdeps  = ();
%::builddeps = ();

sub scan($);

sub scan($) {
	my $module   = shift;
	my %buildreq = ();      # Contents from Buildrequires lines, use hashes to void duplicates
	my %testreq  = ();      # Contents from Requires and #TestRequires lines

	# Only scan modules not already scanned
	if ( !$::builddeps{$module} ) {
		if ( !-r "$::specdir/$module.spec" ) {
			getspec( $module, "master" );
		}
		open( FH, "$::specdir/$module.spec" )
		  or die("Unable to read $::specdir/$module.spec: $!");
		while (<FH>) {
			if (    $_ =~ m/^(Requires:)(.*)$/
				 || $_ =~ m/^#(TestRequires:)(.*)$/
				 || $_ =~ m/^(BuildRequires:)(.*)$/ )
			{
				my $tag = $1;
				my $b   = $2;
				$b =~ s/\s*//;        # Remove ws after tag
				$b =~ s/\s.*$//;      # Remove ws+others after module name
				$b =~ s/-devel$//;    # Remove devel end, will be produced as part of the binary package

				if ( $b =~ m/^smartmet-/ ) {
					if ( $tag =~ m/^BuildRequires/ ) {
						$buildreq{$b} = 1;
					} else {
						$testreq{$b} = 1;
					}
				}
			}
			$::builddeps{$module} = [ sort keys %buildreq ];
			$::testdeps{$module}  = [ sort keys %testreq ];
		}

		#		$::testrules{$module}   = "test-$module:\n  <<: *test_defaults\n";
		#		$::buildrules{$module}  = "build-$module:\n  <<: *build_defaults\n";
		#		$::jobs{"test-$module"} = "        requires:
		#          - build-" . join( "\n          - build-", @testreq ) . "\n";
		#		$::jobs{"build-$module"} = "        requires:
		#          - build-" . join( "\n          - build-", @buildreq ) . "\n";

		close(FH);
	}

	foreach my $mod ( keys %buildreq ) { scan($mod); }
	foreach my $mod ( keys %testreq )  { scan($mod); }
}

mkdir($::specdir);

# Fetch server spec
# Read it, collect build, install and test requirements and generate this part of yml
#  Recursively call the requirements
scan("smartmet-server");
# This does not get all actually needed stuff, this should:
# Mika Heiskanen [12:02 PM]
# backend frontend wcs autocomplete timeseries meta admin download wms wfs
scan("smartmet-plugin-backend");
scan("smartmet-plugin-frontend");
scan("smartmet-plugin-wcs");
scan("smartmet-plugin-autocomplete");
scan("smartmet-plugin-timeseries");
scan("smartmet-plugin-meta");
scan("smartmet-plugin-admin");
scan("smartmet-plugin-download");
scan("smartmet-plugin-wms");
scan("smartmet-plugin-wfs");
scan("smartmet-qdtools");
scan("smartmet-qdcontour");
scan("smartmet-shapetools");

#print Dumper(\%::testdeps );
#print Dumper(\%::builddeps );

my $currenttemplate        = "";
my $currenttemplatename    = "";
my $currenttemplatestartln = 0;    # Save start line number for use in error prints
my $currenttemplateindent  = 0;
my $lineno                 = 0;
my @prejobs                = ();
my @postjobs               = ();

while (<STDIN>) {
	my $ln = $_;
	$lineno++;

	# Special tags
	if ( $ln =~ m/^#timestamp/ ) {
		$ln = "#timestamp " . `LC_ALL=C date`;
	}

	# Start of template? Save line to buffer and go to next line
	if ( $ln =~ m/^#template (\S+)/ ) {
		if ($currenttemplatename) {
			die "error: $currenttemplatename already started on line $lineno - enclosing templates not allowed\n";
		}
		$currenttemplatename    = $1;
		$currenttemplate        = "";
		$currenttemplateindent  = 0;
		$currenttemplatestartln = $lineno;

		# Debug
		# print STDERR "****** Encountered template $currenttemplatename, going to next line\n";
	} elsif ( $ln =~ m/^#end/ ) {

		# End of template? Print out lines in buffer and end template
		if ( !$currenttemplatename ) {
			print STDERR "warning: #end clause without recognized template beginning on line $lineno\n";
		} else {
			if ( $currenttemplatename eq "build" ) {
				foreach my $module ( sort keys %::builddeps ) {
					my $c = $currenttemplate;
					$c =~ s/smartmet-[a-z0-9-]+/$module/sg;
					print $c;
				}
			} elsif ( $currenttemplatename eq "test" ) {
				foreach my $module ( sort keys %::testdeps ) {
					my $c = $currenttemplate;
					$c =~ s/smartmet-[a-z0-9-]+/$module/sg;
					print $c;
				}
			} elsif ( $currenttemplatename eq "pre" || $currenttemplatename eq "post" ) {

				# Pre an post template is passed as is, only read the job name for dependency tree setup
				# Remove comments before checking the job name
				my $c = $currenttemplate;
				$c =~ s/#.*//m;
				if ( $c =~ m/\s*([^ :]*)/s ) {
					if ( $currenttemplatename eq "pre" ) {
						push @prejobs, $1;
					} elsif ( $currenttemplatename eq "post" ) {
						push @postjobs, $1;
					} else {
						die("How did we get to this line??? Processing post/pre but templataname is $currenttemplatename!");
					}
				}
				print $currenttemplate;
			} elsif ( $currenttemplatename eq "deptree" ) {

				# Building the workflow dependency tree is a bit special: we don't actually use the
				# the template for anythig except detecting the indentation
				foreach my $module ( sort @prejobs ) {
					print ' ' x $currenttemplateindent . "- $module\n";
				}
				foreach my $module ( sort keys %::builddeps ) {
					my $value = $::builddeps{$module};
					my $c     = ' ' x $currenttemplateindent . "- build-$module";
					if ( ($value && scalar @$value > 0) || (scalar @prejobs >0) ) {
						$c .= ":\n" . ( ' ' x ( $currenttemplateindent + 3 ) ) . "requires:\n";
                        foreach my $dep (sort @prejobs) {
                            $c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- $dep\n";
                        }
						foreach my $dep (sort @$value) {
							$c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- test-$dep\n";
						}
					} else {
						$c .= "\n";
					}
					print $c;
				}
				foreach my $module ( sort keys %::testdeps ) {
					my $value = $::testdeps{$module};
					my $c     = ' ' x $currenttemplateindent . "- test-$module";
					$c .= ":\n"
					  . ( ' ' x ( $currenttemplateindent + 3 ) )
					  . "requires:\n"
					  . ( ' ' x ( $currenttemplateindent + 4 ) )
					  . "- build-$module\n";
					if ( $value && scalar @$value > 0 ) {
						foreach my $dep (@$value) {
							$c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- test-$dep\n";
						}
					}
					print $c;
				}
				if ( scalar @postjobs ) {

					# Post jobs require that we build and test all modules first
					foreach my $postjobname (@postjobs) {
						my $c = ' ' x $currenttemplateindent . "- " . $postjobname . ":\n"
						  . ( ' ' x ( $currenttemplateindent + 3 ) ) . "requires:\n";
						foreach my $dep ( sort keys %::builddeps ) {
							$c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- build-$dep\n";
						}
						foreach my $dep ( sort keys %::testdeps ) {
							$c .= ( ' ' x ( $currenttemplateindent + 4 ) ) . "- test-$dep\n";
						}

						print $c;
					}
				}
			} else {
				print $currenttemplate;
			}
		}
		$currenttemplatename   = "";
		$currenttemplate       = "";
		$currenttemplateindent = 0;
	} elsif ($currenttemplatename) {

		# In template? ( But not end, that would have been detected previously) Save line in buffer and go to next line
		if ( $currenttemplateindent < 0 ) {
			next;    # Reading repetitive lines
		}
		if ( $ln =~ m/^( +)/ ) {

			# Only check lines which are not completely whitespace or just a commeent
			if ( $ln !~ m/^\s*$/ || $ln !~ m/^\s*#.*$/ ) {
				my $indentation = length $1;    # How many spaces we have
				if ( $indentation <= $currenttemplateindent ) {

					# If indentation is now the same or less, ignore this and the rest until template end.
					# They are just repetition of the same jobs/workflow parts
					$currenttemplateindent = -1;
					next;
				}
				if ( $currenttemplateindent == 0 ) {
					$currenttemplateindent = $indentation;
				}
			}
		}
		$currenttemplate .= $ln;
		next;
	}

	print $ln;
}

