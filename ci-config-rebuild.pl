#!/usr/bin/perl -w

use strict;
$::specdir = "/tmp/specs";

# https://raw.githubusercontent.com/fmidev/smartmet-library-grid-files/master/smartmet-library-grid-files.spec
sub getspec($$) {
	my $module = shift;
	my $branch = shift;
	if ( !$branch ) { $branch = "master" }

	# Remove .git and parts of URL if they accidentally got into module
	$module =~ s%[.]git$%%;
	$module =~ s%^.*/%%;
	my $url =
	  "https://raw.githubusercontent.com/fmidev/$module/$branch/$module.spec";
	system( "curl", "-s","-o", "$::specdir/$module.spec", "$url" )==0
	  or die("Unable to fetch spec file for $module");
}

%::testrules  = ();
%::buildrules = ();
%::jobs       = ();

sub genconfigpart($) {
	my $module = shift;

	my @buildreq = ();    # Contents from Buildrequires lines
	my @testreq  = ();    # Contents from Requires and #TestRequires lines

	if ( ! $::buildrules{$module} ) {
		if ( !-r "$::specdir/$module.spec" ) {
			getspec( $module, "master" );
		}
		open( FH, "$::specdir/$module.spec" )
		  or die("Unable to read $::specdir/$module.spec: $!");
		while (<FH>) {
			if (   $_ =~ m/^(Requires:)(.*)$/
				|| $_ =~ m/^#(TestRequires:)(.*)$/
				|| $_ =~ m/^(BuildRequires:)(.*)$/ )
			{
				my $tag = $1;
				my $b = $2;
				$b =~ s/\s*//;      # Remove ws after tag
				$b =~ s/\s.*$//;    # Remove ws+others after module name
				if ( $b =~ m/^smartmet-/ ) {
					if ( $tag =~ m/^BuildRequires/ ) {
						push @buildreq, $b;
					} else {
						push @testreq, $b;
					}
				}
			}
		}

		$::testrules{$module} = "test-$module:\n  <<: *test_defaults\n";
		$::buildrules{$module} = "build-$module:\n  <<: *build_defaults\n";
		$::jobs{"test-$module"} = "        requires:
          - build-" . join( "\n          - build-", @testreq ) . "\n";
		$::jobs{"build-$module"} = "        requires:
          - build-" . join( "\n          - build-", @buildreq ) . "\n";
		close(FH);
	}
}

mkdir($::specdir);

# Fetch server spec
# Read it, collect build, install and test requirements and generate this part of yml
#  Recursively call the requirements
genconfigpart("smartmet-server");

print "aliases:
&build_defaults:
  build:
    docker:
      - image: fmidev/smartmet-cibase:latest
    steps:
      - checkout
      - run:
          name: Install build dependencies
          command: ci-build deps
      - run:
          name: Build RPM
          command: ci-build rpm
      - persist_to_workspace:
          root: /dist
          paths: ./*.rpm
&test_defaults:
  test:
    docker:
      - image: fmidev/smartmet-cibase:latest
    steps:
      - checkout
      - attach_workspace:
          at: /dist
      - run:
          name: Installation test
          command: sudo yum install -y /dist/*.rpm
      - run:
          name: Test prepare
          command: ci-build testprep
      - run:
          name: Test
          command: ci-build test
      - store_artifacts:
          path: /dist
          destination: dist/
version: 2\n";
print "jobs:
";
foreach my $rule ( sort keys %::buildrules ) {
	print $::buildrules{$rule};
}
foreach my $rule ( sort keys %::testrules ) {
	print $::testrules{$rule};
}
print "
workflows:
  version: 2
  jobs:
";
foreach my $job ( sort keys %::jobs ) {
	print "    - ".$job.":\n".$::jobs{$job};
}
