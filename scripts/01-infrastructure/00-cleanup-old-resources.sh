#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Cleaning up old Yandex Cloud resources"

# Load environment
load_env || exit 1

warning "This will delete resources with 'k8s-airflow' in the name"
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    info "Cancelled"
    exit 0
fi

# Delete VMs
info "Checking for old VMs..."
for vm in $(yc compute instance list --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    warning "Deleting VM: $vm"
    yc compute instance delete $vm --async
done

# Wait for VMs to be deleted
sleep 30

# Delete Load Balancers
info "Checking for old Load Balancers..."
for lb in $(yc load-balancer network-load-balancer list --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    warning "Deleting Load Balancer: $lb"
    yc load-balancer network-load-balancer delete $lb
done

# Delete Target Groups
info "Checking for old Target Groups..."
for tg in $(yc load-balancer target-group list --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    warning "Deleting Target Group: $tg"
    yc load-balancer target-group delete $tg
done

# Delete Subnets
info "Checking for old Subnets..."
for subnet in $(yc vpc subnet list --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    warning "Deleting Subnet: $subnet"
    yc vpc subnet delete $subnet
done

# Delete Security Groups
info "Checking for old Security Groups..."
for sg in $(yc vpc security-group list --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    warning "Deleting Security Group: $sg"
    yc vpc security-group delete $sg
done

# Delete Networks
info "Checking for old Networks..."
for net in $(yc vpc network list --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    warning "Deleting Network: $net"
    yc vpc network delete $net
done

# Delete Disks
info "Checking for old Disks..."
for disk in $(yc compute disk list --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    warning "Deleting Disk: $disk"
    yc compute disk delete $disk
done

success "Cleanup completed!"

# Show current resources
info "Current resources:"
bash scripts/01-infrastructure/check-resources.sh