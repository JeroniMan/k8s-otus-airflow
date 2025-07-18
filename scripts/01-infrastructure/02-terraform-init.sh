#!/bin/bash
# scripts/01-infrastructure/02-terraform-init.sh

set -e

source "$(dirname "$0")/../lib/common.sh"

step "Initializing Terraform"

# Load environment
load_env || exit 1

# Check prerequisites
check_prerequisites terraform || exit 1

# Check Terraform service account
info "Checking Terraform service account..."
if ! yc iam service-account get "terraform-sa" &>/dev/null; then
    error "Terraform service account not found!"
    info "Running service account setup..."
    "${SCRIPT_DIR}/../00-prerequisites/04-setup-service-accounts.sh"

    # Reload environment
    load_env || exit 1
fi

# Check Terraform key file
if [ -z "$YC_SERVICE_ACCOUNT_KEY_FILE" ]; then
    error "YC_SERVICE_ACCOUNT_KEY_FILE not set"

    # Try to find key file
    if [ -f "${PROJECT_ROOT}/yc-terraform-key.json" ]; then
        export YC_SERVICE_ACCOUNT_KEY_FILE="${PROJECT_ROOT}/yc-terraform-key.json"
        info "Found key file at: $YC_SERVICE_ACCOUNT_KEY_FILE"
    elif [ -f "${PROJECT_ROOT}/.artifacts/terraform-sa-key.json" ]; then
        cp "${PROJECT_ROOT}/.artifacts/terraform-sa-key.json" "${PROJECT_ROOT}/yc-terraform-key.json"
        export YC_SERVICE_ACCOUNT_KEY_FILE="${PROJECT_ROOT}/yc-terraform-key.json"
        info "Restored key file from artifacts"
    else
        error "No Terraform key file found!"
        error "Please run: ./scripts/00-prerequisites/04-setup-service-accounts.sh"
        exit 1
    fi
fi

# Expand and validate key file path
KEY_FILE=$(eval echo "$YC_SERVICE_ACCOUNT_KEY_FILE")
if [ ! -f "$KEY_FILE" ]; then
    if [ -f "${PROJECT_ROOT}/yc-terraform-key.json" ]; then
        KEY_FILE="${PROJECT_ROOT}/yc-terraform-key.json"
    else
        error "Service account key file not found: $KEY_FILE"
        exit 1
    fi
fi
export YC_SERVICE_ACCOUNT_KEY_FILE="$KEY_FILE"
info "Using Terraform key: $KEY_FILE"

# Test Terraform service account
info "Testing Terraform service account access..."
if YC_SERVICE_ACCOUNT_KEY_FILE="$KEY_FILE" yc resource-manager cloud list &>/dev/null; then
    success "Terraform service account access confirmed"
else
    error "Terraform service account test failed"
    error "Please check service account permissions"
    exit 1
fi

cd "${PROJECT_ROOT}/infrastructure/terraform"

# Verify S3 credentials are set
if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    error "S3 credentials not found in environment"

    # Try to load from artifacts
    if [ -f "${PROJECT_ROOT}/.artifacts/s3-keys.json" ]; then
        ACCESS_KEY=$(jq -r '.access_key' "${PROJECT_ROOT}/.artifacts/s3-keys.json")
        SECRET_KEY=$(jq -r '.secret_key' "${PROJECT_ROOT}/.artifacts/s3-keys.json")
        export ACCESS_KEY
        export SECRET_KEY
        export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
        success "Loaded S3 credentials from artifacts"
    else
        error "No S3 credentials found!"
        error "Please run: ./scripts/01-infrastructure/01-create-s3-bucket.sh"
        exit 1
    fi
fi

# Verify bucket exists
if [ -z "$TF_STATE_BUCKET" ]; then
    error "TF_STATE_BUCKET not set"
    exit 1
fi

info "Checking Terraform state bucket..."
if ! yc storage bucket get "$TF_STATE_BUCKET" &>/dev/null; then
    error "Terraform state bucket $TF_STATE_BUCKET does not exist!"
    error "Please run: ./scripts/01-infrastructure/01-create-s3-bucket.sh"
    exit 1
fi
success "State bucket exists: $TF_STATE_BUCKET"

# Update backend configuration in main.tf
info "Updating backend configuration..."
sed -i.bak "s/bucket = \".*\"/bucket = \"$TF_STATE_BUCKET\"/" main.tf

# Set AWS credentials for S3 backend
export AWS_ACCESS_KEY_ID="${ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${SECRET_KEY}"

# Clean up old terraform files
info "Cleaning up old Terraform files..."
rm -rf .terraform .terraform.lock.hcl

# Initialize Terraform
info "Running terraform init..."
if terraform init -reconfigure \
    -backend-config="access_key=${ACCESS_KEY}" \
    -backend-config="secret_key=${SECRET_KEY}" \
    -upgrade; then
    success "Terraform initialized successfully!"
else
    error "Terraform init failed!"

    # Common troubleshooting
    echo ""
    error "Troubleshooting steps:"
    echo "1. Check S3 access:"
    echo "   yc storage bucket list"
    echo ""
    echo "2. Check service account roles:"
    echo "   ${PROJECT_ROOT}/.artifacts/check-service-accounts.sh"
    echo ""
    echo "3. Recreate service accounts:"
    echo "   ./scripts/00-prerequisites/04-setup-service-accounts.sh"
    echo ""
    echo "4. Check backend configuration in main.tf"

    exit 1
fi

# Save terraform version info
mkdir -p "${PROJECT_ROOT}/.artifacts"
terraform version > "${PROJECT_ROOT}/.artifacts/terraform-version.txt"

# Validate configuration
info "Validating Terraform configuration..."
if terraform validate; then
    success "Terraform configuration is valid"
else
    error "Terraform configuration validation failed"
    exit 1
fi

# Show providers
info "Installed providers:"
terraform providers

# Create a simple test to verify state access
info "Testing state backend access..."
cat > test.tf << 'EOF'
resource "null_resource" "test" {
  triggers = {
    timestamp = timestamp()
  }
}
EOF

if terraform plan -out=test.tfplan &>/dev/null; then
    success "State backend access confirmed"
    rm -f test.tf test.tfplan
else
    warning "Could not test state backend access"
    rm -f test.tf test.tfplan
fi

success "Terraform is ready to use!"
info "Next step: ./scripts/01-infrastructure/03-terraform-apply.sh"

# Save initialization status
echo "initialized_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${PROJECT_ROOT}/.artifacts/terraform-init-status.txt"