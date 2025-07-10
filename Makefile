# Makefile - обновленная версия

.PHONY: help
help: ## Показать эту справку
	@echo "Kubernetes + Airflow + Monitoring Stack"
	@echo ""
	@echo "Доступные команды:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Примеры использования:"
	@echo "  make setup              # Установить все инструменты"
	@echo "  make deploy             # Развернуть всю систему"
	@echo "  make status             # Проверить статус"
	@echo "  make destroy            # Удалить всё"

# ==================== SETUP ====================

.PHONY: setup
setup: setup-tools setup-env ## Полная настройка окружения

.PHONY: setup-tools
setup-tools: ## Установить необходимые инструменты
	@scripts/setup/install-prerequisites.sh
	@scripts/setup/install-terraform.sh
	@scripts/setup/install-ansible.sh
	@scripts/setup/install-k8s-tools.sh
	@scripts/setup/install-yc-cli.sh

.PHONY: setup-env
setup-env: ## Настроить окружение
	@scripts/setup/configure-environment.sh

# ==================== INFRASTRUCTURE ====================

.PHONY: infrastructure
infrastructure: infra-init infra-apply ## Создать всю инфраструктуру

.PHONY: infra-init
infra-init: ## Инициализировать Terraform
	@scripts/infrastructure/create-s3-bucket.sh
	@scripts/infrastructure/terraform-init.sh

.PHONY: infra-plan
infra-plan: ## Показать план Terraform
	@scripts/infrastructure/terraform-plan.sh

.PHONY: infra-apply
infra-apply: ## Применить изменения Terraform
	@scripts/infrastructure/terraform-apply.sh

.PHONY: infra-destroy
infra-destroy: ## Удалить инфраструктуру Terraform
	@scripts/infrastructure/terraform-destroy.sh

.PHONY: infra-output
infra-output: ## Показать outputs Terraform
	@scripts/infrastructure/terraform-output.sh

# ==================== KUBERNETES ====================

.PHONY: kubernetes
kubernetes: k8s-install k8s-config ## Установить и настроить Kubernetes

.PHONY: k8s-install
k8s-install: ## Установить k3s
	@scripts/kubernetes/install-k3s.sh

.PHONY: k8s-config
k8s-config: ## Получить kubeconfig
	@scripts/kubernetes/get-kubeconfig.sh

.PHONY: k8s-verify
k8s-verify: ## Проверить кластер
	@export KUBECONFIG=${PWD}/kubeconfig && kubectl get nodes

# ==================== APPLICATIONS ====================

.PHONY: applications
applications: apps-argocd apps-secrets apps-deploy ## Развернуть все приложения

.PHONY: apps-argocd
apps-argocd: ## Установить ArgoCD
	@scripts/kubernetes/install-argocd.sh

.PHONY: apps-secrets
apps-secrets: ## Создать секреты
	@scripts/kubernetes/create-secrets.sh

.PHONY: apps-deploy
apps-deploy: ## Развернуть приложения через ArgoCD
	@scripts/kubernetes/deploy-apps.sh

.PHONY: apps-status
apps-status: ## Показать статус приложений
	@scripts/monitoring/check-apps-status.sh

.PHONY: apps-wait
apps-wait: ## Дождаться готовности приложений
	@scripts/kubernetes/wait-for-ready.sh

# ==================== MAIN WORKFLOWS ====================

.PHONY: deploy
deploy: ## 🚀 Развернуть всю систему
	@scripts/workflows/full-deploy.sh

.PHONY: quick-start
quick-start: ## ⚡ Быстрый старт с установкой инструментов
	@scripts/workflows/quick-start.sh

.PHONY: production
production: ## 🏭 Production развертывание
	@scripts/workflows/production-deploy.sh

.PHONY: destroy
destroy: ## 💥 Удалить всю инфраструктуру
	@scripts/workflows/destroy-all.sh

# ==================== OPERATIONS ====================

.PHONY: backup
backup: ## 💾 Создать backup конфигураций
	@scripts/operations/backup-config.sh

.PHONY: restore
restore: ## 📥 Восстановить из backup
	@scripts/operations/restore-config.sh

.PHONY: cleanup
cleanup: ## 🧹 Очистить временные ресурсы
	@scripts/operations/cleanup-resources.sh

.PHONY: emergency-cleanup
emergency-cleanup: ## 🚨 Экстренная очистка всего
	@scripts/operations/emergency-cleanup.sh

