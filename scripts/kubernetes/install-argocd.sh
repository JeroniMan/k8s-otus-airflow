# scripts/kubernetes/install-argocd.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Установка ArgoCD"

# Валидация
validate_kubeconfig || exit 1
validate_tools kubectl || exit 1

# Создание namespace
create_namespace argocd

# Установка ArgoCD
log INFO "Установка ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Ожидание готовности
log INFO "Ожидание готовности ArgoCD..."
wait_for_deployment argocd argocd-server 600

# Получение пароля
ARGOCD_PASSWORD=$(get_secret_value argocd argocd-initial-admin-secret password)
echo "${ARGOCD_PASSWORD}" > "${PROJECT_ROOT}/argocd-password.txt"

log SUCCESS "ArgoCD установлен"
log INFO "Пароль admin сохранен в argocd-password.txt"