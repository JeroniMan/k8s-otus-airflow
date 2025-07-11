#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Installing k3s Cluster"

# Load environment
load_env || exit 1

# Check prerequisites
check_prerequisites ansible ansible-playbook || exit 1

cd "${PROJECT_ROOT}/infrastructure/ansible"

info "Running install-k3s playbook..."

# Run ansible playbook
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -i inventory/hosts.yml \
    --private-key="$SSH_PRIVATE_KEY_PATH" \
    playbooks/install-k3s.yml \
    -v

success "k3s cluster installed successfully!"

# Wait for cluster to stabilize
info "Waiting for cluster to stabilize..."
sleep 30