# scripts/monitoring/check-cluster-status.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Проверка статуса кластера"

# Валидация
validate_kubeconfig || exit 1

# Статус нод
echo -e "\n${GREEN}=== Nodes Status ===${NC}"
kubectl get nodes

# Использование ресурсов
if kubectl top nodes &> /dev/null; then
    echo -e "\n${GREEN}=== Resource Usage ===${NC}"
    kubectl top nodes
    echo ""
    kubectl top pods --all-namespaces | head -20
fi

# Системные компоненты
echo -e "\n${GREEN}=== System Components ===${NC}"
kubectl get pods -n kube-system | grep -v Running || echo "All system pods are running"

# Storage
echo -e "\n${GREEN}=== Storage Classes ===${NC}"
kubectl get storageclass

echo -e "\n${GREEN}=== Persistent Volumes ===${NC}"
kubectl get pv

log SUCCESS "Проверка завершена"