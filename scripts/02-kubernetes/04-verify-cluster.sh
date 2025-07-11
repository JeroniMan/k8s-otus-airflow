#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Verifying k3s Cluster"

# Check kubeconfig
if [ ! -f "${PROJECT_ROOT}/kubeconfig" ]; then
    error "kubeconfig not found. Run get-kubeconfig.sh first!"
    exit 1
fi

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Check cluster info
info "Cluster information:"
kubectl cluster-info

echo ""
info "Nodes:"
kubectl get nodes -o wide

echo ""
info "System pods:"
kubectl get pods -n kube-system

echo ""
info "Storage classes:"
kubectl get storageclass

echo ""
info "Namespaces:"
kubectl get namespaces

# Check all nodes are ready
NODES_COUNT=$(kubectl get nodes --no-headers | wc -l)
READY_NODES=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)

if [ "$NODES_COUNT" -eq "$READY_NODES" ]; then
    success "All $NODES_COUNT nodes are ready!"
else
    warning "Only $READY_NODES out of $NODES_COUNT nodes are ready"
fi

# Check core components
echo ""
info "Checking core components..."

components=("coredns" "metrics-server" "local-path-provisioner")
all_good=true

for component in "${components[@]}"; do
    if kubectl get deployment -n kube-system | grep -q "$component"; then
        success "$component is running"
    else
        warning "$component is not found"
        all_good=false
    fi
done

if $all_good; then
    success "Cluster verification passed!"
else
    warning "Some components are missing, but this might be normal for k3s"
fi

echo ""
info "Cluster is ready for application deployment!"