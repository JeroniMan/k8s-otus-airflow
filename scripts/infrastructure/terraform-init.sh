# scripts/infrastructure/terraform-init.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/yandex-cloud.sh"

log STEP "Инициализация Terraform"

# Загрузка окружения и валидация
load_env || exit 1
validate_env_vars || exit 1
validate_tools terraform || exit 1

# Экспорт S3 credentials
export_s3_credentials || exit 1

cd "${TERRAFORM_DIR}"

# Обновление bucket в конфигурации
if [ -n "${TF_STATE_BUCKET}" ]; then
    log INFO "Обновление S3 bucket в main.tf"
    sed -i.bak "s/bucket[[:space:]]*=[[:space:]]*\"[^\"]*\"/bucket   = \"${TF_STATE_BUCKET}\"/" main.tf
fi

# Создание terraform.tfvars если не существует
if [ ! -f terraform.tfvars ]; then
    log INFO "Создание terraform.tfvars"
    cat > terraform.tfvars << EOF
yc_cloud_id          = "${YC_CLOUD_ID}"
yc_folder_id         = "${YC_FOLDER_ID}"
yc_zone              = "${YC_ZONE:-ru-central1-a}"
ssh_public_key_path  = "${SSH_PUBLIC_KEY_PATH}"
ssh_private_key_path = "${SSH_PRIVATE_KEY_PATH}"

# Конфигурация нод
master_count  = 1
master_cpu    = 2
master_memory = 4
master_disk_size = 50

worker_count  = 2
worker_cpu    = 2
worker_memory = 4
worker_disk_size = 100

# Экономные настройки
disk_type     = "network-hdd"
preemptible   = true
core_fraction = 50
EOF
fi

# Инициализация
if [ -d ".terraform" ]; then
    log INFO "Переконфигурация Terraform..."
    terraform init -reconfigure -upgrade
else
    log INFO "Первичная инициализация Terraform..."
    terraform init -upgrade
fi

log SUCCESS "Terraform инициализирован"