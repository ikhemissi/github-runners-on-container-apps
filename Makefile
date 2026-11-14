# Local tasks. Containers run with Podman (set CONTAINER=docker to use Docker).
CONTAINER ?= podman
IMAGE ?= gh-runner:local
HADOLINT_IMAGE = ghcr.io/hadolint/hadolint:v2.15.1

.PHONY: lint build test run-local

lint:  ## shellcheck and hadolint
	shellcheck -x runner/entrypoint.sh runner/tests/test-entrypoint.sh
	$(CONTAINER) run --rm -i $(HADOLINT_IMAGE) < runner/Dockerfile

build:  ## the runner image, for linux/amd64
	$(CONTAINER) build --platform linux/amd64 -t $(IMAGE) runner

test: build  ## the added tools start, and the entrypoint's offline tests pass, in the image
	$(CONTAINER) run --rm --entrypoint bash $(IMAGE) -c 'az version --output none && gh --version && node --version && npm --version'
	$(CONTAINER) run --rm --entrypoint bash -v "$(CURDIR)/runner:/tests:ro,Z" $(IMAGE) /tests/tests/test-entrypoint.sh

run-local: build  ## register one JIT runner from this machine (local test mode, runner/README.md); needs runner/.env
	$(CONTAINER) run --rm --env-file runner/.env \
	  -v "$(GH_REGISTRAR_KEY_FILE):/run/secrets/registrar.pem:ro,Z" -e GH_REGISTRAR_KEY_FILE=/run/secrets/registrar.pem \
	  $(IMAGE)
