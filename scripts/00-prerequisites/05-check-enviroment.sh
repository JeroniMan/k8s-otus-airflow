#!/bin/bash
# scripts/00-prerequisites/05-check-environment.sh

set -e

source "$(dirname "$0")/../lib/common.sh"

step "Checking and Fixing Environment"

# Load environment
if ! load_env; then
    error ".env file not found or cannot be loaded"

    if [ -f "${PROJECT_ROOT}/.env.example" ]; then
        info "Creating .env from .env.example..."
        cp "${PROJECT_ROOT}/.env.example" "${PROJECT_ROOT}/.env"
        info "Please edit .env file with your values"
        exit 1
    else
        error "No .env.example found"
        exit 1
    fi
fi

# Function to check and fix variable
check_var() {
    local var_name=$1
    local var_value=${!var_name}
    local fix_command=$2

    if [ -z "$var_value" ] || [[ "$var_value" == *'$('* ]]; then
        warning "$var_name is not set or contains command substitution"

        if [ -n "$fix_command" ]; then
            info "Attempting to fix..."
            local fixed_value=$(eval "$fix_command")
            if [ -n "$fixed_value" ]; then
                export "$var_name=$fixed_value"

                # Update .env
                if grep -q "^export $var_name=" "${PROJECT_ROOT}/.env"; then
                    sed -i.bak "s/^export $var_name=.*/export $var_name=\"$fixed_value\"/" "${PROJECT_ROOT}/.env"
                else
                    echo "export $var_name=\"$fixed_value\"" >> "${PROJECT_ROOT}/.env"
                fi

                success "$var_name fixed: $fixed_value"
                return 0
            fi
        fi

        error "$var_name could not be fixed"
        return 1
    else
        success "$var_name is set: ${var_value:0:20}..."
        return 0
    fi
}

echo ""
info "Checking Yandex Cloud configuration..."

# Check YC CLI
if ! command_exists yc; then
    error "yc CLI not installed"
    info "Run: ./scripts/00-prerequisites/02-install-tools.sh"
    exit 1
fi

# Check YC configuration
if ! yc config list &>/dev/null; then
    error "Yandex Cloud CLI not configured"
    info "Run: yc init"
    exit 1
fi

# Check and fix critical variables
check_var "YC_CLOUD_ID" "yc config get cloud-id"
check_var "YC_FOLDER_ID" "yc config get folder-id"
check_var "YC_ZONE" "echo 'ru-central1-a'"

echo ""
info "Checking SSH keys..."

# Check SSH keys
if [ ! -f "$HOME/.ssh/k8s-airflow" ] || [ ! -f "$HOME/.ssh/k8s-airflow.pub" ]; then
    warning "SSH keys not found"
    info "Creating SSH keys..."
    ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/k8s-airflow" -N "" -C "k8s-airflow"
    success "SSH keys created"
fi

check_var "SSH_PUBLIC_KEY_PATH" "echo '$HOME/.ssh/k8s-airflow.pub'"
check_var "SSH_PRIVATE_KEY_PATH" "echo '$HOME/.ssh/k8s-airflow'"

echo ""
info "Checking service accounts..."

# Check Terraform SA
if ! yc iam service-account get "terraform-sa" &>/dev/null; then
    warning "Terraform service account not found"
    NEED_SA_SETUP=true
else
    success "Terraform service account exists"
fi

# Check S3 SA
if ! yc iam service-account get "s3-storage-sa" &>/dev/null; then
    warning "S3 storage service account not found"
    NEED_SA_SETUP=true
else
    success "S3 storage service account exists"
fi

# Run SA setup if needed
if [ "$NEED_SA_SETUP" = "true" ]; then
    info "Setting up service accounts..."
    "${SCRIPT_DIR}/04-setup-service-accounts.sh"
fi

# Check Terraform key
if [ ! -f "${PROJECT_ROOT}/yc-terraform-key.json" ]; then
    if [ -f "${PROJECT_ROOT}/.artifacts/terraform-sa-key.json" ]; then
        info "Restoring Terraform key from artifacts..."
        cp "${PROJECT_ROOT}/.artifacts/terraform-sa-key.json" "${PROJECT_ROOT}/yc-terraform-key.json"
        chmod 600 "${PROJECT_ROOT}/yc-terraform-key.json"
    else
        warning "Terraform key not found"
        NEED_SA_SETUP=true
    fi
fi

check_var "YC_SERVICE_ACCOUNT_KEY_FILE" "echo '${PROJECT_ROOT}/yc-terraform-key.json'"

