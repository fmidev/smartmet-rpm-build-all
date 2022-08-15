
build-config:
	mkdir -p .circleci
	perl ci-config-rebuild.pl < .circleci/config.tmpl.yml > .circleci/build-all.yml

force:  build-config

check:
