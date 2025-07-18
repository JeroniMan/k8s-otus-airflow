#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Applying Terraform Configuration"

# Load environment
load_env || exit 1

cd "${PROJECT_ROOT}/infrastructure/terraform"

# Set AWS credentials for S3 backend
export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"

# Check Yandex Cloud credentials
if [ -n "$YC_SERVICE_ACCOUNT_KEY_FILE" ]; then
    # Expand path relative to project root
    KEY_FILE=$(eval echo "$YC_SERVICE_ACCOUNT_KEY_FILE")

    # If path starts with $PWD, replace with actual project root
    if [[ "$KEY_FILE" == *'$PWD'* ]]; then
        KEY_FILE="${PROJECT_ROOT}/key.json"
    fi

    # Check if file exists
    if [ ! -f "$KEY_FILE" ]; then
        # Try in project root
        if [ -f "${PROJECT_ROOT}/key.json" ]; then
            KEY_FILE="${PROJECT_ROOT}/key.json"
        else
            error "Service account key file not found"
            error "Searched in: $KEY_FILE and ${PROJECT_ROOT}/key.json"
            exit 1
        fi
    fi

    export YC_SERVICE_ACCOUNT_KEY_FILE="$KEY_FILE"
    info "Using service account key: $KEY_FILE"
fi

# Create terraform.tfvars if it doesn't exist
if [ ! -f terraform.tfvars ]; then
    info "Creating terraform.tfvars..."
    cat > terraform.tfvars << EOF
yc_cloud_id          = "$YC_CLOUD_ID"
yc_folder_id         = "$YC_FOLDER_ID"
yc_zone              = "${YC_ZONE:-ru-central1-a}"
ssh_public_key_path  = "$SSH_PUBLIC_KEY_PATH"
ssh_private_key_path = "$SSH_PRIVATE_KEY_PATH"

# Cluster configuration
master_count  = 1
master_cpu    = 2
master_memory = 4

worker_count  = 2
worker_cpu    = 2
worker_memory = 4

# Cost optimization
preemptible   = true
core_fraction = 50
EOF
    success "terraform.tfvars created"
fi

# Show plan
info "Running terraform plan..."
terraform plan -out=tfplan

# Ask for confirmation
echo ""
warning "This will create resources in Yandex Cloud!"
read -p "Do you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    info "Cancelled"
    exit 0
fi

# Apply
info "Applying Terraform configuration..."
terraform apply tfplan

# Save outputs
info "Saving outputs..."
terraform output -json > "${PROJECT_ROOT}/terraform-outputs.json"

# Save to artifacts
mkdir -p "${PROJECT_ROOT}/.artifacts"
cp "${PROJECT_ROOT}/terraform-outputs.json" "${PROJECT_ROOT}/.artifacts/terraform-outputs.json"

# Save resource list
yc compute instance list --format json > "${PROJECT_ROOT}/.artifacts/compute-instances.json"
yc vpc network list --format json > "${PROJECT_ROOT}/.artifacts/vpc-networks.json"
yc lb nlb list --format json > "${PROJECT_ROOT}/.artifacts/load-balancers.json"

# Show important outputs
echo ""
success "Infrastructure created successfully!"
echo ""
info "Important information:"
info "Load Balancer IP: $(terraform output -raw load_balancer_ip)"
info "Master IP: $(terraform output -json master_ips | jq -r '.["master-0"].public_ip')"
echo ""
info "SSH to master: $(terraform output -raw ssh_master_command)"

# Update .env with subnet_id
SUBNET_ID=$(terraform output -json network_info | jq -r '.subnet_id')
sed -i.bak "s/^export SUBNET_ID=.*/export SUBNET_ID=\"$SUBNET_ID\"/" "${PROJECT_ROOT}/.env"

success "Infrastructure is ready!"
info "All artifacts saved to: ${PROJECT_ROOT}/.artifacts/"