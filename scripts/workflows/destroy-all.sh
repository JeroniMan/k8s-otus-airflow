# scripts/workflows/destroy-all.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log STEP "ПОЛНОЕ УДАЛЕНИЕ ИНФРАСТРУКТУРЫ"

log WARN "Это удалит ВСЮ инфраструктуру и данные!"
echo ""
read -p "Вы уверены? Введите 'yes' для подтверждения: " confirm

if [ "$confirm" != "yes" ]; then
    log INFO "Отменено"
    exit 0
fi

# Создание backup перед удалением
log INFO "Создание финального backup..."
"${SCRIPT_DIR}/operations/backup-config.sh" || true

# Удаление приложений
log INFO "Удаление Kubernetes приложений..."
if [ -f "${PROJECT_ROOT}/kubeconfig" ]; then
    export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"
    kubectl delete applications --all -n argocd 2>/dev/null || true
    sleep 30
fi

# Удаление инфраструктуры
log INFO "Удаление инфраструктуры..."
"${SCRIPT_DIR}/infrastructure/terraform-destroy.sh"

# Очистка локальных файлов
log INFO "Очистка локальных файлов..."
rm -f "${PROJECT_ROOT}/kubeconfig"
rm -f "${PROJECT_ROOT}/argocd-password.txt"
rm -f "${PROJECT_ROOT}/terraform-outputs.json"

log SUCCESS "Инфраструктура полностью удалена"