#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Cleaning Up Resources"

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Function to delete namespace safely
delete_namespace() {
    local namespace=$1

    if kubectl get namespace "$namespace" &>/dev/null; then
        info "Deleting namespace $namespace..."

        # First, delete all resources in namespace
        kubectl delete all --all -n "$namespace" --grace-period=0 --force 2>/dev/null || true

        # Delete the namespace
        kubectl delete namespace "$namespace" --grace-period=0 --force 2>/dev/null || true

        # If namespace is stuck, patch finalizers
        kubectl get namespace "$namespace" -o json 2>/dev/null | \
            jq '.spec.finalizers = []' | \
            kubectl replace --raw "/api/v1/namespaces/$namespace/finalize" -f - 2>/dev/null || true
    fi
}

# Check if cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    warning "Cannot connect to cluster. It may already be destroyed."
    exit 0
fi

# Delete ArgoCD applications first
info "Deleting ArgoCD applications..."
kubectl delete applications --all -n argocd 2>/dev/null || true

# Wait for applications to be deleted
sleep 30

# Delete application namespaces in reverse order
for ns in airflow monitoring ingress-nginx cert-manager; do
    delete_namespace "$ns"
done

# Delete ArgoCD last
delete_namespace "argocd"

# Delete cluster-wide resources
info "Deleting cluster-wide resources..."
kubectl delete clusterrolebinding --all 2>/dev/null || true
kubectl delete clusterrole --all 2>/dev/null || true
kubectl delete crd --all 2>/dev/null || true

# Clean local files
info "Cleaning local files..."
rm -f "${PROJECT_ROOT}/kubeconfig"
rm -f "${PROJECT_ROOT}/argocd-password.txt"
rm -f "${PROJECT_ROOT}/access-info.txt"

success "Kubernetes resources cleaned up!"