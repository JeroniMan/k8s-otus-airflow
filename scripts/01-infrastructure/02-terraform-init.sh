#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Initializing Terraform"

# Load environment
load_env || exit 1

# Check prerequisites
check_prerequisites terraform || exit 1

cd "${PROJECT_ROOT}/infrastructure/terraform"

# Update backend configuration
info "Updating backend configuration..."
sed -i.bak "s/bucket = \".*\"/bucket = \"$TF_STATE_BUCKET\"/" main.tf

# Set AWS credentials for S3 backend
export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"

# Initialize Terraform
info "Running terraform init..."
terraform init -upgrade

# Validate configuration
info "Validating Terraform configuration..."
terraform validate

success "Terraform initialized successfully!"

# Show providers
info "Installed providers:"
terraform providers