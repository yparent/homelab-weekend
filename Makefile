# Shortcuts for the weekend. Each target prints nothing magic: open this file
# to see the exact command, the docs explain every one of them.
#   make help

SHELL := /bin/bash
.DEFAULT_GOAL := help

TOFU_SECRETS := secrets/tofu.enc.env
LAB_SECRETS  := secrets/lab.enc.env
KUBECONFIG_ADMIN := $(CURDIR)/kubeconfig/homelab.yaml
KUBECONFIG_AI    := $(CURDIR)/kubeconfig/homelab-ai-readonly.yaml
KPS_VERSION := 93.11.0

.PHONY: help init plan apply destroy rebuild forget-hostkeys ansible k3s \
        monitoring alerts demo ai-readonly lint weekend-up

help: ## List the targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-16s %s\n", $$1, $$2}'

## ---- Saturday ----
init: ## tofu init with the state outside the repo (opentofu/backend.hcl)
	cd opentofu && tofu init -backend-config=backend.hcl

plan: ## tofu plan (Proxmox token decrypted on the fly by sops)
	cd opentofu && sops exec-env ../$(TOFU_SECRETS) 'tofu plan'

apply: ## tofu apply: create / update the VMs and the Ansible inventory
	cd opentofu && sops exec-env ../$(TOFU_SECRETS) 'tofu apply'

destroy: ## tofu destroy: delete the VMs
	cd opentofu && sops exec-env ../$(TOFU_SECRETS) 'tofu destroy'

forget-hostkeys: ## Forget the SSH host keys of the old VMs (after a rebuild)
	rm -f ansible/.known_hosts

ansible: ## Base config of every VM (updates, SSH, node_exporter)
	cd ansible && ansible-playbook playbooks/base.yml

rebuild: destroy apply forget-hostkeys ansible ## Saturday test: destroy, apply, Ansible

## ---- Sunday ----
k3s: ## Install k3s on the k3s_server VM and fetch the kubeconfig
	cd ansible && ansible-playbook playbooks/k3s.yml

monitoring: ## kube-prometheus-stack via Helm (Grafana password from sops)
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	sops exec-env $(LAB_SECRETS) 'helm upgrade --install kps prometheus-community/kube-prometheus-stack \
	  --kubeconfig $(KUBECONFIG_ADMIN) --version $(KPS_VERSION) \
	  --namespace monitoring --create-namespace \
	  -f kubernetes/monitoring/values-kube-prometheus-stack.yaml \
	  --set-literal grafana.adminPassword="$$GRAFANA_ADMIN_PASSWORD" --wait --timeout 10m'

alerts: ## Apply the homelab PrometheusRule
	kubectl --kubeconfig $(KUBECONFIG_ADMIN) apply -f kubernetes/monitoring/homelab-alerts.yaml

demo: ## Deploy the healthy demo app
	kubectl --kubeconfig $(KUBECONFIG_ADMIN) apply -f kubernetes/demo-app/

ai-readonly: ## Read-only ServiceAccount + kubeconfig for the AI
	kubectl --kubeconfig $(KUBECONFIG_ADMIN) apply -f kubernetes/ai-readonly/rbac.yaml
	ADMIN_KUBECONFIG=$(KUBECONFIG_ADMIN) OUT=$(KUBECONFIG_AI) bash kubernetes/ai-readonly/make-readonly-kubeconfig.sh

weekend-up: apply forget-hostkeys ansible k3s monitoring alerts demo ## Everything, from zero (next weekend)

## ---- Checks (same as the CI, plus a few) ----
lint: ## fmt/validate, ansible-lint, yamllint, shellcheck, trivy
	cd opentofu && tofu fmt -check -recursive && tofu init -backend=false -input=false >/dev/null && tofu validate
	ansible-lint
	yamllint -s .
	shellcheck host/*.sh host/firewall/*.sh kubernetes/ai-readonly/*.sh
	trivy config --severity HIGH,CRITICAL --exit-code 1 .
