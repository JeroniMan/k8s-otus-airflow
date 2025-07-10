# scripts/access/port-forward-airflow.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Port-forward для Airflow"

# Валидация
validate_kubeconfig || exit 1

log INFO "Открытие доступа к Airflow UI..."
log INFO "URL: http://localhost:8080"
log INFO "Username: admin"
log INFO "Password: admin"
log INFO ""
log INFO "Нажмите Ctrl+C для остановки"

create_port_forward airflow airflow-webserver 8080 8080