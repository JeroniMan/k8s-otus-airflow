# scripts/04-applications/05-validate-helm-values.sh
#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Validating Helm Values"

# Проверка что все переменные окружения установлены
required_vars=(
    "DOMAIN"
    "LETSENCRYPT_EMAIL"
    "GRAFANA_ADMIN_PASSWORD"
    "AIRFLOW_WEBSERVER_SECRET_KEY"
    "LOKI_S3_BUCKET"
    "S3_ACCESS_KEY"
    "S3_SECRET_KEY"
)

missing_vars=()
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    error "Missing required environment variables: ${missing_vars[*]}"
    exit 1
fi

# Подстановка переменных в values файлы
for values_file in kubernetes/helm-values/**/values.yaml; do
    if [ -f "$values_file" ]; then
        envsubst < "$values_file" > "${values_file}.processed"
        info "Processed: $values_file"
    fi
done

success "Helm values validated and processed"