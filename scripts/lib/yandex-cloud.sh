# scripts/lib/yandex-cloud.sh
#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Проверка квот Yandex Cloud
check_yc_quotas() {
    log INFO "Проверка квот Yandex Cloud..."

    local quotas=$(yc resource-manager quota list --format json 2>/dev/null || echo "[]")

    if [ "$quotas" != "[]" ]; then
        log INFO "Текущие квоты:"
        echo "$quotas" | jq -r '.[] | "\(.metric): \(.usage)/\(.limit)"' | while read line; do
            log INFO "  $line"
        done
    fi

    return 0
}

# Получение списка зон
get_available_zones() {
    yc compute zone list --format json | jq -r '.[].id'
}

# Проверка доступности ресурсов в зоне
check_zone_availability() {
    local zone=$1

    local availability=$(yc compute zone get --name=$zone --format json 2>/dev/null || echo "{}")
    if [ "$availability" != "{}" ]; then
        return 0
    else
        return 1
    fi
}

# Создание S3 bucket
create_s3_bucket() {
    local bucket_name=$1

    if yc storage bucket get "${bucket_name}" &> /dev/null; then
        log WARN "S3 bucket ${bucket_name} уже существует"
        return 0
    fi

    log INFO "Создание S3 bucket: ${bucket_name}"
    yc storage bucket create \
        --name "${bucket_name}" \
        --default-storage-class standard \
        --max-size 1073741824
}

# Удаление S3 bucket
delete_s3_bucket() {
    local bucket_name=$1

    if ! yc storage bucket get "${bucket_name}" &> /dev/null; then
        log WARN "S3 bucket ${bucket_name} не существует"
        return 0
    fi

    log INFO "Удаление S3 bucket: ${bucket_name}"
    yc storage bucket delete --name "${bucket_name}"
}

# Экспорт credentials для S3
export_s3_credentials() {
    if [ -z "${ACCESS_KEY}" ] || [ -z "${SECRET_KEY}" ]; then
        log ERROR "ACCESS_KEY или SECRET_KEY не установлены"
        return 1
    fi

    export AWS_ACCESS_KEY_ID="${ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${SECRET_KEY}"
}