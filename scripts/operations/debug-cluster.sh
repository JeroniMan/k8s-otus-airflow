# scripts/operations/debug-cluster.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Сбор отладочной информации"

# Валидация
validate_kubeconfig || exit 1

# Создание директории для отладки
DEBUG_DIR="${PROJECT_ROOT}/debug/$(date +%Y%m%d_%H%M%S)"
mkdir -p "${DEBUG_DIR}"

log INFO "Директория отладки: ${DEBUG_DIR}"

# Информация о кластере
kubectl cluster-info > "${DEBUG_DIR}/cluster-info.txt"
kubectl get nodes -o wide > "${DEBUG_DIR}/nodes.txt"
kubectl get all --all-namespaces > "${DEBUG_DIR}/all-resources.txt"

# События
kubectl get events --all-namespaces --sort-by='.lastTimestamp' > "${DEBUG_DIR}/events.txt"

# Проблемные поды
kubectl get pods --all-namespaces --field-selector='status.phase!=Running,status.phase!=Succeeded' > "${DEBUG_DIR}/problem-pods.txt"

# Логи проблемных подов
log INFO "Сбор логов проблемных подов..."
problem_pods=$(kubectl get pods --all-namespaces --field-selector='status.phase!=Running,status.phase!=Succeeded' -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"')

if [ -n "$problem_pods" ]; then
    echo "$problem_pods" | while read ns pod; do
        log INFO "Логи $ns/$pod"
        kubectl logs -n "$ns" "$pod" --tail=100 > "${DEBUG_DIR}/logs-${ns}-${pod}.txt" 2>&1 || \
        kubectl logs -n "$ns" "$pod" --previous --tail=100 > "${DEBUG_DIR}/logs-${ns}-${pod}-previous.txt" 2>&1 || true
    done
fi

# ArgoCD статус
kubectl get applications -n argocd -o yaml > "${DEBUG_DIR}/argocd-apps.yaml" 2>/dev/null || true

# Describe для важных ресурсов
for ns in airflow monitoring argocd ingress-nginx; do
    mkdir -p "${DEBUG_DIR}/${ns}"
    kubectl get all -n "$ns" -o yaml > "${DEBUG_DIR}/${ns}/all.yaml" 2>/dev/null || true
    kubectl describe all -n "$ns" > "${DEBUG_DIR}/${ns}/describe.txt" 2>/dev/null || true
done

# Архивирование
log INFO "Создание архива..."
cd "${PROJECT_ROOT}/debug"
tar -czf "$(basename "${DEBUG_DIR}").tar.gz" "$(basename "${DEBUG_DIR}")"

log SUCCESS "Отладочная информация собрана: ${DEBUG_DIR}.tar.gz"