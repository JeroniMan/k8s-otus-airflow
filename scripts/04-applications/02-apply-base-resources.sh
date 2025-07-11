#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Applying Base Kubernetes Resources"

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Load environment
load_env || exit 1

info "Applying base resources..."

# Apply storage class
if [ -f "${PROJECT_ROOT}/kubernetes/base/storage-class.yaml" ]; then
    info "Applying storage classes..."
    envsubst < "${PROJECT_ROOT}/kubernetes/base/storage-class.yaml" | kubectl apply -f -
fi

# Apply RBAC
info "Applying RBAC..."
for rbac_file in "${PROJECT_ROOT}"/kubernetes/base/*-rbac.yaml; do
    if [ -f "$rbac_file" ]; then
        kubectl apply -f "$rbac_file"
    fi
done

# Apply resource quotas
if [ -f "${PROJECT_ROOT}/kubernetes/base/resource-quotas.yaml" ]; then
    info "Applying resource quotas..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/base/resource-quotas.yaml"
fi

# Apply network policies
if [ -f "${PROJECT_ROOT}/kubernetes/base/network-policies.yaml" ]; then
    info "Applying network policies..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/base/network-policies.yaml" || \
        warning "Network policies applied but may not be enforced without a CNI plugin that supports them"
fi

# Apply cluster issuers for cert-manager
info "Waiting for cert-manager..."
if kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager 2>/dev/null; then
    info "Applying cluster issuers..."
    envsubst < "${PROJECT_ROOT}/kubernetes/base/cluster-issuer.yaml" | kubectl apply -f -
else
    warning "cert-manager not ready yet, skipping cluster issuers"
fi

# Apply additional ConfigMaps
for cm_file in "${PROJECT_ROOT}"/kubernetes/base/*-configmap.yaml; do
    if [ -f "$cm_file" ]; then
        info "Applying $(basename $cm_file)..."
        kubectl apply -f "$cm_file"
    fi
done

# Apply Prometheus rules
for rule_file in "${PROJECT_ROOT}"/kubernetes/base/*-rules.yaml; do
    if [ -f "$rule_file" ]; then
        info "Applying $(basename $rule_file)..."
        kubectl apply -f "$rule_file" || warning "Prometheus rules applied but may require CRDs"
    fi
done

success "Base resources applied!"

# Show summary
echo ""
info "Resource summary:"
kubectl get storageclass
echo ""
kubectl get clusterrole | grep -E "(airflow|monitoring)" || true
echo ""
kubectl get resourcequota --all-namespaces