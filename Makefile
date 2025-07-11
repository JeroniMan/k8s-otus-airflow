.PHONY: help
help: ## Show this help
	@echo "Kubernetes + Airflow on k3s (Yandex Cloud VMs)"
	@echo ""
	@echo "Quick start:"
	@echo "  make init          - Initialize environment"
	@echo "  make deploy        - Full deployment"
	@echo "  make destroy       - Destroy everything"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ========== STAGE 0: Prerequisites ==========

.PHONY: check
check: ## Check all prerequisites
	@scripts/00-prerequisites/01-check-tools.sh

.PHONY: install-tools
install-tools: ## Install required tools
	@scripts/00-prerequisites/02-install-tools.sh

.PHONY: setup-yc
setup-yc: ## Setup Yandex Cloud CLI
	@scripts/00-prerequisites/03-setup-yc.sh

.PHONY: init
init: check install-tools setup-yc ## Initialize environment (check + install + setup)
	@echo "✓ Environment initialized"

# ========== STAGE 1: Infrastructure ==========

.PHONY: create-buckets
create-buckets: ## Create S3 buckets
	@scripts/01-infrastructure/01-create-s3-bucket.sh

.PHONY: tf-init
tf-init: ## Initialize Terraform
	@scripts/01-infrastructure/02-terraform-init.sh

.PHONY: tf-plan
tf-plan: ## Show Terraform plan
	@cd infrastructure/terraform && terraform plan

.PHONY: tf-apply
tf-apply: ## Apply Terraform configuration
	@scripts/01-infrastructure/03-terraform-apply.sh

.PHONY: tf-destroy
tf-destroy: ## Destroy Terraform infrastructure
	@scripts/01-infrastructure/04-terraform-destroy.sh

.PHONY: infra
infra: create-buckets tf-init tf-apply ## Deploy infrastructure (buckets + terraform)

# ========== STAGE 2: Kubernetes ==========

.PHONY: prepare-nodes
prepare-nodes: ## Prepare nodes for k3s
	@scripts/02-kubernetes/01-prepare-nodes.sh

.PHONY: install-k3s
install-k3s: ## Install k3s cluster
	@scripts/02-kubernetes/02-install-k3s.sh

.PHONY: get-kubeconfig
get-kubeconfig: ## Get kubeconfig from master
	@scripts/02-kubernetes/03-get-kubeconfig.sh

.PHONY: verify-cluster
verify-cluster: ## Verify k3s cluster
	@scripts/02-kubernetes/04-verify-cluster.sh

.PHONY: k8s
k8s: prepare-nodes install-k3s get-kubeconfig verify-cluster ## Setup Kubernetes

# ========== STAGE 3: ArgoCD ==========

.PHONY: install-argocd
install-argocd: ## Install ArgoCD
	@scripts/03-argocd/01-install-argocd.sh

.PHONY: configure-argocd
configure-argocd: ## Configure ArgoCD
	@scripts/03-argocd/02-configure-argocd.sh

.PHONY: apply-projects
apply-projects: ## Apply ArgoCD projects
	@scripts/03-argocd/03-apply-projects.sh

.PHONY: apply-apps
apply-apps: ## Apply ArgoCD applications
	@scripts/03-argocd/04-apply-apps.sh

.PHONY: argocd
argocd: install-argocd configure-argocd apply-projects apply-apps ## Setup ArgoCD

# ========== STAGE 4: Applications ==========

.PHONY: create-secrets
create-secrets: ## Create application secrets
	@scripts/04-applications/01-create-secrets.sh

.PHONY: apply-base
apply-base: ## Apply base resources
	@scripts/04-applications/02-apply-base-resources.sh

.PHONY: sync-apps
sync-apps: ## Sync ArgoCD applications
	@scripts/04-applications/03-sync-apps.sh

.PHONY: verify-apps
verify-apps: ## Verify applications
	@scripts/04-applications/04-verify-apps.sh

.PHONY: apps
apps: create-secrets apply-base sync-apps verify-apps ## Deploy applications

# ========== STAGE 5: Operations ==========

.PHONY: info
info: ## Show access information
	@scripts/05-operations/01-get-access-info.sh

.PHONY: port-forward
port-forward: ## Show port-forward commands
	@scripts/05-operations/02-port-forward.sh

.PHONY: backup
backup: ## Backup configurations
	@scripts/05-operations/03-backup.sh

.PHONY: cleanup
cleanup: ## Cleanup resources
	@scripts/05-operations/04-cleanup.sh

# ========== Main Workflows ==========

.PHONY: deploy
deploy: ## 🚀 Full deployment
	@echo "Starting full deployment..."
	@$(MAKE) infra
	@$(MAKE) k8s
	@$(MAKE) argocd
	@$(MAKE) apps
	@$(MAKE) info
	@echo "✓ Deployment complete!"

.PHONY: destroy
destroy: ## 💥 Destroy everything
	@echo "⚠️  This will destroy all resources!"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		$(MAKE) cleanup; \
		$(MAKE) tf-destroy; \
		echo "✓ All resources destroyed"; \
	else \
		echo "Cancelled"; \
	fi

# ========== Quick Access ==========

.PHONY: pf-airflow
pf-airflow: ## Port-forward Airflow
	kubectl port-forward -n airflow svc/airflow-webserver 8080:8080

.PHONY: pf-grafana
pf-grafana: ## Port-forward Grafana
	kubectl port-forward -n monitoring svc/grafana 3000:80

.PHONY: pf-argocd
pf-argocd: ## Port-forward ArgoCD
	kubectl port-forward -n argocd svc/argocd-server 8080:443

.PHONY: ssh-master
ssh-master: ## SSH to master node
	@cd infrastructure/terraform && \
	MASTER_IP=$$(terraform output -json master_ips | jq -r '.["master-0"].public_ip') && \
	ssh -i ~/.ssh/k8s-airflow ubuntu@$$MASTER_IP

# ========== Utilities ==========

.PHONY: logs-airflow
logs-airflow: ## Show Airflow logs
	kubectl logs -n airflow -l component=scheduler --tail=50 -f

.PHONY: logs-argocd
logs-argocd: ## Show ArgoCD logs
	kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50 -f

.PHONY: status
status: ## Show cluster status
	@echo "=== Nodes ==="
	@kubectl get nodes
	@echo "\n=== ArgoCD Applications ==="
	@kubectl get applications -n argocd
	@echo "\n=== Pods ==="
	@kubectl get pods -n airflow
	@kubectl get pods -n monitoring
	@kubectl get pods -n argocd

.PHONY: validate
validate: ## Validate configurations
	@echo "Validating Terraform..."
	@cd infrastructure/terraform && terraform validate
	@echo "Validating Kubernetes manifests..."
	@find kubernetes/ -name '*.yaml' -exec kubeval {} \; 2>/dev/null || echo "kubeval not installed"