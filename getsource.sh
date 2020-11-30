#!/bin/bash

set -e

# The following variables are needed
# CI=true
# CIRCLECI=true
# CIRCLE_BRANCH
# CIRCLE_JOB
# CIRCLE_REPOSITORY_URL
# CIRCLE_WORKING_DIRECTORY

for i in CI CIRCLECI CIRCLE_BRANCH CIRCLE_REPOSITORY_URL CIRCLE_WORKING_DIRECTORY CIRCLE_JOB ; do
	if [ -z "${!i}" ] ; then
		echo "Environment variable $i needs to be set and non-empty" >&2
		exit 2
	else
		echo "$i:" ${!i}
	fi
done

# Inside the container, we have to use HTTPS as ssh keys are not in place
if ! ( echo $repobase | grep -q '^https:' ) ; then
    repobase='https://github.com/fmidev'
else
    repobase=`echo $CIRCLE_REPOSITORY_URL | sed -e "s%/[^/]*\$%%"`
fi

# Assume /tmp/build is unique to this container
cd /tmp
jobbase=`echo $CIRCLE_JOB | sed -e 's/^.*smartmet-/smartmet-/'`
repo="$repobase/$jobbase"
echo "Checking out $repo"

# Check out same branch first, fallback to devel and then to master.

# THIS DOES NOT WORK, SINCE 'build' may have been created. Hence we try only the requested branch for now:
#
# git clone -b "$CIRCLE_BRANCH" "$repo" build || git clone -b devel "$repo" build || git clone -b master "$repo" build
git clone -b "$CIRCLE_BRANCH" "$repo" build

cd build
echo Checked out branch "`git branch --no-color | cut -f 2 -d ' '`"
