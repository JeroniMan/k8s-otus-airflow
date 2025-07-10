# scripts/kubernetes/install-k3s.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Установка k3s через Ansible"

# Загрузка окружения и валидация
load_env || exit 1
validate_env_vars || exit 1
validate_tools ansible ansible-playbook || exit 1
validate_ssh_keys || exit 1

cd "${ANSIBLE_DIR}"

# Проверка inventory
if [ ! -f "inventory/hosts.yml" ]; then
    log ERROR "Ansible inventory не найден"
    log INFO "Сначала создайте инфраструктуру: make infra-apply"
    exit 1
fi

# Ожидание готовности серверов
log INFO "Проверка доступности серверов..."
ANSIBLE_HOST_KEY_CHECKING=False ansible all \
    -i inventory/hosts.yml \
    --private-key="${SSH_PRIVATE_KEY_PATH}" \
    -m wait_for_connection \
    -a 'delay=10 timeout=300' || {
    log ERROR "Серверы недоступны"
    exit 1
}

# Установка k3s
log INFO "Установка k3s..."
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -i inventory/hosts.yml \
    --private-key="${SSH_PRIVATE_KEY_PATH}" \
    playbooks/install-k3s.yml \
    -v

log SUCCESS "k3s установлен"