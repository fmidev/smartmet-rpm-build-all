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
	fi
done

# Assume /tmp/build is unique to this container