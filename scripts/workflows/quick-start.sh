# scripts/workflows/quick-start.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "БЫСТРЫЙ СТАРТ (минимальная конфигурация)"

# Проверка инструментов
log INFO "Проверка инструментов..."
if ! validate_tools terraform ansible kubectl helm yc; then
    log INFO "Установка недостающих инструментов..."
    "${SCRIPT_DIR}/setup/install-prerequisites.sh"
    "${SCRIPT_DIR}/setup/install-terraform.sh"
    "${SCRIPT_DIR}/setup/install-ansible.sh"
    "${SCRIPT_DIR}/setup/install-k8s-tools.sh"
    "${SCRIPT_DIR}/setup/install-yc-cli.sh"
fi

# Настройка окружения
"${SCRIPT_DIR}/setup/configure-environment.sh"

# Минимальное развертывание
log INFO "Запуск минимального развертывания..."
"${SCRIPT_DIR}/workflows/full-deploy.sh"

log SUCCESS "Быстрый старт завершен!"