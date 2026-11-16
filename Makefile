# Local tasks. Containers run with Podman (set CONTAINER=docker to use Docker).
CONTAINER ?= podman
IMAGE ?= gh-runner:local
PROXY_IMAGE ?= egress-proxy:local
HADOLINT_IMAGE = ghcr.io/hadolint/hadolint:v2.15.1
# For the push targets: the azd environment's registry, and the commit the images are built from.
REGISTRY_NAME = $(firstword $(subst ., ,$(shell azd env get-value AZURE_CONTAINER_REGISTRY_ENDPOINT)))
TAG ?= $(shell git rev-parse --short HEAD)

.PHONY: lint build test run-local build-proxy test-proxy test-infra push-runner push-proxy

lint:  ## shellcheck and hadolint
	shellcheck -x runner/entrypoint.sh runner/tests/test-entrypoint.sh egress-proxy/tests/test-proxy.sh
	$(CONTAINER) run --rm -i $(HADOLINT_IMAGE) < runner/Dockerfile
	$(CONTAINER) run --rm -i $(HADOLINT_IMAGE) < egress-proxy/Dockerfile

build:  ## the runner image, for linux/amd64
	$(CONTAINER) build --platform linux/amd64 -t $(IMAGE) runner

test: build  ## the added tools start, sudo keeps the proxy settings, and the entrypoint's offline tests pass, in the image
	$(CONTAINER) run --rm --entrypoint bash $(IMAGE) -c 'az version --output none && gh --version && node --version && npm --version && uv --version && uv python find 3.12'
	$(CONTAINER) run --rm --entrypoint bash -e HTTPS_PROXY=http://proxy.test:3128 $(IMAGE) -c 'test "$$(sudo -n printenv HTTPS_PROXY)" = http://proxy.test:3128'
	$(CONTAINER) run --rm --entrypoint bash -v "$(CURDIR)/runner:/tests:ro,Z" $(IMAGE) /tests/tests/test-entrypoint.sh

run-local: build  ## register one JIT runner from this machine (local test mode, runner/README.md); needs runner/.env
	$(CONTAINER) run --rm --env-file runner/.env \
	  -v "$(GH_REGISTRAR_KEY_FILE):/run/secrets/registrar.pem:ro,Z" -e GH_REGISTRAR_KEY_FILE=/run/secrets/registrar.pem \
	  $(IMAGE)

build-proxy:  ## the egress proxy image, for linux/amd64
	$(CONTAINER) build --platform linux/amd64 -t $(PROXY_IMAGE) egress-proxy

test-proxy: build-proxy  ## allowlisted domains pass through the proxy, others are denied (needs internet access)
	egress-proxy/tests/test-proxy.sh $(CONTAINER) $(PROXY_IMAGE)

test-infra:  ## Terraform offline: format, validation, tflint, Trivy (.trivyignore.yaml) and the tests with mock providers
	terraform -chdir=infra fmt -check -recursive
	terraform -chdir=infra init -backend=false -input=false >/dev/null
	terraform -chdir=infra validate
	cd infra && tflint --init >/dev/null && tflint --recursive --config "$$PWD/.tflint.hcl"
	trivy config --quiet --exit-code 1 --severity MEDIUM,HIGH,CRITICAL --ignorefile .trivyignore.yaml .
	terraform -chdir=infra test
	for module in infra/modules/*/; do terraform -chdir="$$module" init -backend=false -input=false >/dev/null && terraform -chdir="$$module" test || exit 1; done

push-runner:  ## build the runner image in the registry (ACR Tasks), tagged with the commit; then RUNNER_IMAGE_TAG=$(TAG)
	az acr build --registry $(REGISTRY_NAME) --platform linux/amd64 --image gh-runner:$(TAG) runner

push-proxy:  ## build the egress proxy image in the registry, tagged with the commit; then EGRESS_PROXY_IMAGE_TAG=$(TAG)
	az acr build --registry $(REGISTRY_NAME) --platform linux/amd64 --image egress-proxy:$(TAG) egress-proxy
