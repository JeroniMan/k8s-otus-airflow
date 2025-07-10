# scripts/workflows/production-deploy.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "PRODUCTION РАЗВЕРТЫВАНИЕ"

# Загрузка окружения
load_env || exit 1

# Изменение конфигурации на production
log INFO "Настройка production конфигурации..."

cd "${TERRAFORM_DIR}"
cat > terraform.tfvars << EOF
yc_cloud_id          = "${YC_CLOUD_ID}"
yc_folder_id         = "${YC_FOLDER_ID}"
yc_zone              = "${YC_ZONE:-ru-central1-a}"
ssh_public_key_path  = "${SSH_PUBLIC_KEY_PATH}"
ssh_private_key_path = "${SSH_PRIVATE_KEY_PATH}"

# Production конфигурация
master_count  = 3          # HA control plane
master_cpu    = 4
master_memory = 8
master_disk_size = 100

worker_count  = 3
worker_cpu    = 4
worker_memory = 8
worker_disk_size = 200

# Production настройки
disk_type     = "network-ssd"
preemptible   = false
core_fraction = 100
EOF

cd "${PROJECT_ROOT}"

# Запуск полного развертывания
"${SCRIPT_DIR}/workflows/full-deploy.sh"

# Дополнительные production настройки
log INFO "Применение production настроек..."

# Включение Network Policies
kubectl apply -f "${K8S_DIR}/manifests/network-policies/" 2>/dev/null || true

# Настройка backup
"${SCRIPT_DIR}/operations/backup-config.sh"

log SUCCESS "Production развертывание завершено"