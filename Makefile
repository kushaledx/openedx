# Do things in edx-platform
.PHONY: base-requirements check-types clean \
  compile-requirements detect_changed_source_translations dev-requirements \
  docs extract_translations \
  guides help lint-imports local-requirements migrate migrate-lms migrate-cms \
  pre-requirements pull pull_xblock_translations pull_translations push_translations \
  requirements shell swagger \
  technical-docs test-requirements ubuntu-requirements upgrade-package upgrade

# Careful with mktemp syntax: it has to work on Mac and Ubuntu, which have differences.
PRIVATE_FILES := $(shell mktemp -u /tmp/private_files.XXXXXX)

help: ## display this help message
	@echo "Please use \`make <target>' where <target> is one of"
	@grep '^[a-zA-Z]' $(MAKEFILE_LIST) | sort | awk -F ':.*?## ' 'NF==2 {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}'

clean: ## archive and delete most git-ignored files
	@# Remove all the git-ignored stuff, but save and restore things marked
	@# by start-noclean/end-noclean. Include Makefile in the tarball so that
	@# there's always at least one file even if there are no private files.
	sed -n -e '/start-noclean/,/end-noclean/p' < .gitignore > /tmp/private-files
	-tar cf $(PRIVATE_FILES) Makefile `git ls-files --exclude-from=/tmp/private-files --ignored --others`
	-git clean -fdX
	tar xf $(PRIVATE_FILES)
	rm $(PRIVATE_FILES)

SWAGGER = docs/lms-openapi.yaml

docs: swagger guides technical-docs ## build the documentation for this repository
	$(MAKE) -C docs html

swagger: ## generate the swagger.yaml file
	DJANGO_SETTINGS_MODULE=docs.docs_settings python manage.py lms generate_swagger --generator-class=edx_api_doc_tools.ApiSchemaGenerator -o $(SWAGGER)

extract_translations: ## extract localizable strings from sources
	i18n_tool extract --no-segment -v
	cd conf/locale/en/LC_MESSAGES && msgcat djangojs.po underscore.po -o djangojs.po

pull_plugin_translations:  ## Pull translations for edx_django_utils.plugins for both lms and cms
	python manage.py lms pull_plugin_translations --verbose $(ATLAS_OPTIONS)
	python manage.py lms compile_plugin_translations

pull_xblock_translations:  ## pull xblock translations via atlas
	python manage.py lms pull_xblock_translations --verbose $(ATLAS_OPTIONS)
	python manage.py lms compile_xblock_translations
	python manage.py cms compile_xblock_translations

clean_translations: ## Remove existing translations to prepare for a fresh pull
	# Removes core edx-platform translations but keeps config files and Esperanto (eo) test translations
	find conf/locale/ -type f \! -path '*/eo/*' \( -name '*.mo' -o -name '*.po' \) -delete
	# Removes the xblocks/plugins and js-compiled translations
	rm -rf conf/plugins-locale cms/static/js/i18n/ lms/static/js/i18n/ cms/static/js/xblock.v1-i18n/ lms/static/js/xblock.v1-i18n/

pull_translations: clean_translations  ## pull translations via atlas
	make pull_xblock_translations
	make pull_plugin_translations
	atlas pull $(ATLAS_OPTIONS) \
	    translations/edx-platform/conf/locale:conf/locale \
	    $(ATLAS_EXTRA_SOURCES)
	python manage.py lms compilemessages
	python manage.py lms compilejsi18n
	python manage.py cms compilejsi18n

detect_changed_source_translations: ## check if translation files are up-to-date
	i18n_tool changed

pre-requirements: ## install Python requirements for running pip-tools (still needed for requirements/edx-sandbox and scripts/*, which aren't on uv yet)
	pip install -r requirements/pip-tools.txt

local-requirements: ## no-op; `uv sync` (used by the targets below) already installs -e . itself
	@true

dev-requirements: ## install development environment requirements
	uv sync --group dev --frozen

base-requirements: ## install only production/runtime dependencies
	uv sync --no-default-groups --frozen

test-requirements: ## install production dependencies plus the testing group (used by CI and tox)
	uv sync --no-default-groups --group testing --frozen

requirements: dev-requirements ## install development environment requirements

# requirements/edx-sandbox (codejail's isolated sandbox environment) and the
# scripts/* one-off script directories are not yet migrated to uv (tracked in
# https://github.com/openedx/public-engineering/issues/543) and are still
# compiled with pip-compile below. Order is important: files must appear
# after everything they include!
REQ_FILES = \
	requirements/edx-sandbox/base \
	scripts/xblock/requirements \
	scripts/user_retirement/requirements/base \
	scripts/user_retirement/requirements/testing \
	scripts/structures_pruning/requirements/base \
	scripts/structures_pruning/requirements/testing

define COMMON_CONSTRAINTS_TEMP_COMMENT
# This is a temporary solution to override the real common_constraints.txt\n# In edx-lint, until the pyjwt constraint in edx-lint has been removed.\n# See BOM-2721 for more details.\n# Below is the copied and edited version of common_constraints\n
endef

COMMON_CONSTRAINTS_TXT=requirements/common_constraints.txt
.PHONY: $(COMMON_CONSTRAINTS_TXT)
$(COMMON_CONSTRAINTS_TXT):
	curl -L https://raw.githubusercontent.com/edx/edx-lint/master/edx_lint/files/common_constraints.txt > "$(@)"
	printf "$(COMMON_CONSTRAINTS_TEMP_COMMENT)" | cat - $(@) > temp && mv temp $(@)

