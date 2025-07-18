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

# ========== Service Account Management ==========

.PHONY: setup-sa
setup-sa: ## Setup all service accounts
	@scripts/00-prerequisites/04-setup-service-accounts.sh

.PHONY: check-sa
check-sa: ## Check service accounts status
	@echo "Checking service accounts..."
	@yc iam service-account list --format=table
	@echo ""
	@if [ -f ".artifacts/check-service-accounts.sh" ]; then \
		.artifacts/check-service-accounts.sh; \
	else \
		echo "Run 'make setup-sa' first"; \
	fi

.PHONY: fix-env
fix-env: ## Fix environment issues
	@scripts/00-prerequisites/05-check-environment.sh

.PHONY: init-complete
init-complete: ## Complete initialization from scratch
	@scripts/00-prerequisites/00-init-all.sh

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

# ========== External Access ==========

.PHONY: configure-access
configure-access: ## Configure external access to applications
	@scripts/04-applications/05-configure-external-access.sh

.PHONY: show-urls
show-urls: ## Show all application URLs
	@echo "Application URLs:"
	@echo ""
	@LB_IP=$$(cd infrastructure/terraform && terraform output -raw load_balancer_ip 2>/dev/null || echo "N/A"); \
	if [ "$$LB_IP" != "N/A" ]; then \
		echo "Load Balancer IP: $$LB_IP"; \
		echo ""; \
		echo "Via Ingress (recommended):"; \
		echo "  Airflow: http://$$LB_IP:32080"; \
		echo "  Grafana: http://$$LB_IP:32080/grafana"; \
		echo "  ArgoCD:  http://$$LB_IP:32080/argocd"; \
		echo ""; \
		echo "Direct NodePort access:"; \
		echo "  Airflow: http://$$LB_IP:30880"; \
		echo "  Grafana: http://$$LB_IP:30300"; \
		echo ""; \
		echo "Credentials:"; \
		echo "  Airflow: admin / admin"; \
		echo "  Grafana: admin / changeme123"; \
		if [ -f "argocd-password.txt" ]; then \
			echo "  ArgoCD:  admin / $$(cat argocd-password.txt)"; \
		fi; \
	else \
		echo "Load Balancer not found. Run 'make tf-apply' first."; \
	fi

.PHONY: test-access
test-access: ## Test external access to all services
	@if [ -f "check-services.sh" ]; then \
		./check-services.sh; \
	else \
		LB_IP=$$(cd infrastructure/terraform && terraform output -raw load_balancer_ip 2>/dev/null || echo "N/A"); \
		if [ "$$LB_IP" != "N/A" ]; then \
			echo "Testing service availability..."; \
			echo ""; \
			curl -s -o /dev/null -w "Airflow (Ingress): %{http_code}\n" http://$$LB_IP:32080 || true; \
			curl -s -o /dev/null -w "Grafana (Ingress): %{http_code}\n" http://$$LB_IP:32080/grafana || true; \
			curl -s -o /dev/null -w "Airflow (Direct):  %{http_code}\n" http://$$LB_IP:30880 || true; \
			curl -s -o /dev/null -w "Grafana (Direct):  %{http_code}\n" http://$$LB_IP:30300 || true; \
		fi; \
	fi

.PHONY: open-airflow
open-airflow: ## Open Airflow in browser
	@LB_IP=$$(cd infrastructure/terraform && terraform output -raw load_balancer_ip 2>/dev/null); \
	if [ -n "$$LB_IP" ]; then \
		echo "Opening Airflow at http://$$LB_IP:32080"; \
		open "http://$$LB_IP:32080" 2>/dev/null || xdg-open "http://$$LB_IP:32080" 2>/dev/null || echo "Please open manually"; \
	else \
		echo "Load Balancer IP not found"; \
	fi

.PHONY: open-grafana
open-grafana: ## Open Grafana in browser
	@LB_IP=$$(cd infrastructure/terraform && terraform output -raw load_balancer_ip 2>/dev/null); \
	if [ -n "$$LB_IP" ]; then \
		echo "Opening Grafana at http://$$LB_IP:32080/grafana"; \
		open "http://$$LB_IP:32080/grafana" 2>/dev/null || xdg-open "http://$$LB_IP:32080/grafana" 2>/dev/null || echo "Please open manually"; \
	else \
		echo "Load Balancer IP not found"; \
	fi

.PHONY: fix-ingress
fix-ingress: ## Fix/reinstall Ingress controller
	@echo "Reinstalling Ingress NGINX controller..."
	@kubectl delete namespace ingress-nginx --ignore-not-found
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml
	@echo "Waiting for controller to be ready..."
	@kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
	@echo "Patching NodePorts..."
	@kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' \
		-p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value":32080}, \
		     {"op": "replace", "path": "/spec/ports/1/nodePort", "value":32443}]'
	@echo "Applying Ingress rules..."
	@kubectl apply -f kubernetes/base/ingress-configuration.yaml || true
	@echo "Ingress controller fixed!"

.PHONY: add-nodeport
add-nodeport: ## Add NodePort services for direct access
	@echo "Creating NodePort services..."
	@kubectl apply -f kubernetes/patches/services-nodeport.yaml
	@echo "NodePort services created!"
	@make show-urls

