#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Preparing Nodes for k3s Installation"

# Load environment
load_env || exit 1

# Check prerequisites
check_prerequisites ansible ansible-playbook || exit 1

cd "${PROJECT_ROOT}/infrastructure/ansible"

# Check inventory exists
if [ ! -f "inventory/hosts.yml" ]; then
    error "Ansible inventory not found. Run terraform first!"
    exit 1
fi

info "Running prepare-nodes playbook..."

# Run ansible playbook
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -i inventory/hosts.yml \
    --private-key="${SSH_PRIVATE_KEY_PATH}" \
    playbooks/prepare-nodes.yml \
    -v

success "Nodes prepared successfully!"