compile-requirements: export CUSTOM_COMPILE_COMMAND=make upgrade
compile-requirements: pre-requirements ## Regenerate uv.lock for the root project, and re-compile *.in requirements for the not-yet-migrated sub-projects above
	uv run --no-project --with edx-lint edx_lint write_uv_constraints pyproject.toml
	uv lock ${UV_LOCK_OPTS}

	@# Compatibility exports for external tooling (e.g. tutor's Dockerfile) that
	@# still does `pip install -r requirements/edx/<name>.txt` directly. These are
	@# GENERATED FILES -- see the header comment in each for what regenerates them.
	@mkdir -p requirements/edx
	@{ \
		echo "# GENERATED FILE, DO NOT EDIT DIRECTLY."; \
		echo "# Compatibility export of [project.dependencies] for tools that still"; \
		echo "# 'pip install -r requirements/edx/base.txt' directly instead of using uv."; \
		echo "# Source of truth: [project.dependencies] in pyproject.toml / uv.lock."; \
		uv export --frozen --no-hashes --no-default-groups --no-emit-project; \
	} > requirements/edx/base.txt
	@{ \
		echo "# GENERATED FILE, DO NOT EDIT DIRECTLY."; \
		echo "# Compatibility export of the 'assets' dependency-group for tools that still"; \
		echo "# 'pip install -r requirements/edx/assets.txt' directly instead of using uv."; \
		echo "# Source of truth: [dependency-groups].assets in pyproject.toml / uv.lock."; \
		uv export --frozen --no-hashes --only-group assets --no-emit-project; \
	} > requirements/edx/assets.txt
	@{ \
		echo "# GENERATED FILE, DO NOT EDIT DIRECTLY."; \
		echo "# Compatibility export of the 'dev' dependency-group for tools that still"; \
		echo "# 'pip install -r requirements/edx/development.txt' directly instead of using uv."; \
		echo "# Source of truth: [dependency-groups].dev in pyproject.toml / uv.lock."; \
		uv export --frozen --no-hashes --group dev --no-emit-project; \
	} > requirements/edx/development.txt

	sed 's/Django<5.0//g' requirements/common_constraints.txt > requirements/common_constraints.tmp
	mv requirements/common_constraints.tmp requirements/common_constraints.txt
	sed 's/pip<25.3//g' requirements/common_constraints.txt > requirements/common_constraints.tmp
	mv requirements/common_constraints.tmp requirements/common_constraints.txt

	pip-compile -v --allow-unsafe ${COMPILE_OPTS} -o requirements/pip-tools.txt requirements/pip-tools.in
	pip install -r requirements/pip-tools.txt

	@ export REBUILD='--rebuild'; \
	for f in $(REQ_FILES); do \
		echo ; \
		echo "== $$f ===============================" ; \
		echo "pip-compile -v $$REBUILD ${COMPILE_OPTS} -o $$f.txt $$f.in"; \
		pip-compile -v $$REBUILD ${COMPILE_OPTS} -o $$f.txt $$f.in || exit 1; \
		export REBUILD=''; \
	done

upgrade: $(COMMON_CONSTRAINTS_TXT) ## update all dependencies (uv.lock for the root project, pip-compile for the not-yet-migrated sub-projects) to the latest releases satisfying our constraints
	$(MAKE) compile-requirements COMPILE_OPTS="--upgrade" UV_LOCK_OPTS="--upgrade"

upgrade-package: ## update just one package to the latest usable release
	@test -n "$(package)" || { echo "\nUsage: make upgrade-package package=...\n"; exit 1; }
	$(MAKE) compile-requirements COMPILE_OPTS="--upgrade-package $(package)" UV_LOCK_OPTS="--upgrade-package $(package)"

check-types: ## run static type-checking tests
	mypy

lint-imports:
	lint-imports

migrate-lms:
	python manage.py lms showmigrations --database default --traceback --pythonpath=.
	python manage.py lms migrate --database default --traceback --pythonpath=.

migrate-cms:
	python manage.py cms showmigrations --database default --traceback --pythonpath=.
	python manage.py cms migrate --database default --noinput --traceback --pythonpath=.

migrate: migrate-lms migrate-cms

# WARNING (EXPERIMENTAL):
# This installs the Ubuntu requirements necessary to make `pip install` and some other basic
# dev commands to pass. This is not necessarily everything needed to get a working edx-platform.
# Part of https://github.com/openedx/wg-developer-experience/issues/136
ubuntu-requirements: ## Install ubuntu 22.04 system packages needed for `pip install` to work on ubuntu.
	sudo apt install libmysqlclient-dev libxmlsec1-dev

xsslint: ## check xss for quality issuest
	python scripts/xsslint/xss_linter.py \
	--rule-totals \
	--config=scripts.xsslint_config \
	--thresholds=scripts/xsslint_thresholds.json

ruff: ## check python files with ruff
	ruff check .

## Re-enable --lint flag when this issue https://github.com/openedx/edx-platform/issues/35775 is resolved
pii_check: ## check django models for pii annotations
	DJANGO_SETTINGS_MODULE=cms.envs.test \
	code_annotations django_find_annotations \
		--config_file .pii_annotations.yml \
		--coverage \
		--lint

	DJANGO_SETTINGS_MODULE=lms.envs.test \
	code_annotations django_find_annotations \
		--config_file .pii_annotations.yml \
		--coverage \
		--lint

check_keywords: ## check django models for reserve keywords
	DJANGO_SETTINGS_MODULE=cms.envs.test \
	python manage.py cms check_reserved_keywords \
	--override_file db_keyword_overrides.yml

	DJANGO_SETTINGS_MODULE=lms.envs.test \
	python manage.py lms check_reserved_keywords \
	--override_file db_keyword_overrides.yml
