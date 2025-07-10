# scripts/operations/restore-config.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log STEP "Восстановление из резервной копии"

# Поиск последнего бэкапа
BACKUP_FILE=$(ls -t "${PROJECT_ROOT}"/backups/*.tar.gz 2>/dev/null | head -1)

if [ -z "${BACKUP_FILE}" ]; then
    log ERROR "Backup файлы не найдены"
    exit 1
fi

log INFO "Используется backup: ${BACKUP_FILE}"

# Подтверждение
read -p "Восстановить из этого backup? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log INFO "Отменено"
    exit 0
fi

# Распаковка
TEMP_DIR=$(mktemp -d)
tar -xzf "${BACKUP_FILE}" -C "${TEMP_DIR}"

BACKUP_DIR=$(ls -d "${TEMP_DIR}"/*/)

# Восстановление файлов
log INFO "Восстановление конфигураций..."

# .env
if [ -f "${BACKUP_DIR}/.env" ]; then
    cp "${BACKUP_DIR}/.env" "${PROJECT_ROOT}/.env.restored"
    log INFO ".env восстановлен как .env.restored"
fi

# kubeconfig
if [ -f "${BACKUP_DIR}/kubeconfig" ]; then
    cp "${BACKUP_DIR}/kubeconfig" "${PROJECT_ROOT}/kubeconfig.restored"
    log INFO "kubeconfig восстановлен как kubeconfig.restored"
fi

# Passwords
if [ -f "${BACKUP_DIR}/argocd-password.txt" ]; then
    cp "${BACKUP_DIR}/argocd-password.txt" "${PROJECT_ROOT}/"
    log INFO "Пароли восстановлены"
fi

# Очистка
rm -rf "${TEMP_DIR}"

log SUCCESS "Восстановление завершено"
log WARN "Файлы восстановлены с суффиксом .restored для безопасности"