.PHONY: debug
debug: ## 🐛 Собрать отладочную информацию
	@scripts/operations/debug-cluster.sh

# ==================== MONITORING ====================

.PHONY: status
status: ## 📊 Показать общий статус системы
	@scripts/monitoring/check-cluster-status.sh
	@scripts/monitoring/check-apps-status.sh

.PHONY: health
health: ## 🏥 Проверить здоровье системы
	@scripts/operations/health-check.sh

.PHONY: metrics
metrics: ## 📈 Показать метрики
	@scripts/monitoring/get-metrics.sh

.PHONY: alerts
alerts: ## 🔔 Проверить алерты
	@scripts/monitoring/test-alerts.sh

# ==================== ACCESS ====================

.PHONY: access-info
access-info: ## 🔑 Показать информацию о доступе
	@scripts/access/print-access-info.sh

.PHONY: passwords
passwords: ## 🔐 Показать все пароли
	@scripts/access/get-passwords.sh

.PHONY: port-forward
port-forward: ## 🌐 Инструкции для port-forward
	@echo "Доступные команды:"
	@echo "  make port-forward-airflow   # Airflow UI на localhost:8080"
	@echo "  make port-forward-grafana   # Grafana на localhost:3000"
	@echo "  make port-forward-argocd    # ArgoCD на localhost:8080"

.PHONY: port-forward-airflow
port-forward-airflow: ## 🌬️ Port-forward для Airflow
	@scripts/access/port-forward-airflow.sh

.PHONY: port-forward-grafana
port-forward-grafana: ## 📊 Port-forward для Grafana
	@scripts/access/port-forward-grafana.sh

.PHONY: port-forward-argocd
port-forward-argocd: ## 🔄 Port-forward для ArgoCD
	@scripts/access/port-forward-argocd.sh

# ==================== DEVELOPMENT ====================

.PHONY: sync-dags
sync-dags: ## 🔄 Синхронизировать DAGs
	@scripts/development/sync-dags.sh

.PHONY: test-dag
test-dag: ## 🧪 Тестировать DAG
	@scripts/development/test-dag.sh $(DAG_ID) $(TASK_ID)

.PHONY: reload-airflow
reload-airflow: ## 🔄 Перезагрузить Airflow
	@scripts/development/reload-config.sh

.PHONY: local-dev
local-dev: ## 💻 Настроить локальную разработку
	@scripts/development/local-dev-setup.sh

# ==================== VALIDATION ====================

.PHONY: validate
validate: ## ✅ Валидировать конфигурации
	@echo "Проверка Terraform..."
	@cd infrastructure/terraform && terraform fmt -check -recursive
	@cd infrastructure/terraform && terraform validate
	@echo "Проверка Kubernetes манифестов..."
	@find kubernetes/ -name '*.yaml' -o -name '*.yml' | xargs kubeval --ignore-missing-schemas 2>/dev/null || echo "kubeval не установлен"
	@echo "Проверка Python..."
	@python3 -m py_compile airflow/dags/*.py

# ==================== SHORTCUTS ====================

.PHONY: tf-init
tf-init: infra-init ## Alias для infra-init

.PHONY: tf-plan
tf-plan: infra-plan ## Alias для infra-plan

.PHONY: tf-apply
tf-apply: infra-apply ## Alias для infra-apply

.PHONY: tf-destroy
tf-destroy: infra-destroy ## Alias для infra-destroy

.PHONY: k-get-nodes
k-get-nodes: ## Показать ноды кластера
	@export KUBECONFIG=${PWD}/kubeconfig && kubectl get nodes

.PHONY: k-get-pods
k-get-pods: ## Показать все поды
	@export KUBECONFIG=${PWD}/kubeconfig && kubectl get pods --all-namespaces

.PHONY: k-get-apps
k-get-apps: ## Показать ArgoCD приложения
	@export KUBECONFIG=${PWD}/kubeconfig && kubectl get applications -n argocd

# ==================== LOGS ====================

.PHONY: logs-airflow
logs-airflow: ## 📜 Логи Airflow
	@export KUBECONFIG=${PWD}/kubeconfig && kubectl logs -n airflow -l component=scheduler --tail=50 -f

.PHONY: logs-argocd
logs-argocd: ## 📜 Логи ArgoCD
	@export KUBECONFIG=${PWD}/kubeconfig && kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50 -f

.PHONY: logs-ingress
logs-ingress: ## 📜 Логи Ingress
	@export KUBECONFIG=${PWD}/kubeconfig && kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50 -f