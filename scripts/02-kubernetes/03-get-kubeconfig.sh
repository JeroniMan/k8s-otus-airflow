#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Getting kubeconfig from Master Node"

# Load environment
load_env || exit 1

# Get master IP from terraform outputs
if [ -f "${PROJECT_ROOT}/terraform-outputs.json" ]; then
    MASTER_IP=$(jq -r '.master_ips.value["master-0"].public_ip' "${PROJECT_ROOT}/terraform-outputs.json")
else
    error "terraform-outputs.json not found. Run terraform apply first!"
    exit 1
fi

info "Connecting to master node at $MASTER_IP..."

# Get kubeconfig
ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" ubuntu@"$MASTER_IP" \
    'sudo cat /etc/rancher/k3s/k3s.yaml' > "${PROJECT_ROOT}/kubeconfig"

# Replace localhost with actual master IP
sed -i.bak "s/127.0.0.1/$MASTER_IP/g" "${PROJECT_ROOT}/kubeconfig"

# Set permissions
chmod 600 "${PROJECT_ROOT}/kubeconfig"

# Export KUBECONFIG
export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Test connection
info "Testing connection to cluster..."
if kubectl cluster-info &>/dev/null; then
    success "Successfully connected to k3s cluster!"

    # Show version without --short flag
    echo ""
    info "Kubernetes version:"
    kubectl version --client -o yaml | grep -E "gitVersion|platform" | sed 's/^/  /'

    # Show server version if available
    if kubectl version -o yaml 2>/dev/null | grep -q "serverVersion"; then
        echo ""
        info "Server version:"
        kubectl version -o yaml 2>/dev/null | grep -A3 "serverVersion:" | grep -E "gitVersion|platform" | sed 's/^/  /'
    fi
else
    error "Failed to connect to cluster"
    exit 1
fi

info "kubeconfig saved to: ${PROJECT_ROOT}/kubeconfig"
info "To use kubectl: export KUBECONFIG=${PROJECT_ROOT}/kubeconfig"