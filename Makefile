SHELL:=/bin/bash
CLI_DIR:='$(CURDIR)/docker-ce/components/cli'
ENGINE_DIR:='$(CURDIR)/docker-ce/components/engine'
GIT_BASE_REPO:=https://github.com/docker/docker-ce
BASE_BRANCH:=17.06
VERSION ?= $(shell cat docker-ce/VERSION)
DOCKER_GITCOMMIT ?= $(shell git -C $(ENGINE_DIR) rev-parse --short HEAD)
DOCKER_DEV_IMG ?= $(shell cat docker-dev-digest.txt)
BUILD_TAG ?= local
EXECUTOR_NUMBER ?= 0
CONTAINER_NAME=$(BUILD_TAG)-$(EXECUTOR_NUMBER)-$(shell date | md5sum | head -c6)
VOL_MNT_BUNDLES = '$(CURDIR)/bundles:/go/src/github.com/docker/docker/bundles'
VOL_MNT_CLI = '$(CURDIR)/docker-ce/components/cli/build:/usr/local/cli'
CHOWN=docker run --rm -v $(CURDIR):/v -w /v alpine:3.6 chown

help: ## show make targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf " \033[36m%-20s\033[0m  %s\n", $$1, $$2}' $(MAKEFILE_LIST)

clean: ## clean artifacts
	$(RM) -r bundles
	$(RM) -r docker-ce
	$(RM) *.tgz
	$(RM) *.txt

docker-gitcommit.txt: ## save docker gitcommit to file
	echo $(DOCKER_GITCOMMIT) > $@

docker-ce.tgz: ## package source
	tar czf $@ docker-ce

docker-dev: ## build and push docker-dev image
	./make-docker-dev $(ENGINE_DIR)

binary-client: ## statically compile cli
	make -C $(CLI_DIR) -f docker.Makefile binary

binary-daemon: ## statically compile daemon for running tests
	docker run --rm --privileged --name $(CONTAINER_NAME)-binary \
		-v $(VOL_MNT_BUNDLES) \
		-e DOCKER_GITCOMMIT=$(DOCKER_GITCOMMIT) \
		$(DOCKER_DEV_IMG) hack/make.sh binary

test-integration-cli: ## run integration test for TEST_SUITE
	docker run --rm --privileged --name $(CONTAINER_NAME) \
		-v $(VOL_MNT_BUNDLES) \
		-v $(VOL_MNT_CLI) \
		-e DOCKER_CLI_PATH=docker \
		-e DOCKER_GITCOMMIT=$(DOCKER_GITCOMMIT) \
		-e TESTFLAGS='-test.run $(TEST_SUITE).*' \
		-e KEEPBUNDLE=1 \
		$(DOCKER_DEV_IMG) hack/make.sh test-integration-cli

log-%.tgz: ## package integration test logs
	$(CHOWN) -R $(shell id -u):$(shell id -g) bundles
	find bundles -name '*.log' -o -name '*.prof' -o -name integration.test | xargs tar -czf $@

daemon-unit-test: ## run unit tests for daemon
	docker run --rm --privileged --name $(CONTAINER_NAME)-daemon-unit \
		-t \
		-e DOCKER_GITCOMMIT=$(DOCKER_GITCOMMIT) \
		$(DOCKER_DEV_IMG) hack/make.sh test-unit

extract-src: ## extract docker-ce source
	tar xzf docker-ce.tgz

client-unit-test: ## run unit tests for cli
	make -C $(CLI_DIR) -f docker.Makefile test-unit
