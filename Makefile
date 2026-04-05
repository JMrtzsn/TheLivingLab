# TheLivingLab Makefile
# Local Kubernetes developer platform (Minimal Viable Platform)

SHELL := /bin/bash
.DEFAULT_GOAL := help

TERRAFORM_DIR := terraform
KUBECONFIG_PATH := $(HOME)/.kube/living-lab-config
export KUBECONFIG := $(KUBECONFIG_PATH)

# Colors
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# ─────────────────────────────────────────────────────────────────────────────
# Platform lifecycle
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: up
up: ## Bootstrap the full platform (cluster + services)
	@chmod +x bootstrap.sh
	@./bootstrap.sh

.PHONY: down
down: ## Tear down the cluster and all resources
	@echo -e "$(YELLOW)Destroying cluster...$(NC)"
	@terraform -chdir=$(TERRAFORM_DIR) destroy -auto-approve
	@echo -e "$(GREEN)Cluster destroyed.$(NC)"

.PHONY: restart
restart: down up ## Destroy and re-create the entire platform

# ─────────────────────────────────────────────────────────────────────────────
# Cluster info
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: status
status: ## Show cluster nodes, all pods, and ArgoCD application status
	@echo -e "\n$(CYAN)── Nodes ──$(NC)"
	@kubectl get nodes -o wide
	@echo -e "\n$(CYAN)── Pods (all namespaces) ──$(NC)"
	@kubectl get pods -A
	@echo -e "\n$(CYAN)── ArgoCD Applications ──$(NC)"
	@kubectl -n argocd get applications 2>/dev/null || echo "ArgoCD not installed"

.PHONY: pods
pods: ## List all pods across all namespaces
	@kubectl get pods -A

.PHONY: nodes
nodes: ## List cluster nodes
	@kubectl get nodes -o wide

.PHONY: kubeconfig
kubeconfig: ## Print the export KUBECONFIG command
	@echo "export KUBECONFIG=$(KUBECONFIG_PATH)"

# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: argocd-password
argocd-password: ## Print the ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

.PHONY: sync
sync: ## Force-sync all ArgoCD applications
	@echo -e "$(CYAN)Syncing all ArgoCD applications...$(NC)"
	@for app in $$(kubectl -n argocd get applications -o jsonpath='{.items[*].metadata.name}'); do \
		echo -e "  Syncing $$app..."; \
		kubectl -n argocd patch application $$app --type merge \
			-p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' 2>&1 || \
			echo "  ($$app may already be syncing)"; \
	done
	@echo -e "$(GREEN)Sync triggered for all applications.$(NC)"

# ─────────────────────────────────────────────────────────────────────────────
# Logs
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: logs-argocd
logs-argocd: ## Tail ArgoCD server logs
	@kubectl -n argocd logs -f deployment/argocd-server

.PHONY: logs-ingress
logs-ingress: ## Tail NGINX Ingress controller logs
	@kubectl -n ingress-nginx logs -f deployment/ingress-nginx-controller

.PHONY: logs-grafana
logs-grafana: ## Tail Grafana logs
	@kubectl -n monitoring logs -f deployment/monitoring-grafana

.PHONY: logs-prometheus
logs-prometheus: ## Tail Prometheus logs
	@kubectl -n monitoring logs -f statefulset/prometheus-monitoring-kube-prometheus-prometheus

# ─────────────────────────────────────────────────────────────────────────────
# Terraform
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: tf-init
tf-init: ## Initialize Terraform providers
	@terraform -chdir=$(TERRAFORM_DIR) init -input=false

.PHONY: tf-plan
tf-plan: ## Show Terraform execution plan
	@terraform -chdir=$(TERRAFORM_DIR) plan

.PHONY: tf-apply
tf-apply: ## Apply Terraform changes (cluster only, no services)
	@terraform -chdir=$(TERRAFORM_DIR) apply -auto-approve -input=false

.PHONY: tf-output
tf-output: ## Show Terraform outputs
	@terraform -chdir=$(TERRAFORM_DIR) output

# ─────────────────────────────────────────────────────────────────────────────
# Port forwarding (alternatives to ingress)
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: pf-argocd
pf-argocd: ## Port-forward ArgoCD to localhost:8080
	@echo -e "$(CYAN)ArgoCD available at http://localhost:8080$(NC)"
	@kubectl -n argocd port-forward svc/argocd-server 8080:80

.PHONY: pf-grafana
pf-grafana: ## Port-forward Grafana to localhost:3000
	@echo -e "$(CYAN)Grafana available at http://localhost:3000$(NC)"
	@kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

.PHONY: pf-prometheus
pf-prometheus: ## Port-forward Prometheus to localhost:9090
	@echo -e "$(CYAN)Prometheus available at http://localhost:9090$(NC)"
	@kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090

# ─────────────────────────────────────────────────────────────────────────────
# Help
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help message
	@echo -e "\n$(CYAN)TheLivingLab$(NC) - Local Kubernetes Developer Platform\n"
	@echo -e "$(GREEN)Usage:$(NC) make <target>\n"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(CYAN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
