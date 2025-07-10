# scripts/infrastructure/terraform-plan.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/yandex-cloud.sh"

log STEP "Планирование изменений Terraform"

# Загрузка окружения и валидация
load_env || exit 1
validate_env_vars || exit 1
validate_terraform_state || exit 1

# Экспорт S3 credentials
export_s3_credentials || exit 1

cd "${TERRAFORM_DIR}"

# Создание плана
log INFO "Создание плана изменений..."
terraform plan -out=tfplan

log SUCCESS "План создан: tfplan"
log INFO "Для применения выполните: make infra-apply"