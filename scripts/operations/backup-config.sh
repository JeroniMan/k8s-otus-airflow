# scripts/operations/backup-config.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Создание резервной копии конфигураций"

# Директория для бэкапов
BACKUP_DIR="${PROJECT_ROOT}/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "${BACKUP_DIR}"

log INFO "Директория бэкапа: ${BACKUP_DIR}"

# Terraform state
if [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    log INFO "Backup Terraform state..."
    cp "${TERRAFORM_DIR}/terraform.tfstate" "${BACKUP_DIR}/"
fi

# Terraform outputs
if [ -f "${PROJECT_ROOT}/terraform-outputs.json" ]; then
    cp "${PROJECT_ROOT}/terraform-outputs.json" "${BACKUP_DIR}/"
fi

# Kubeconfig
if [ -f "${PROJECT_ROOT}/kubeconfig" ]; then
    log INFO "Backup kubeconfig..."
    cp "${PROJECT_ROOT}/kubeconfig" "${BACKUP_DIR}/"
fi

# Environment
cp "${PROJECT_ROOT}/.env" "${BACKUP_DIR}/" 2>/dev/null || true

# Пароли
cp "${PROJECT_ROOT}/argocd-password.txt" "${BACKUP_DIR}/" 2>/dev/null || true

# Kubernetes ресурсы
if validate_kubeconfig; then
    log INFO "Backup Kubernetes resources..."
    kubectl get all,cm,secret,pvc,pv,ing --all-namespaces -o yaml > "${BACKUP_DIR}/k8s-all-resources.yaml"
    kubectl get applications -n argocd -o yaml > "${BACKUP_DIR}/argocd-applications.yaml" 2>/dev/null || true
fi

# Git информация
cat > "${BACKUP_DIR}/git-info.txt" << EOF
Repository: $(git config --get remote.origin.url)
Branch: $(git branch --show-current)
Commit: $(git rev-parse HEAD)
Date: $(date)
EOF

# Архивирование
log INFO "Создание архива..."
cd "${PROJECT_ROOT}/backups"
tar -czf "$(basename "${BACKUP_DIR}").tar.gz" "$(basename "${BACKUP_DIR}")"

log SUCCESS "Backup создан: ${BACKUP_DIR}.tar.gz"