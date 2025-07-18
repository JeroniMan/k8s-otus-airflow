#!/bin/bash
# scripts/workflows/full-deploy.sh

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

step "ПОЛНОЕ РАЗВЕРТЫВАНИЕ СИСТЕМЫ"

# Время начала
START_TIME=$SECONDS

# 1. Проверка окружения
step "1/8 - Проверка окружения"
if [ ! -f "${PROJECT_ROOT}/.env" ]; then
    error ".env файл не найден!"
    info "Скопируйте .env.example в .env и заполните переменные"
    exit 1
fi

load_env || exit 1

# Проверка обязательных переменных
info "Проверка переменных окружения..."
REQUIRED_VARS=(
    "YC_CLOUD_ID"
    "YC_FOLDER_ID"
    "SSH_PUBLIC_KEY_PATH"
    "SSH_PRIVATE_KEY_PATH"
    "TF_STATE_BUCKET"
)

all_set=true
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        error "$var не установлена в .env"
        all_set=false
    else
        success "$var установлена"
    fi
done

if [ "$all_set" = "false" ]; then
    error "Не все обязательные переменные установлены"
    exit 1
fi

# 2. Создание S3 bucket и service accounts
step "2/8 - Создание S3 buckets и service accounts"
"${SCRIPT_DIR}/../01-infrastructure/01-create-s3-bucket.sh"

# Перезагрузка env для получения новых ключей
load_env || exit 1

# 3. Terraform
step "3/8 - Создание инфраструктуры"
"${SCRIPT_DIR}/../01-infrastructure/02-terraform-init.sh"
"${SCRIPT_DIR}/../01-infrastructure/03-terraform-apply.sh"

# 4. Установка k3s
step "4/8 - Установка Kubernetes"
"${SCRIPT_DIR}/../02-kubernetes/01-prepare-nodes.sh"
"${SCRIPT_DIR}/../02-kubernetes/02-install-k3s.sh"
"${SCRIPT_DIR}/../02-kubernetes/03-get-kubeconfig.sh"
"${SCRIPT_DIR}/../02-kubernetes/04-verify-cluster.sh"

# 5. Установка ArgoCD
step "5/8 - Установка ArgoCD"
"${SCRIPT_DIR}/../03-argocd/01-install-argocd.sh"
"${SCRIPT_DIR}/../03-argocd/02-configure-argocd.sh"
"${SCRIPT_DIR}/../03-argocd/03-apply-projects.sh"
"${SCRIPT_DIR}/../03-argocd/04-apply-apps.sh"

# 6. Создание секретов
step "6/8 - Создание секретов"
"${SCRIPT_DIR}/../04-applications/01-create-secrets.sh"

# 7. Развертывание приложений
step "7/8 - Развертывание приложений"
"${SCRIPT_DIR}/../04-applications/02-apply-base-resources.sh"
"${SCRIPT_DIR}/../04-applications/03-sync-apps.sh"

# 8. Ожидание готовности и проверка
step "8/8 - Проверка готовности"
sleep 60
"${SCRIPT_DIR}/../04-applications/04-verify-apps.sh"

# Вывод информации о доступе
"${SCRIPT_DIR}/../05-operations/01-get-access-info.sh"

# Сохранение информации о развертывании
DEPLOYMENT_INFO="${PROJECT_ROOT}/.artifacts/deployment-info.json"
cat > "$DEPLOYMENT_INFO" << EOF
{
  "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "duration_seconds": $((SECONDS - START_TIME)),
  "terraform_state_bucket": "$TF_STATE_BUCKET",
  "loki_bucket": "$LOKI_S3_BUCKET",
  "cluster_name": "${PROJECT_NAME:-k8s-airflow}-${ENVIRONMENT:-prod}",
  "artifacts_dir": "${PROJECT_ROOT}/.artifacts"
}
EOF

# Время выполнения
ELAPSED_TIME=$((SECONDS - START_TIME))
success "Развертывание завершено за $((ELAPSED_TIME/60)) минут $((ELAPSED_TIME%60)) секунд"
info "Артефакты сохранены в: ${PROJECT_ROOT}/.artifacts/"
info "Для удаления всей инфраструктуры: make destroy"