# scripts/kubernetes/get-kubeconfig.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Получение kubeconfig"

# Загрузка окружения
load_env || exit 1
validate_ssh_keys || exit 1

# Получение MASTER_IP
if [ -z "${MASTER_IP}" ]; then
    if [ -f "${PROJECT_ROOT}/terraform-outputs.json" ]; then
        MASTER_IP=$(jq -r '.master_ips.value["master-0"].public_ip' "${PROJECT_ROOT}/terraform-outputs.json")
    else
        log ERROR "MASTER_IP не найден. Создайте инфраструктуру: make infra-apply"
        exit 1
    fi
fi

log INFO "Подключение к master: ${MASTER_IP}"

# Получение kubeconfig
ssh -o StrictHostKeyChecking=no \
    -i "${SSH_PRIVATE_KEY_PATH}" \
    "ubuntu@${MASTER_IP}" \
    'sudo cat /etc/rancher/k3s/k3s.yaml' > "${PROJECT_ROOT}/kubeconfig.tmp"

# Замена localhost на реальный IP
sed "s/127.0.0.1/${MASTER_IP}/g" "${PROJECT_ROOT}/kubeconfig.tmp" > "${PROJECT_ROOT}/kubeconfig"
rm -f "${PROJECT_ROOT}/kubeconfig.tmp"

# Проверка
export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"
if kubectl cluster-info &> /dev/null; then
    log SUCCESS "Kubeconfig получен и сохранен"
    log INFO "Использование: export KUBECONFIG=${PROJECT_ROOT}/kubeconfig"
else
    log ERROR "Ошибка проверки kubeconfig"
    exit 1
fi