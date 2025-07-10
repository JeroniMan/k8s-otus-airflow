# scripts/access/port-forward-grafana.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Port-forward для Grafana"

# Валидация
validate_kubeconfig || exit 1

log INFO "Открытие доступа к Grafana..."
log INFO "URL: http://localhost:3000"
log INFO "Username: admin"
log INFO "Password: changeme123"
log INFO ""
log INFO "Нажмите Ctrl+C для остановки"

create_port_forward monitoring prometheus-stack-grafana 3000 80