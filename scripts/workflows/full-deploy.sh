# scripts/workflows/full-deploy.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "ПОЛНОЕ РАЗВЕРТЫВАНИЕ СИСТЕМЫ"

# Время начала
START_TIME=$SECONDS

# 1. Проверка окружения
log STEP "1/8 - Проверка окружения"
"${SCRIPT_DIR}/setup/configure-environment.sh"
load_env || exit 1
validate_env_vars || exit 1

# 2. Создание S3 bucket
log STEP "2/8 - Создание S3 bucket"
"${SCRIPT_DIR}/infrastructure/create-s3-bucket.sh"

# 3. Terraform
log STEP "3/8 - Создание инфраструктуры"
"${SCRIPT_DIR}/infrastructure/terraform-init.sh"
"${SCRIPT_DIR}/infrastructure/terraform-apply.sh"

# 4. Установка k3s
log STEP "4/8 - Установка Kubernetes"
"${SCRIPT_DIR}/kubernetes/install-k3s.sh"
"${SCRIPT_DIR}/kubernetes/get-kubeconfig.sh"

# 5. Установка ArgoCD
log STEP "5/8 - Установка ArgoCD"
"${SCRIPT_DIR}/kubernetes/install-argocd.sh"

# 6. Создание секретов
log STEP "6/8 - Создание секретов"
"${SCRIPT_DIR}/kubernetes/create-secrets.sh"

# 7. Развертывание приложений
log STEP "7/8 - Развертывание приложений"
"${SCRIPT_DIR}/kubernetes/deploy-apps.sh"

# 8. Ожидание готовности
log STEP "8/8 - Проверка готовности"
sleep 60
"${SCRIPT_DIR}/kubernetes/wait-for-ready.sh"

# Вывод информации о доступе
"${SCRIPT_DIR}/access/print-access-info.sh"

# Время выполнения
ELAPSED_TIME=$((SECONDS - START_TIME))
log SUCCESS "Развертывание завершено за $((ELAPSED_TIME/60)) минут $((ELAPSED_TIME%60)) секунд"