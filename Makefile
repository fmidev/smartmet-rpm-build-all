
.circleci/config.yml: .phony
	perl ci-config-rebuild.pl > tmp.yml
	circleci config validate tmp.yml
	yamllint tmp.yml
	mkdir -p .circleci
	mv tmp.yml .circleci/config.yml

.phony: