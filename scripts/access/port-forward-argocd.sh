# scripts/access/port-forward-argocd.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Port-forward для ArgoCD"

# Валидация
validate_kubeconfig || exit 1

# Получение пароля
ARGOCD_PASS="N/A"
if [ -f "${PROJECT_ROOT}/argocd-password.txt" ]; then
    ARGOCD_PASS=$(cat "${PROJECT_ROOT}/argocd-password.txt")
else
    ARGOCD_PASS=$(get_secret_value argocd argocd-initial-admin-secret password 2>/dev/null || echo "N/A")
fi

log INFO "Открытие доступа к ArgoCD UI..."
log INFO "URL: https://localhost:8080"
log INFO "Username: admin"
log INFO "Password: ${ARGOCD_PASS}"
log INFO ""
log WARN "Браузер может показать предупреждение о сертификате - это нормально"
log INFO ""
log INFO "Нажмите Ctrl+C для остановки"

create_port_forward argocd argocd-server 8080 443