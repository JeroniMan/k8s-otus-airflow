# scripts/operations/health-check.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Проверка здоровья системы"

# Валидация
validate_kubeconfig || exit 1

# Проверка кластера
log INFO "=== Состояние кластера ==="
check_cluster_ready

# Проверка нод
log INFO "=== Ноды ==="
kubectl get nodes

# Проверка системных подов
log INFO "=== Системные поды ==="
kubectl get pods -n kube-system | grep -v Running || true

# Проверка приложений
log INFO "=== ArgoCD приложения ==="
kubectl get applications -n argocd

# Проверка Airflow
log INFO "=== Airflow поды ==="
kubectl get pods -n airflow

# Проверка PVC
log INFO "=== Persistent Volumes ==="
kubectl get pvc --all-namespaces | grep -v Bound || true

# Проверка сервисов
log INFO "=== Проблемные сервисы ==="
kubectl get endpoints --all-namespaces | grep -E "<none>|<pending>" || true

# Проверка ресурсов
if kubectl top nodes &> /dev/null; then
    log INFO "=== Использование ресурсов ==="
    kubectl top nodes
fi

log SUCCESS "Проверка завершена"