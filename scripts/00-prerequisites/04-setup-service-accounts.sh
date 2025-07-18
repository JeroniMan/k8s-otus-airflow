#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Setting up Yandex Cloud Service Accounts"

# Load environment
load_env || exit 1

# Ensure we have folder ID
if [ -z "$YC_FOLDER_ID" ]; then
    YC_FOLDER_ID=$(yc config get folder-id)
    export YC_FOLDER_ID
fi

if [ -z "$YC_FOLDER_ID" ]; then
    error "YC_FOLDER_ID is not set and cannot be determined from yc config"
    exit 1
fi

info "Using Folder ID: $YC_FOLDER_ID"

# Create artifacts directory
mkdir -p "${PROJECT_ROOT}/.artifacts"

# Function to create or recreate service account
create_service_account() {
    local SA_NAME=$1
    local SA_DESCRIPTION=$2
    local SA_ROLES=("${@:3}")

    info "Setting up service account: $SA_NAME"

    # Check if SA exists
    if yc iam service-account get "$SA_NAME" &>/dev/null; then
        warning "Service account $SA_NAME already exists"
        read -p "Do you want to recreate it? (yes/no): " recreate

        if [ "$recreate" = "yes" ]; then
            info "Deleting existing service account..."

            # Delete all keys first
            OLD_KEYS=$(yc iam key list --service-account-name "$SA_NAME" --format json | jq -r '.[].id')
            for key_id in $OLD_KEYS; do
                yc iam key delete --id "$key_id" || true
            done

            # Delete all access keys
            OLD_ACCESS_KEYS=$(yc iam access-key list --service-account-name "$SA_NAME" --format json | jq -r '.[].id')
            for key_id in $OLD_ACCESS_KEYS; do
                yc iam access-key delete --id "$key_id" || true
            done

            # Delete service account
            yc iam service-account delete --name "$SA_NAME"
            sleep 3
        else
            return 0
        fi
    fi

    # Create service account
    info "Creating service account $SA_NAME..."
    yc iam service-account create \
        --name "$SA_NAME" \
        --description "$SA_DESCRIPTION"

    # Get SA ID
    local SA_ID=$(yc iam service-account get --name "$SA_NAME" --format json | jq -r '.id')
    info "Service Account ID: $SA_ID"

    # Save SA info
    yc iam service-account get "$SA_NAME" --format json > "${PROJECT_ROOT}/.artifacts/${SA_NAME}-info.json"

    # Assign roles
    info "Assigning roles to $SA_NAME..."
    for role in "${SA_ROLES[@]}"; do
        info "  Assigning role: $role"
        if yc resource-manager folder add-access-binding \
            --id "$YC_FOLDER_ID" \
            --role "$role" \
            --service-account-id "$SA_ID" 2>&1; then
            success "  Role $role assigned"
        else
            warning "  Could not assign role $role (might already exist)"
        fi
    done

    # Wait for role propagation
    sleep 5

    # Verify roles
    info "Verifying role assignments..."
    local ASSIGNED_ROLES=$(yc resource-manager folder list-access-bindings --id "$YC_FOLDER_ID" | grep "$SA_ID" | awk '{print $2}' | sort | uniq)
    if [ -n "$ASSIGNED_ROLES" ]; then
        success "Roles assigned to $SA_NAME:"
        echo "$ASSIGNED_ROLES" | sed 's/^/  - /'
    else
        error "No roles found for $SA_NAME!"
    fi

    echo ""
}

# 1. Terraform Service Account
TERRAFORM_SA_ROLES=(
    "editor"
    "vpc.publicAdmin"
    "load-balancer.admin"
    "compute.admin"
    "iam.serviceAccounts.user"
    "resource-manager.clouds.member"
)

create_service_account \
    "terraform-sa" \
    "Service account for Terraform infrastructure management" \
    "${TERRAFORM_SA_ROLES[@]}"

