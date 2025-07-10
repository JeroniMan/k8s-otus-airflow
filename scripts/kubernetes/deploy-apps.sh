# scripts/kubernetes/deploy-apps.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Развертывание приложений через ArgoCD"

# Валидация
validate_kubeconfig || exit 1

# Обновление URL репозитория
REPO_URL=$(git config --get remote.origin.url || echo "https://github.com/yourusername/k8s-airflow-project")
log INFO "Используется репозиторий: ${REPO_URL}"

# Обновление URL в манифестах
find "${K8S_DIR}/argocd" -name "*.yaml" -type f -exec \
    sed -i.bak "s|https://github.com/yourusername/k8s-airflow-project|${REPO_URL}|g" {} \;

# Применение namespaces
log INFO "Создание namespaces..."
apply_manifests "${K8S_DIR}/namespaces"

# Применение ArgoCD projects
log INFO "Создание ArgoCD projects..."
apply_manifests "${K8S_DIR}/argocd/projects"

# Применение ArgoCD applications в правильном порядке
log INFO "Развертывание приложений..."

# 1. CRDs
kubectl apply -f "${K8S_DIR}/argocd/apps/crds.yaml" 2>/dev/null || log WARN "CRDs app не найден"
sleep 30

# 2. NFS Provisioner
kubectl apply -f "${K8S_DIR}/argocd/apps/nfs-provisioner.yaml" 2>/dev/null || log WARN "NFS provisioner app не найден"
sleep 30

# 3. Ingress
kubectl apply -f "${K8S_DIR}/argocd/apps/ingress-nginx.yaml"
sleep 60

# 4. Monitoring
kubectl apply -f "${K8S_DIR}/argocd/apps/prometheus-stack.yaml"
kubectl apply -f "${K8S_DIR}/argocd/apps/loki-stack.yaml"
sleep 120

# 5. Airflow
kubectl apply -f "${K8S_DIR}/argocd/apps/airflow.yaml"

log SUCCESS "Приложения развернуты"
log INFO "Проверьте статус: kubectl get applications -n argocd"