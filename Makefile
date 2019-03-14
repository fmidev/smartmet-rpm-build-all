
.circleci/config.yml: .circleci/config.tmpl.yml ci-config-rebuild.pl Makefile
	perl ci-config-rebuild.pl < .circleci/config.tmpl.yml > tmp.yml
	circleci config validate tmp.yml
	mkdir -p .circleci
	mv tmp.yml .circleci/config.yml

force:
	touch ci-config-rebuild.pl
	make

check:
	cp .circleci/config.yml .circleci/config.check
	make
	@if ! cmp -s .circleci/config.check .circleci/config.yml ; then echo;echo "ERROR: config.yml is old. Forgot to run make? Run make, commit and push" ; echo ; false ; fi
	@rm -f .circleci/config.check
	@echo; echo Config.yml is current
