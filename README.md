# smartmet-rpm-build-all

Build and test all RPM packages in correct dependency order and form yum repository

## Purpose of this module

This module is mainly intended for automatic CI builds in CirleCI(or future another system).
When used in such a context, it should build and test all public smartmet-modules. The resulting set
is an YUM repository and set of RPMs that is tested and working.

The CI should run this approximately daily.

## Triggering on change to this repository

If you change, commit and push anything, a full rebuild is triggered. If you are merely developing nuances of the
CI build system (and do not intend to build everything), please work in a separate branch or push upstream only
when ready.

Due to the automatic daily updates of the config.yml anyway, you are also likely to encounter merge conflicts.
You should resolve these by overwriting config.yml with anything make generates. This will be done daily anyway(see below).

## Scheduled builds

In .circleci/config.yml, there is a scheduled workflow which is run every night.
The only purpose of this workflow is to force a minor(or major, if there have been a lot of dependency changes
in RPMs) change in config.yml and push it to GitHub.
This will trigger a full rebuild.

## CI configuration build

CI configuration in .circleci/config.yml is generated from the template file in the same directory.
When you modify the template, CircleCI itself is unable to regenerate the config file and restart.

You should run make and commit and push both .circleci/config.yml and .circleci/config.tmpl.yml .
This will trigger a full rebuild.

Testing individual jobs is possible with careful use of the local CirleCI simulation tool.

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

WARNING: Operation with branches has not been tested as there are no other branches with a full set of modules except master.

If you wish to run nightly builds and/or need to test he full rebuild process on your branches, you can branch
this repository and modify the configuration template. Currently the scheduled workflow is only enabled for master and devel
branches but you can easily modify this in your own branch. However, when developing, you can always force a full
rebuild by calling make force , git commit and git push .

As the other modules(that is, the full dependency tree) is checked out during the process, there might not be a module
for your branch in everything. Thus there is a fallback first to devel and then master branch which will be used for
fetching dependant repositories.

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

* docker-smartmet-cibase: definition for a base CI build docker image
* smartmet-build-utils (useful if you need local builds)
* other smartmet modules
