# Local shortcuts. Recipe lines MUST be indented with a TAB.
#
#   make help
#   make template ENV=prod
#   make deploy ENV=dev
#   make hf-diff ENV=staging

CHART ?= myapp
ENV   ?= dev
NS    ?= $(CHART)-$(ENV)
VALUES = environments/$(ENV)/$(CHART).values.yaml
HF     = helmfile -f helmfile/helmfile.yaml.gotmpl -e $(ENV)

# Helm 4 renamed --atomic to --rollback-on-failure
HELM_MAJOR := $(shell helm version --template '{{.Version}}' 2>/dev/null | cut -c2)
ifeq ($(HELM_MAJOR),3)
ROLLBACK_FLAG = --atomic
PLUGIN_FLAGS  =
else
ROLLBACK_FLAG = --rollback-on-failure
PLUGIN_FLAGS  = --verify=false
endif

.DEFAULT_GOAL := help
.PHONY: help tools lint template dry-run diff deploy test uninstall package kind-up kind-down hf-lint hf-template hf-diff hf-apply

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

tools: ## Install the helm-diff plugin (needed by diff and Helmfile)
	helm plugin install https://github.com/databus23/helm-diff $(PLUGIN_FLAGS) || true

# ---------- Plain Helm (one app) ----------

lint: ## helm lint with the ENV values
	helm lint charts/$(CHART) -f $(VALUES) --strict

template: ## Render manifests locally
	helm template $(CHART) charts/$(CHART) -n $(NS) -f $(VALUES)

dry-run: ## Server-side dry run against the current cluster
	helm upgrade --install $(CHART) charts/$(CHART) -n $(NS) --create-namespace -f $(VALUES) --dry-run=server --debug

diff: ## Show what an upgrade would change (needs helm-diff)
	helm diff upgrade $(CHART) charts/$(CHART) -n $(NS) -f $(VALUES) --allow-unreleased

deploy: ## Install or upgrade the app
	helm upgrade --install $(CHART) charts/$(CHART) -n $(NS) --create-namespace -f $(VALUES) --wait $(ROLLBACK_FLAG) --timeout 5m --history-max 10

test: ## Run chart tests
	helm test $(CHART) -n $(NS)

uninstall: ## Remove the release
	helm uninstall $(CHART) -n $(NS)

package: ## Package the chart into .packages/
	helm package charts/$(CHART) --destination .packages

# ---------- Local cluster ----------

kind-up: ## Create a local kind cluster named helm-lab
	kind create cluster --name helm-lab

kind-down: ## Delete the local kind cluster
	kind delete cluster --name helm-lab

# ---------- Helmfile (whole environment) ----------

hf-lint: ## helmfile lint
	$(HF) lint

hf-template: ## Render every release of the environment
	$(HF) template

hf-diff: ## Preview changes for the environment
	$(HF) diff

hf-apply: ## Apply only what changed
	$(HF) apply
