
.circleci/config.yml: .circleci/config.tmpl.yml ci-config-rebuild.pl Makefile
	perl ci-config-rebuild.pl < .circleci/config.tmpl.yml > tmp.yml
	echo "SKIPPING circleci config validate tmp.yml due to CI problems"
	mkdir -p .circleci
	mv tmp.yml .circleci/config.yml

force:
	touch ci-config-rebuild.pl
	rm -f /tmp/specs/*
	make

check:
	cp .circleci/config.yml .circleci/config.check
	make force
	sed -e 's/^#timestamp.*//' < .circleci/config.yml > .circleci/config.check2
	mv .circleci/config.check .circleci/config.yml
	sed -e 's/^#timestamp.*//' < .circleci/config.yml > .circleci/config.check
	@if ! cmp -s .circleci/config.check .circleci/config.check2 ; then echo;echo "ERROR: config.yml is old. Forgot to run make? Run make, commit and push" ; echo ; false ; fi
	@rm -f .circleci/config.check .circleci/config.check2
	@echo; echo Config.yml is current
