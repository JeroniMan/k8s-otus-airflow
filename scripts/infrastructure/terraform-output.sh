# scripts/infrastructure/terraform-output.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Получение outputs Terraform"

# Валидация
validate_terraform_state || exit 1

cd "${TERRAFORM_DIR}"

# Вывод всех outputs
terraform output

# Сохранение в JSON
terraform output -json > "${PROJECT_ROOT}/terraform-outputs.json"

log SUCCESS "Outputs сохранены в terraform-outputs.json"