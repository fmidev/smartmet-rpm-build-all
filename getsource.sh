#!/bin/bash

# The following variables are needed
# CI=true
# CIRCLECI=true
# CIRCLE_BRANCH
# CIRCLE_JOB
# CIRCLE_REPOSITORY_URL
# CIRCLE_WORKING_DIRECTORY

for i in CI CIRCLECI CIRCLE_BRANCH CIRCLE_REPOSITORY_URL CIRCLE_WORKING_DIRECTORY CIRCLE_JOB ; do
	if [ -z "$$i" ] ; then
		echo "Environment variable $i needs to be set and non-empty" >&2
		exit 2
	else
		echo "$i: $$i"
	fi
done

# Assume /tmp/build is unique to this container
cd /tmp
mkdir -p build
jobbase=`echo $CIRCLE_JOB | sed -e 's/^.*smartmet-/smartmet-/'`
repo=`echo $CIRCLE_REPOSITORY_URL | sed -e "s%[^/]*\$%$jobbase%"`
echo "Checking out $repo"
# Check out same branch first, fallback to devel and then to master
git clone -b "$CIRCLE_BRANCH" "$repo" build || 
git clone -b devel "$repo" build ||
git clone -b master "$repo" build
