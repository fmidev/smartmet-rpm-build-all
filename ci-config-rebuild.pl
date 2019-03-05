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

#print Dumper(\%::testdeps );
#print Dumper(\%::builddeps );

my $currenttemplate        = "";
my $currenttemplatename    = "";
my $currenttemplatestartln = 0;    # Save start line number for use in error prints
my $lineno                 = 1;

while (<STDIN>) {
	my $ln = $_;

	# Start of template? Save line to buffer and go to next line
	if ( $ln =~ m/^#template (\S+)/ ) {
		if ($currenttemplatename) {
			die "error: $currenttemplatename already started on line $lineno - enclosing templates not allowed\n";
		}
		$currenttemplatename = $1;
		$currenttemplate     = $ln;
		next;
	}

	# End of template? Print out lines in buffer and end template
	if ( $ln =~ m/^#end/ ) {
		if ( !$currenttemplatename ) {
			print STDERR "warning: #end clause without recognized template beginning on line $lineno\n";
		} else {
			print "# We should actually expand the template $currenttemplatename here\n";
			print $currenttemplate;
		}
		$currenttemplatename = "";
		$currenttemplate     = "";
	}

	# In template? ( But not end, that would have been detected previously) Save line in buffer and go to next line
	if ($currenttemplatename) {
		$currenttemplate .= $ln;
		next;
	}

	print $ln;
	$lineno++;
}

#
#print "jobs:
#";
#foreach my $rule ( sort keys %::buildrules ) {
#	print $::buildrules{$rule};
#}
#foreach my $rule ( sort keys %::testrules ) {
#	print $::testrules{$rule};
#}
#print "
#workflows:
#  version: 2
#  jobs:
#";
#foreach my $job ( sort keys %::jobs ) {
#	print "    - ".$job.":\n".$::jobs{$job};
#}
