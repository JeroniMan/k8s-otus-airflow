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
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ========== STAGE 0: Prerequisites ==========

.PHONY: fix-permissions
fix-permissions: ## Fix script permissions
	@echo "Fixing script permissions..."
	@find scripts -name "*.sh" -type f -exec chmod +x {} \;
	@echo "✓ All scripts are now executable"

.PHONY: check
check: fix-permissions ## Check all prerequisites
	@scripts/00-prerequisites/01-check-tools.sh

.PHONY: check-env
check-env: ## Check .env file
	@scripts/00-prerequisites/check-env.sh

.PHONY: check-s3-creds
check-s3-creds: ## Check S3 credentials
	@scripts/00-prerequisites/check-s3-creds.sh

.PHONY: check-yc-key
check-yc-key: ## Check Yandex Cloud service account key
	@scripts/00-prerequisites/check-yc-key.sh

.PHONY: install-tools
install-tools: ## Install required tools
	@scripts/00-prerequisites/02-install-tools.sh

.PHONY: setup-yc
setup-yc: ## Setup Yandex Cloud CLI
	@scripts/00-prerequisites/03-setup-yc.sh

.PHONY: init
init: fix-permissions check install-tools setup-yc ## Initialize environment (fix permissions + check + install + setup)
	@echo "✓ Environment initialized"

# ========== STAGE 1: Infrastructure ==========

.PHONY: check-resources
check-resources: ## Check existing Yandex Cloud resources
	@scripts/01-infrastructure/check-resources.sh

.PHONY: cleanup-old
cleanup-old: ## Cleanup old Yandex Cloud resources
	@scripts/01-infrastructure/cleanup-old-resources.sh

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

.PHONY: tf-output
tf-output: ## Show Terraform outputs
	@cd infrastructure/terraform && terraform output

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
cleanup: ## Cleanup Kubernetes resources
	@scripts/05-operations/04-cleanup.sh

.PHONY: health-check
health-check: ## Check system health
	@scripts/05-operations/health-check.sh

.PHONY: troubleshoot
troubleshoot: ## Troubleshoot cluster issues
	@scripts/05-operations/05-troubleshoot.sh

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

.PHONY: deploy-quick
deploy-quick: ## 🚀 Quick deployment (skip confirmations)
	@scripts/workflows/quick-deploy.sh

.PHONY: destroy
destroy: ## 💥 Destroy everything
	@scripts/workflows/destroy-all.sh

.PHONY: destroy-emergency
destroy-emergency: ## 💥 Emergency destroy (when normal destroy fails)
	@scripts/workflows/emergency-destroy.sh

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
	MASTER_IP=$$(terraform output -json master_ips 2>/dev/null | jq -r '.["master-0"].public_ip' || echo "N/A") && \
	if [ "$$MASTER_IP" != "N/A" ]; then \
		ssh -i ~/.ssh/k8s-airflow ubuntu@$$MASTER_IP; \
	else \
		echo "Master IP not found. Run 'make tf-output' to check."; \
	fi

# ========== Monitoring ==========

.PHONY: logs-airflow
logs-airflow: ## Show Airflow scheduler logs
	kubectl logs -n airflow -l component=scheduler --tail=50 -f

.PHONY: logs-argocd
logs-argocd: ## Show ArgoCD server logs
	kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50 -f

.PHONY: status
status: ## Show cluster status
	@echo "=== Nodes ==="
	@kubectl get nodes || echo "Cluster not accessible"
	@echo "\n=== ArgoCD Applications ==="
	@kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD not installed"
	@echo "\n=== Airflow Pods ==="
	@kubectl get pods -n airflow 2>/dev/null || echo "Airflow not installed"
	@echo "\n=== Monitoring Pods ==="
	@kubectl get pods -n monitoring 2>/dev/null || echo "Monitoring not installed"

.PHONY: events
events: ## Show recent Kubernetes events
	kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# ========== Utilities ==========

.PHONY: validate
validate: ## Validate configurations
	@echo "Validating Terraform..."
	@cd infrastructure/terraform && terraform validate
	@echo "Validating Kubernetes manifests..."
	@find kubernetes/ -name '*.yaml' -exec kubeval {} \; 2>/dev/null || echo "kubeval not installed"

.PHONY: cost-estimate
cost-estimate: ## Estimate infrastructure costs
	@echo "Estimated daily costs (RUB):"
	@echo "  Minimal (3 VMs, preemptible):  ~70-100 RUB/day"
	@echo "  Standard (3 VMs, regular):      ~150-200 RUB/day"
	@echo "  Production (6 VMs, regular):    ~300-500 RUB/day"
	@echo ""
	@echo "Current configuration:"
	@cd infrastructure/terraform && \
	grep -E "preemptible|worker_count|master_count" terraform.tfvars 2>/dev/null || \
	echo "  Run 'make tf-apply' to see actual configuration"

.PHONY: test-apps
test-apps: ## Test deployed applications
	@echo "Testing applications..."
	@scripts/05-operations/test-endpoints.sh 2>/dev/null || echo "Test script not found"

# ========== Development ==========

.PHONY: fmt
fmt: ## Format Terraform files
	@cd infrastructure/terraform && terraform fmt -recursive

.PHONY: lint
lint: ## Lint Ansible playbooks
	@ansible-lint infrastructure/ansible/playbooks/*.yml 2>/dev/null || echo "ansible-lint not installed"

.PHONY: clean
clean: ## Clean temporary files
	@echo "Cleaning temporary files..."
	@find . -name "*.bak" -delete
	@find . -name "*.tmp" -delete
	@find . -name "*.log" -delete
	@find infrastructure/terraform -name "*.tfplan" -delete
	@rm -rf infrastructure/terraform/.terraform.lock.hcl.backup
	@echo "✓ Cleaned"

# ========== Help Targets ==========

.PHONY: help-quick
help-quick: ## Show quick start guide
	@echo "Quick Start Guide:"
	@echo "  1. cp .env.example .env"
	@echo "  2. Edit .env with your values"
	@echo "  3. make init"
	@echo "  4. make deploy"
	@echo ""
	@echo "To destroy:"
	@echo "  make destroy"

.PHONY: help-troubleshoot
help-troubleshoot: ## Show troubleshooting guide
	@echo "Troubleshooting:"
	@echo "  make check              - Check prerequisites"
	@echo "  make check-env          - Verify .env file"
	@echo "  make check-resources    - Show YC resources"
	@echo "  make status             - Show cluster status"
	@echo "  make troubleshoot       - Run diagnostics"
	@echo "  make logs-airflow       - Show Airflow logs"
	@echo "  make events             - Show K8s events"