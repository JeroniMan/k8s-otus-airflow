# scripts/development/reload-config.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Перезагрузка конфигурации Airflow"

# Валидация
validate_kubeconfig || exit 1

# Перезапуск подов Airflow
log INFO "Перезапуск Airflow компонентов..."

kubectl rollout restart deployment airflow-webserver -n airflow
kubectl rollout restart deployment airflow-scheduler -n airflow
kubectl rollout restart statefulset airflow-worker -n airflow

log INFO "Ожидание готовности..."
kubectl rollout status deployment airflow-webserver -n airflow
kubectl rollout status deployment airflow-scheduler -n airflow

log SUCCESS "Конфигурация перезагружена"