# Create key for Terraform SA
if [ -f "${PROJECT_ROOT}/yc-terraform-key.json" ]; then
    info "Terraform key already exists at ${PROJECT_ROOT}/yc-terraform-key.json"
    read -p "Do you want to recreate it? (yes/no): " recreate_key

    if [ "$recreate_key" = "yes" ]; then
        rm -f "${PROJECT_ROOT}/yc-terraform-key.json"
        info "Creating new service account key for Terraform..."
        yc iam key create \
            --service-account-name "terraform-sa" \
            --output "${PROJECT_ROOT}/yc-terraform-key.json"
        chmod 600 "${PROJECT_ROOT}/yc-terraform-key.json"

        # Update .env
        if grep -q "^export YC_SERVICE_ACCOUNT_KEY_FILE=" "${PROJECT_ROOT}/.env"; then
            sed -i.bak "s|^export YC_SERVICE_ACCOUNT_KEY_FILE=.*|export YC_SERVICE_ACCOUNT_KEY_FILE=\"${PROJECT_ROOT}/yc-terraform-key.json\"|" "${PROJECT_ROOT}/.env"
        else
            echo "export YC_SERVICE_ACCOUNT_KEY_FILE=\"${PROJECT_ROOT}/yc-terraform-key.json\"" >> "${PROJECT_ROOT}/.env"
        fi

        # Save copy to artifacts
        cp "${PROJECT_ROOT}/yc-terraform-key.json" "${PROJECT_ROOT}/.artifacts/terraform-sa-key.json"
    fi
else
    info "Creating service account key for Terraform..."
    yc iam key create \
        --service-account-name "terraform-sa" \
        --output "${PROJECT_ROOT}/yc-terraform-key.json"
    chmod 600 "${PROJECT_ROOT}/yc-terraform-key.json"

    # Update .env
    if grep -q "^export YC_SERVICE_ACCOUNT_KEY_FILE=" "${PROJECT_ROOT}/.env"; then
        sed -i.bak "s|^export YC_SERVICE_ACCOUNT_KEY_FILE=.*|export YC_SERVICE_ACCOUNT_KEY_FILE=\"${PROJECT_ROOT}/yc-terraform-key.json\"|" "${PROJECT_ROOT}/.env"
    else
        echo "export YC_SERVICE_ACCOUNT_KEY_FILE=\"${PROJECT_ROOT}/yc-terraform-key.json\"" >> "${PROJECT_ROOT}/.env"
    fi

    # Save copy to artifacts
    cp "${PROJECT_ROOT}/yc-terraform-key.json" "${PROJECT_ROOT}/.artifacts/terraform-sa-key.json"
fi

success "Terraform service account ready"

# 2. S3 Storage Service Account
S3_SA_ROLES=(
    "storage.admin"
    "storage.editor"
    "storage.viewer"
    "storage.uploader"
)

create_service_account \
    "s3-storage-sa" \
    "Service account for S3 storage access (Terraform state and Loki)" \
    "${S3_SA_ROLES[@]}"

# Create access keys for S3
info "Creating S3 access keys..."

# Clean up old keys
OLD_ACCESS_KEYS=$(yc iam access-key list --service-account-name "s3-storage-sa" --format json | jq -r '.[].id')
for key_id in $OLD_ACCESS_KEYS; do
    yc iam access-key delete --id "$key_id" || true
done

# Create new access key
KEY_OUTPUT=$(yc iam access-key create --service-account-name "s3-storage-sa" --format json)
NEW_ACCESS_KEY=$(echo "$KEY_OUTPUT" | jq -r '.access_key.key_id')
NEW_SECRET_KEY=$(echo "$KEY_OUTPUT" | jq -r '.secret')

if [ -z "$NEW_ACCESS_KEY" ] || [ -z "$NEW_SECRET_KEY" ] || [ "$NEW_ACCESS_KEY" = "null" ] || [ "$NEW_SECRET_KEY" = "null" ]; then
    error "Failed to create S3 access keys"
    exit 1
fi

# Save keys to artifacts
cat > "${PROJECT_ROOT}/.artifacts/s3-keys.json" << EOF
{
  "access_key": "$NEW_ACCESS_KEY",
  "secret_key": "$NEW_SECRET_KEY",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "service_account": "s3-storage-sa"
}
EOF
chmod 600 "${PROJECT_ROOT}/.artifacts/s3-keys.json"

# Update .env
info "Updating .env with S3 credentials..."
sed -i.bak '/^export ACCESS_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
sed -i.bak '/^export SECRET_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
sed -i.bak '/^export AWS_ACCESS_KEY_ID=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
sed -i.bak '/^export AWS_SECRET_ACCESS_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true

