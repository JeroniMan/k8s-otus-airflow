# scripts/setup/install-ansible.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

ANSIBLE_VERSION="8.5.0"

log STEP "Установка Ansible ${ANSIBLE_VERSION}"

if check_command ansible; then
    current_version=$(ansible --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    log WARN "Ansible уже установлен: ${current_version}"
fi

# Установка через pip
pip3 install --user "ansible==${ANSIBLE_VERSION}"

# Установка коллекций
log INFO "Установка Ansible коллекций..."
ansible-galaxy collection install community.general ansible.posix kubernetes.core

# Проверка установки
if ansible --version &> /dev/null; then
    log SUCCESS "Ansible установлен: $(ansible --version | head -1)"
else
    log ERROR "Ошибка установки Ansible"
    exit 1
fi