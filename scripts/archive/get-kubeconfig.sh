#!/bin/bash
# scripts/get-kubeconfig.sh
# Получить kubeconfig с master ноды

set -e

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Получаем IP master ноды
if [ -f .env ]; then
    source .env
else
    cd infrastructure/terraform
    export MASTER_IP=$(terraform output -json master_ips | jq -r '.["master-0"].public_ip')
    cd ../..
fi

if [ -z "$MASTER_IP" ]; then
    echo -e "${RED}[✗]${NC} Не удалось получить IP master ноды"
    exit 1
fi

# SSH ключ
SSH_KEY=${SSH_PRIVATE_KEY_PATH:-~/.ssh/k8s-airflow}

echo "Получение kubeconfig с $MASTER_IP..."

# Получаем kubeconfig
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$MASTER_IP" \
    'sudo cat /etc/rancher/k3s/k3s.yaml' > kubeconfig.tmp

# Заменяем localhost на реальный IP
sed "s/127.0.0.1/$MASTER_IP/g" kubeconfig.tmp > kubeconfig
rm kubeconfig.tmp

# Проверяем
export KUBECONFIG=$PWD/kubeconfig
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}[✓]${NC} Kubeconfig успешно получен и сохранен в: $PWD/kubeconfig"
    echo ""
    echo "Для использования выполните:"
    echo "  export KUBECONFIG=$PWD/kubeconfig"
    echo ""
    echo "Или добавьте в ~/.bashrc:"
    echo "  echo 'export KUBECONFIG=$PWD/kubeconfig' >> ~/.bashrc"
else
    echo -e "${RED}[✗]${NC} Ошибка проверки kubeconfig"
    exit 1
fi