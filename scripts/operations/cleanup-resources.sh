# scripts/operations/cleanup-resources.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Очистка временных ресурсов"

# Очистка локальных файлов
log INFO "Очистка временных файлов..."

# Terraform
find "${TERRAFORM_DIR}" -name "*.tfplan" -delete 2>/dev/null || true
find "${TERRAFORM_DIR}" -name "tfplan" -delete 2>/dev/null || true
find "${PROJECT_ROOT}" -name "*.bak" -delete 2>/dev/null || true

# Логи
find "${LOG_DIR}" -name "*.log" -mtime +7 -delete 2>/dev/null || true

# Временные директории
rm -rf "${PROJECT_ROOT}"/tmp.* 2>/dev/null || true

# Старые бэкапы (старше 30 дней)
if [ -d "${PROJECT_ROOT}/backups" ]; then
    find "${PROJECT_ROOT}/backups" -name "*.tar.gz" -mtime +30 -delete 2>/dev/null || true
fi

# Kubernetes очистка
if validate_kubeconfig; then
    log INFO "Очистка Kubernetes ресурсов..."

    # Evicted pods
    kubectl get pods --all-namespaces | grep Evicted | awk '{print $2 " -n " $1}' | xargs -I {} kubectl delete pod {} 2>/dev/null || true

    # Завершенные Jobs
    kubectl delete jobs --all-namespaces --field-selector status.successful=1 2>/dev/null || true
fi

log SUCCESS "Очистка завершена"