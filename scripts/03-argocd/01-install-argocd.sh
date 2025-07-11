#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Installing ArgoCD"

# Check kubeconfig
if [ ! -f "${PROJECT_ROOT}/kubeconfig" ]; then
    error "kubeconfig not found. Run get-kubeconfig.sh first!"
    exit 1
fi

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Check cluster is ready
if ! kubectl cluster-info &>/dev/null; then
    error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Install ArgoCD
info "Creating ArgoCD namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

info "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# Get admin password
info "Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Save password
echo "$ARGOCD_PASSWORD" > "${PROJECT_ROOT}/argocd-password.txt"

success "ArgoCD installed successfully!"
echo ""
info "ArgoCD admin password saved to: argocd-password.txt"
info "Username: admin"
info "Password: $ARGOCD_PASSWORD"