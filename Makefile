
.circleci/config.yml: .circleci/config.tmpl.yml
	perl ci-config-rebuild.pl < .circleci/config.tmpl.yml > tmp.yml
	circleci config validate tmp.yml
	mkdir -p .circleci
	mv tmp.yml .circleci/config.yml
