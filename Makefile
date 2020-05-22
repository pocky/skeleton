BEHAT=$(EXEC) vendor/bin/behat
COMPOSER=$(DOCKER_COMPOSE) exec php composer
CONSOLE=$(EXEC) bin/console
DOCKER?=docker
DOCKER_COMPOSE?=docker-compose
EXEC?=$(DOCKER_COMPOSE) exec php docker-app-entrypoint
EXECJS?=$(DOCKER) run -it --rm --name hades_node -v "$(shell pwd)/":/home/node/app -w /home/node/app node:latest
PHPSPEC=$(EXEC) vendor/bin/phpspec
PHPSTAN=$(EXEC) vendor/bin/phpstan
PHPCSFIXER?=$(EXEC) vendor/bin/php-cs-fixer

.DEFAULT_GOAL := help

.PHONY: help install stop reset clear
.PHONY: watch
.PHONY: build start test tu tf tfp tfp-behat test-behat test-phpspec
.PHONY: phpcs phpcsfix phpstan
.PHONY: db db-diff db-diff-dump db-migrate db-rollback db-load
.PHONY: rm-docker-dev.lock

help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

##
## Project setup
##---------------------------------------------------------------------------
install: .env build start db-clean db-create db-migrate public/build ## Install and start the project

start: ## Start the project
	$(DOCKER_COMPOSE) up -d --remove-orphans

stop: ## Remove docker containers
	$(DOCKER_COMPOSE) kill
	$(DOCKER_COMPOSE) rm -v --force

reset: stop rm-docker-dev.lock start

clear: rm-docker-dev.lock node_modules

##
## Database
##---------------------------------------------------------------------------
wait-for-db:
	$(EXEC) php -r "set_time_limit(60);for(;;){if(@fsockopen('db',5432)){break;}echo \"Waiting for PgSQL\n\";sleep(1);}"

db-clean: vendor wait-for-db  ## Reset the database and load fixtures
	$(CONSOLE) doctrine:database:drop --force --if-exists

db-create: vendor wait-for-db ## Create database and import data if a dump file is present
	$(CONSOLE) doctrine:database:create --if-not-exists
	test -f ./docker/mysql/dump/dump.sql && $(CONSOLE) doctrine:database:import -n -- docker/db/dump/dump.sql || $(CONSOLE) doctrine:migrations:migrate -n

db-migrate: vendor wait-for-db ## Migrate database schema to the latest available version
	$(CONSOLE) doctrine:migration:migrate -n


##
## Assets
##---------------------------------------------------------------------------
node:
	$(EXECJS) $(arg)

watch: node_modules ## Watch the assets and build their development version on change
	$(EXECJS) yarn encore dev --watch

assets-dev: node_modules ## Build the development version of the assets
	$(EXECJS) yarn encore dev

assets-prod: node_modules ## Build the production version of the assets
	$(EXECJS) yarn encore production

##
## Tests
##---------------------------------------------------------------------------
test: tu tf  ## Run all tests

test-behat: ## Run behat tests
	$(BEHAT)

test-phpspec: ## Run phpspec tests with no code generation
	$(PHPSPEC) run -vvv --format=pretty --no-code-generation

run: ## Run phpspec tests with code generation
	$(DOCKER_COMPOSE) exec -u 1000 php vendor/bin/phpspec run -vvv --format=pretty

describe: ## Create php specification file
	$(DOCKER_COMPOSE) exec -u 1000 php vendor/bin/phpspec describe -vvv

tu: test-phpspec

tf: tfp test-behat

tfp: tfp-db

tfp-db: wait-for-db ## Init databases for tests
	$(CONSOLE) doctrine:database:drop --force --if-exists --env=test
	$(CONSOLE) doctrine:database:create --env=test
	$(CONSOLE) doctrine:migration:migrate -n --env=test
	$(CONSOLE) doctrine:schema:validate --env=test

phpcs: vendor ## Lint PHP code
	$(PHPCSFIXER) fix --diff --dry-run --no-interaction -v

phpcsfix: vendor  ## Lint and fix PHP code to follow the convention
	$(PHPCSFIXER) fix

phpstan: vendor
	$(PHPSTAN) analyze --level=max -vvv src

##
## Dependencies
##---------------------------------------------------------------------------
build: docker-dev.lock

docker-dev.lock:
	$(DOCKER_COMPOSE) pull --ignore-pull-failures
	$(DOCKER_COMPOSE) build --force-rm --pull
	touch docker-dev.lock

rm-docker-dev.lock:
	rm -f docker-dev.lock

.env: .env.dist
	cp .env.dist .env.local

vendor: composer.lock
	$(COMPOSER) install -n

composer.lock: composer.json
	@echo composer.lock is not up to date

node_modules: yarn.lock
	$(EXECJS) yarn install

yarn.lock: package.json
	@echo yarn.lock is not up to date.

public/build: node_modules assets-dev
