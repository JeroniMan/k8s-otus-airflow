#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Applying ArgoCD Applications"

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Load environment for substitutions
load_env || exit 1

# Update Git repository URL in application files
info "Updating repository URLs..."
REPO_URL=$(git config --get remote.origin.url || echo "https://github.com/YOUR_USERNAME/k8s-airflow-project.git")

find "${PROJECT_ROOT}/kubernetes/argocd-apps" -name "*.yaml" -type f -exec \
    sed -i.bak "s|https://github.com/YOUR_USERNAME/k8s-airflow-project.git|$REPO_URL|g" {} \;

# Apply applications in order
info "Applying infrastructure applications..."
for app in ingress-nginx cert-manager; do
    app_file="${PROJECT_ROOT}/kubernetes/argocd-apps/infrastructure/$app.yaml"
    if [ -f "$app_file" ]; then
        info "Applying $app..."
        envsubst < "$app_file" | kubectl apply -f -
    fi
done

sleep 10

info "Applying monitoring applications..."
for app in prometheus grafana loki promtail; do
    app_file="${PROJECT_ROOT}/kubernetes/argocd-apps/monitoring/$app.yaml"
    if [ -f "$app_file" ]; then
        info "Applying $app..."
        envsubst < "$app_file" | kubectl apply -f -
    fi
done

sleep 10

info "Applying application stack..."
for app in airflow; do
    app_file="${PROJECT_ROOT}/kubernetes/argocd-apps/applications/$app.yaml"
    if [ -f "$app_file" ]; then
        info "Applying $app..."
        envsubst < "$app_file" | kubectl apply -f -
    fi
done

# Alternatively, apply app-of-apps pattern
if [ -f "${PROJECT_ROOT}/kubernetes/argocd-apps/app-of-apps.yaml" ]; then
    info "Applying app-of-apps..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/argocd-apps/app-of-apps.yaml"
fi

# Show applications
echo ""
info "ArgoCD Applications:"
kubectl get applications -n argocd

success "ArgoCD applications created!"
info "Applications will start syncing automatically..."
info "Check status: kubectl get applications -n argocd"