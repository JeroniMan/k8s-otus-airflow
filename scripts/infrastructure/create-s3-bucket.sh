# scripts/infrastructure/create-s3-bucket.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/yandex-cloud.sh"

log STEP "Создание S3 bucket для Terraform state"

# Загрузка окружения и валидация
load_env || exit 1
validate_env_vars || exit 1
validate_yc_config || exit 1

# Создание bucket
if [ -z "${TF_STATE_BUCKET}" ]; then
    log ERROR "TF_STATE_BUCKET не задан в .env"
    exit 1
fi

create_s3_bucket "${TF_STATE_BUCKET}"

log SUCCESS "S3 bucket готов: ${TF_STATE_BUCKET}"