echo "export ACCESS_KEY=\"$NEW_ACCESS_KEY\"" >> "${PROJECT_ROOT}/.env"
echo "export SECRET_KEY=\"$NEW_SECRET_KEY\"" >> "${PROJECT_ROOT}/.env"
echo "export AWS_ACCESS_KEY_ID=\"$NEW_ACCESS_KEY\"" >> "${PROJECT_ROOT}/.env"
echo "export AWS_SECRET_ACCESS_KEY=\"$NEW_SECRET_KEY\"" >> "${PROJECT_ROOT}/.env"

success "S3 service account ready"

# 3. K8s Node Service Account (optional, for managed k8s)
K8S_NODE_SA_ROLES=(
    "compute.viewer"
    "vpc.privateAdmin"
    "load-balancer.privateAdmin"
)

create_service_account \
    "k8s-node-sa" \
    "Service account for Kubernetes nodes (optional)" \
    "${K8S_NODE_SA_ROLES[@]}"

# 4. Monitoring Service Account (optional, for cloud monitoring integration)
MONITORING_SA_ROLES=(
    "monitoring.viewer"
    "logging.viewer"
)

create_service_account \
    "monitoring-sa" \
    "Service account for monitoring integration (optional)" \
    "${MONITORING_SA_ROLES[@]}"

# Test all service accounts
echo ""
step "Testing Service Accounts"

# Test Terraform SA
info "Testing Terraform service account..."
if YC_SERVICE_ACCOUNT_KEY_FILE="${PROJECT_ROOT}/yc-terraform-key.json" yc resource-manager cloud list &>/dev/null; then
    success "Terraform SA: OK"
else
    error "Terraform SA: FAILED"
fi

# Test S3 SA
info "Testing S3 service account..."
export AWS_ACCESS_KEY_ID="$NEW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$NEW_SECRET_KEY"
if yc storage bucket list &>/dev/null; then
    success "S3 SA: OK"
else
    error "S3 SA: FAILED"
fi

# Create a helper script for quick SA check
cat > "${PROJECT_ROOT}/.artifacts/check-service-accounts.sh" << 'EOF'
#!/bin/bash
echo "Checking Yandex Cloud Service Accounts..."
echo ""
yc iam service-account list --format=table
echo ""
echo "Terraform SA roles:"
SA_ID=$(yc iam service-account get terraform-sa --format json | jq -r '.id')
yc resource-manager folder list-access-bindings --id $(yc config get folder-id) | grep $SA_ID
echo ""
echo "S3 SA roles:"
SA_ID=$(yc iam service-account get s3-storage-sa --format json | jq -r '.id')
yc resource-manager folder list-access-bindings --id $(yc config get folder-id) | grep $SA_ID
EOF
chmod +x "${PROJECT_ROOT}/.artifacts/check-service-accounts.sh"

# Summary
echo ""
step "Service Accounts Summary"

# List all service accounts
info "Created service accounts:"
yc iam service-account list --format json | jq -r '.[] | select(.name | test("terraform-sa|s3-storage-sa|k8s-node-sa|monitoring-sa")) | "  - \(.name) (ID: \(.id))"'

echo ""
info "Credentials saved to:"
echo "  - Terraform key: ${PROJECT_ROOT}/yc-terraform-key.json"
echo "  - S3 keys: ${PROJECT_ROOT}/.artifacts/s3-keys.json"
echo "  - All artifacts: ${PROJECT_ROOT}/.artifacts/"

echo ""
success "All service accounts configured successfully!"

# Add to .gitignore
if [ -f "${PROJECT_ROOT}/.gitignore" ]; then
    grep -q "yc-terraform-key.json" "${PROJECT_ROOT}/.gitignore" || echo "yc-terraform-key.json" >> "${PROJECT_ROOT}/.gitignore"
    grep -q ".artifacts/" "${PROJECT_ROOT}/.gitignore" || echo ".artifacts/" >> "${PROJECT_ROOT}/.gitignore"
fi

info "Next steps:"
echo "  1. Run: ./scripts/01-infrastructure/01-create-s3-bucket.sh"
echo "  2. Run: ./scripts/01-infrastructure/02-terraform-init.sh"