# ========== Main Workflows ==========

.PHONY: deploy
deploy: ## 🚀 Full deployment
	@echo "Starting full deployment..."
	@$(MAKE) infra
	@$(MAKE) k8s
	@$(MAKE) argocd
	@$(MAKE) apps
	@$(MAKE) configure-access
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

.PHONY: airflow
airflow: ## Quick access to Airflow UI
	@make show-urls | grep -A1 "Via Ingress" | grep Airflow || echo "Run 'make configure-access' first"
	@make open-airflow

.PHONY: grafana
grafana: ## Quick access to Grafana
	@make show-urls | grep -A2 "Via Ingress" | grep Grafana || echo "Run 'make configure-access' first"
	@make open-grafana

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

# ========== Troubleshooting ==========

.PHONY: debug-s3
debug-s3: ## Debug S3 access issues
	@echo "Testing S3 access..."
	@yc storage bucket list || echo "Failed to list buckets"
	@echo ""
	@echo "Current S3 credentials:"
	@grep "ACCESS_KEY\|SECRET_KEY" .env | grep -v "#" | head -4
	@echo ""
	@echo "S3 service account:"
	@yc iam service-account get s3-storage-sa 2>/dev/null || echo "Not found"

.PHONY: debug-terraform
debug-terraform: ## Debug Terraform access issues
	@echo "Testing Terraform service account..."
	@if [ -f "yc-terraform-key.json" ]; then \
		YC_SERVICE_ACCOUNT_KEY_FILE=yc-terraform-key.json yc resource-manager cloud list && \
		echo "✓ Terraform SA works" || echo "✗ Terraform SA failed"; \
	else \
		echo "✗ No terraform key found"; \
	fi

.PHONY: reset-sa
reset-sa: ## Reset and recreate all service accounts
	@echo "WARNING: This will delete and recreate all service accounts!"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "Deleting service accounts..."
	@yc iam service-account delete --name terraform-sa 2>/dev/null || true
	@yc iam service-account delete --name s3-storage-sa 2>/dev/null || true
	@yc iam service-account delete --name k8s-node-sa 2>/dev/null || true
	@yc iam service-account delete --name monitoring-sa 2>/dev/null || true
	@sleep 5
	@echo "Recreating service accounts..."
	@scripts/00-prerequisites/04-setup-service-accounts.sh

# ========== Quick Fixes ==========

.PHONY: fix-s3-keys
fix-s3-keys: ## Regenerate S3 access keys
	@echo "Regenerating S3 access keys..."
	@scripts/00-prerequisites/04-setup-service-accounts.sh
	@echo "Loading new credentials..."
	@source .env && scripts/01-infrastructure/01-create-s3-bucket.sh

.PHONY: restore-from-artifacts
restore-from-artifacts: ## Restore configuration from artifacts
	@echo "Restoring from artifacts..."
	@if [ -f ".artifacts/terraform-sa-key.json" ]; then \
		cp .artifacts/terraform-sa-key.json yc-terraform-key.json && \
		echo "✓ Restored Terraform key"; \
	fi
	@if [ -f ".artifacts/s3-keys.json" ]; then \
		ACCESS_KEY=$$(jq -r '.access_key' .artifacts/s3-keys.json) && \
		SECRET_KEY=$$(jq -r '.secret_key' .artifacts/s3-keys.json) && \
		sed -i.bak '/^export ACCESS_KEY=/d' .env && \
		sed -i.bak '/^export SECRET_KEY=/d' .env && \
		echo "export ACCESS_KEY=\"$$ACCESS_KEY\"" >> .env && \
		echo "export SECRET_KEY=\"$$SECRET_KEY\"" >> .env && \
		echo "✓ Restored S3 keys"; \
	fi

# ========== DNS and Domain Configuration ==========

.PHONY: configure-domain
configure-domain: ## Configure domain name for services
	@read -p "Enter your domain name (e.g., example.com): " domain; \
	if [ -n "$$domain" ]; then \
		LB_IP=$$(cd infrastructure/terraform && terraform output -raw load_balancer_ip); \
		echo ""; \
		echo "Add these DNS records to your domain:"; \
		echo "  A    airflow.$$domain    → $$LB_IP"; \
		echo "  A    grafana.$$domain    → $$LB_IP"; \
		echo "  A    argocd.$$domain     → $$LB_IP"; \
		echo ""; \
		echo "Then run: make apply-domain-ingress DOMAIN=$$domain"; \
	fi

.PHONY: apply-domain-ingress
apply-domain-ingress: ## Apply Ingress with domain names
	@if [ -z "$(DOMAIN)" ]; then \
		echo "Usage: make apply-domain-ingress DOMAIN=example.com"; \
		exit 1; \
	fi; \
	echo "Applying Ingress for domain $(DOMAIN)..."; \
	cat kubernetes/base/ingress-configuration.yaml | \
		sed "s/# host: .*/host: airflow.$(DOMAIN)/" | \
		kubectl apply -f -

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
	@echo "  3. make init-complete"
	@echo "  4. make deploy"
	@echo "  5. make show-urls"
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
	@echo "  make debug-s3           - Debug S3 access"
	@echo "  make debug-terraform    - Debug Terraform SA"
	@echo "  make fix-ingress        - Fix Ingress controller"