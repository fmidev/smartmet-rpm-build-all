# smartmet-rpm-build-all

Build and test all RPM packages in correct dependency order and form yum repository

## Purpose of this module

This module is mainly intended for automatic CI builds in CirleCI(or future another system).
When used in such a context, it should build and test all public smartmet-modules. The resulting set
is an YUM repository and set of RPMs that is tested and working.

The CI should run this approximately daily.

## Triggering the build daily

A separate module smartmet-rpmbuild-all-trigger rebuilds the config for this module and pushes changes to GitHub.
That should trigger a rebuild. If there are no changes, cleartext timestamp inside the config 
is nonetheless updated to force a rebuild.

A full rebuild is also triggered if any changes are pushed to Github.

NOTE: Do not use a workflow schedule trigger here, use it instead in the trigger module.

## CI configuration build

CI configuration in .circleci/config.yml is generated from the template file in the same directory.
CircleCI is unable to regenerate the config file and restart. Thus it is either regenerated manually or by a separate
module.

Template and resulting CircleCI config use features of CirleCI 2.1 to simplify individual jobs.
It is recommended that you make changes to specified execution environment and commands instead of the job templates
unless absolutely required.

The configuration rebuild process:
* reads template
* downloads spec files of predefined set of modules
* reads their contents and records build and test dependencies
* recursively reads spec files of all dependany modules and records build and test dependencies for them as well
* constructs build and test jobs for all modules found via this process
* constructs dependency definitions under workflow

## Module building and testing

Modules are built using general rules. Their individual CircleCI configs are not used for this process (it would
be too difficult to parse CircleCI configs). Instead a generic cibuild command is used and whatever is defined
in CirleCI build and test commands in CircleCI config for this module. Cibuild command should be part of
docker-smartmet-cibase.

In general the build process:
* downloads dependencies
* runs make rpm
* collects resulting RPMs for passing to other steps

The test process:
* constructs an RPM repository out of already tested RPMs in this workflow
* installs (with dependencies) the RPMs under testing
* installs anything mentioned in spec file on #TestRequires lines
* runs make test
* moved the now tested RPMs for passing in the general end-result repository

No module specific rules are possible. In theory you could detect the module name in the build/test command, and
do something module specific. However, the better way is to actually implement these inside the modules
themselves in make rpm and make test rules instead and/or specific dependant modules.

## Collecting and archiving end results

As a final step, all tested RPMs are collected, and a repository made out of those.
This now has a set of tested RPMs.

## Modifying the template and/or config rebuilder

Modify the template to improve the build process such as using CirleCI caching(might speed up builds significantly).
Modify the config rebuilder command for changes which need to be repeated on all modules and/or modifications to the
dependency building process.

## Branches

Currently this module is designed to work with master only and will build the master branch of all smartmet-modules.
Branching and using the same branch name for other modules is possible but has not been tested and likely has errors.
For the time being, daily automatic builds for anything besides master would not be working anyway as there is no
other branch which would have all needed modules.

## Internals

Many of these details are actually implemented by the CircleCI configuration. Changing the template may change these.
Please change this document as well, if needed.

### Passing of resulting build artifacts

Build artifact are saved on /dist. This is saved as a workspace after every build. Thus, after every step,
it contains more RPMs. List of resulting RPMS from each build step is saved in the same directory
by the name of job .lst .

### Running tests with the dependants

Using /dist (which is shared with the steps), all RPM files are linked to an alternate directory which is transformed
to a yum repository and used during testing. This way all already built dependencies are installable as well.

Workspace /dist is not saved after testing as it is not modified.

### Transforming /dist to a real repo

The final repo files are created after all jobs are really done.


## Other modules

* docker-smartmet-cibase: definition for a base CI build docker image. Rebuilt every day on Dokcer hub
* smartmet-rpm-build-all-trigger
* smartmet-build-utils (useful if you need local builds)
* other smartmet modules