# Check S3 credentials
echo ""
info "Checking S3 credentials..."

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    if [ -f "${PROJECT_ROOT}/.artifacts/s3-keys.json" ]; then
        info "Loading S3 credentials from artifacts..."
        ACCESS_KEY=$(jq -r '.access_key' "${PROJECT_ROOT}/.artifacts/s3-keys.json")
        SECRET_KEY=$(jq -r '.secret_key' "${PROJECT_ROOT}/.artifacts/s3-keys.json")

        # Update .env
        sed -i.bak '/^export ACCESS_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
        sed -i.bak '/^export SECRET_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
        echo "export ACCESS_KEY=\"$ACCESS_KEY\"" >> "${PROJECT_ROOT}/.env"
        echo "export SECRET_KEY=\"$SECRET_KEY\"" >> "${PROJECT_ROOT}/.env"

        success "S3 credentials loaded from artifacts"
    else
        warning "S3 credentials not found"
        NEED_SA_SETUP=true
    fi
else
    success "S3 credentials are set"
fi

# Check bucket names
echo ""
info "Checking bucket configuration..."

if [ -z "$TF_STATE_BUCKET" ]; then
    info "Generating Terraform state bucket name..."
    TF_STATE_BUCKET="tfstate-k8s-airflow-${USER}-$(date +%s)"
    TF_STATE_BUCKET=$(echo "$TF_STATE_BUCKET" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
    echo "export TF_STATE_BUCKET=\"$TF_STATE_BUCKET\"" >> "${PROJECT_ROOT}/.env"
    export TF_STATE_BUCKET
fi

if [ -z "$LOKI_S3_BUCKET" ]; then
    info "Generating Loki bucket name..."
    LOKI_S3_BUCKET="loki-k8s-airflow-${USER}-$(date +%s)"
    LOKI_S3_BUCKET=$(echo "$LOKI_S3_BUCKET" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
    echo "export LOKI_S3_BUCKET=\"$LOKI_S3_BUCKET\"" >> "${PROJECT_ROOT}/.env"
    export LOKI_S3_BUCKET
fi

success "Bucket names configured"

# Summary
echo ""
step "Environment Check Summary"

ALL_GOOD=true

# Check all required variables
REQUIRED_VARS=(
    "YC_CLOUD_ID"
    "YC_FOLDER_ID"
    "YC_ZONE"
    "SSH_PUBLIC_KEY_PATH"
    "SSH_PRIVATE_KEY_PATH"
    "YC_SERVICE_ACCOUNT_KEY_FILE"
    "ACCESS_KEY"
    "SECRET_KEY"
    "TF_STATE_BUCKET"
    "LOKI_S3_BUCKET"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        error "$var is not set"
        ALL_GOOD=false
    else
        success "$var: OK"
    fi
done

# Check files
echo ""
info "Checking required files..."

if [ -f "${PROJECT_ROOT}/yc-terraform-key.json" ]; then
    success "Terraform key file: OK"
else
    error "Terraform key file: MISSING"
    ALL_GOOD=false
fi

if [ -f "$SSH_PUBLIC_KEY_PATH" ] && [ -f "$SSH_PRIVATE_KEY_PATH" ]; then
    success "SSH keys: OK"
else
    error "SSH keys: MISSING"
    ALL_GOOD=false
fi

# Final verdict
echo ""
if [ "$ALL_GOOD" = "true" ]; then
    success "Environment is properly configured!"
    info "You can proceed with infrastructure deployment"
else
    error "Environment has issues that need to be fixed"
    info "Run the suggested commands above to fix the issues"
    exit 1
fi

# Save environment check result
mkdir -p "${PROJECT_ROOT}/.artifacts"
cat > "${PROJECT_ROOT}/.artifacts/environment-check.txt" << EOF
Environment check performed at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Status: $( [ "$ALL_GOOD" = "true" ] && echo "PASSED" || echo "FAILED" )

Configuration:
  YC_CLOUD_ID: $YC_CLOUD_ID
  YC_FOLDER_ID: $YC_FOLDER_ID
  YC_ZONE: $YC_ZONE
  TF_STATE_BUCKET: $TF_STATE_BUCKET
  LOKI_S3_BUCKET: $LOKI_S3_BUCKET

Service Accounts:
  terraform-sa: $(yc iam service-account get terraform-sa &>/dev/null && echo "EXISTS" || echo "MISSING")
  s3-storage-sa: $(yc iam service-account get s3-storage-sa &>/dev/null && echo "EXISTS" || echo "MISSING")

Files:
  Terraform key: $([ -f "${PROJECT_ROOT}/yc-terraform-key.json" ] && echo "EXISTS" || echo "MISSING")
  SSH keys: $([ -f "$SSH_PUBLIC_KEY_PATH" ] && echo "EXISTS" || echo "MISSING")
EOF

success "Check results saved to: ${PROJECT_ROOT}/.artifacts/environment-check.txt"