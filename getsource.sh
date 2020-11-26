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

# Without this LFS requires authentication. Apparently fixed in Jan 2020 git
export GIT_LFS_SKIP_SMUDGE=1

# Inside the container, we have to use HTTPS as ssh keys are not in place
if ! ( echo $repobase | grep -q '^https:' ) ; then
    repobase='https://github.com/fmidev'
else
    repobase=`echo $CIRCLE_REPOSITORY_URL | sed -e "s%/[^/]*\$%%"`
fi

# Assume /tmp/build is unique to this container
cd /tmp
mkdir -p build
jobbase=`echo $CIRCLE_JOB | sed -e 's/^.*smartmet-/smartmet-/'`
repo="$repobase/$jobbase"
echo "Checking out $repo"
# Check out same branch first, fallback to devel and then to master
git clone -b "$CIRCLE_BRANCH" "$repo" build || 
git clone -b devel "$repo" build ||
git clone -b master "$repo" build
cd build
echo Checked out branch "`git branch --no-color | cut -f 2 -d ' '`"
