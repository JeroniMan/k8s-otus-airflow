#!/bin/bash
# scripts/01-infrastructure/01-create-s3-bucket.sh

set -e

source "$(dirname "$0")/../lib/common.sh"

step "Creating S3 Buckets for Terraform State and Loki"

# Load environment
load_env || exit 1

# Ensure we have folder ID
if [ -z "$YC_FOLDER_ID" ] || [ "$YC_FOLDER_ID" = '$(yc config get folder-id)' ]; then
    YC_FOLDER_ID=$(yc config get folder-id)
    export YC_FOLDER_ID
    info "Setting YC_FOLDER_ID from yc config: $YC_FOLDER_ID"
fi

# Verify folder ID is valid
if [ -z "$YC_FOLDER_ID" ] || [ "$YC_FOLDER_ID" = '$(yc config get folder-id)' ]; then
    error "YC_FOLDER_ID is not properly set!"
    error "Please run: export YC_FOLDER_ID=\$(yc config get folder-id)"
    exit 1
fi

info "Using Folder ID: $YC_FOLDER_ID"

# Check prerequisites
check_prerequisites yc jq || exit 1

# Check if service accounts are configured
info "Checking service accounts..."
if ! yc iam service-account get "s3-storage-sa" &>/dev/null; then
    error "S3 storage service account not found!"
    info "Running service account setup..."
    "${SCRIPT_DIR}/../00-prerequisites/04-setup-service-accounts.sh"

    # Reload environment to get new keys
    load_env || exit 1
fi

# Verify we have S3 credentials
if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    error "S3 credentials not found in environment"
    info "Trying to load from artifacts..."

    if [ -f "${PROJECT_ROOT}/.artifacts/s3-keys.json" ]; then
        ACCESS_KEY=$(jq -r '.access_key' "${PROJECT_ROOT}/.artifacts/s3-keys.json")
        SECRET_KEY=$(jq -r '.secret_key' "${PROJECT_ROOT}/.artifacts/s3-keys.json")
        export ACCESS_KEY
        export SECRET_KEY
        export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"

        # Update .env
        sed -i.bak '/^export ACCESS_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
        sed -i.bak '/^export SECRET_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
        sed -i.bak '/^export AWS_ACCESS_KEY_ID=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
        sed -i.bak '/^export AWS_SECRET_ACCESS_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true

        echo "export ACCESS_KEY=\"$ACCESS_KEY\"" >> "${PROJECT_ROOT}/.env"
        echo "export SECRET_KEY=\"$SECRET_KEY\"" >> "${PROJECT_ROOT}/.env"
        echo "export AWS_ACCESS_KEY_ID=\"$ACCESS_KEY\"" >> "${PROJECT_ROOT}/.env"
        echo "export AWS_SECRET_ACCESS_KEY=\"$SECRET_KEY\"" >> "${PROJECT_ROOT}/.env"

        success "Loaded S3 credentials from artifacts"
    else
        error "No S3 credentials found!"
        error "Please run: ./scripts/00-prerequisites/04-setup-service-accounts.sh"
        exit 1
    fi
fi

# Test S3 access
info "Testing S3 access..."
if yc storage bucket list &>/dev/null; then
    success "S3 access test passed!"
else
    error "S3 access test failed"
    error "Debug info:"
    echo "Folder ID: $YC_FOLDER_ID"
    echo "Access Key: ${ACCESS_KEY:0:10}..."

    # Try to fix by recreating access keys
    info "Trying to recreate access keys..."
    SA_NAME="s3-storage-sa"

    # Clean up old keys
    OLD_ACCESS_KEYS=$(yc iam access-key list --service-account-name "$SA_NAME" --format json | jq -r '.[].id')
    for key_id in $OLD_ACCESS_KEYS; do
        yc iam access-key delete --id "$key_id" || true
    done

    # Create new keys
    KEY_OUTPUT=$(yc iam access-key create --service-account-name "$SA_NAME" --format json)
    NEW_ACCESS_KEY=$(echo "$KEY_OUTPUT" | jq -r '.access_key.key_id')
    NEW_SECRET_KEY=$(echo "$KEY_OUTPUT" | jq -r '.secret')

    if [ -n "$NEW_ACCESS_KEY" ] && [ -n "$NEW_SECRET_KEY" ] && [ "$NEW_ACCESS_KEY" != "null" ] && [ "$NEW_SECRET_KEY" != "null" ]; then
        # Update environment
        export ACCESS_KEY="$NEW_ACCESS_KEY"
        export SECRET_KEY="$NEW_SECRET_KEY"
        export AWS_ACCESS_KEY_ID="$NEW_ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$NEW_SECRET_KEY"

        # Save to artifacts
        mkdir -p "${PROJECT_ROOT}/.artifacts"
        cat > "${PROJECT_ROOT}/.artifacts/s3-keys.json" << EOF
{
  "access_key": "$NEW_ACCESS_KEY",
  "secret_key": "$NEW_SECRET_KEY",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "service_account": "$SA_NAME"
}
EOF
        chmod 600 "${PROJECT_ROOT}/.artifacts/s3-keys.json"

        # Update .env
        sed -i.bak '/^export ACCESS_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
        sed -i.bak '/^export SECRET_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
        sed -i.bak '/^export AWS_ACCESS_KEY_ID=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true
        sed -i.bak '/^export AWS_SECRET_ACCESS_KEY=/d' "${PROJECT_ROOT}/.env" 2>/dev/null || true

        echo "export ACCESS_KEY=\"$NEW_ACCESS_KEY\"" >> "${PROJECT_ROOT}/.env"
        echo "export SECRET_KEY=\"$NEW_SECRET_KEY\"" >> "${PROJECT_ROOT}/.env"
        echo "export AWS_ACCESS_KEY_ID=\"$NEW_ACCESS_KEY\"" >> "${PROJECT_ROOT}/.env"
        echo "export AWS_SECRET_ACCESS_KEY=\"$NEW_SECRET_KEY\"" >> "${PROJECT_ROOT}/.env"

        success "New access keys created"

        # Test again
        if yc storage bucket list &>/dev/null; then
            success "S3 access now working!"
        else
            error "Still cannot access S3. Please check service account permissions."
            exit 1
        fi
    else
        error "Failed to create new access keys"
        exit 1
    fi
fi

# Function to create bucket
create_bucket() {
    local bucket_name="$1"
    local description="$2"

    if [ -z "$bucket_name" ]; then
        error "Bucket name is empty"
        return 1
    fi

    if yc storage bucket get "$bucket_name" &>/dev/null; then
        success "Bucket $bucket_name already exists"
    else
        info "Creating bucket $bucket_name..."
        if yc storage bucket create \
            --name "$bucket_name" \
            --default-storage-class standard \
            --max-size 10737418240 \
            --public-read; then
            success "Bucket $bucket_name created"

            # Save bucket info
            mkdir -p "${PROJECT_ROOT}/.artifacts"
            yc storage bucket get "$bucket_name" --format json > "${PROJECT_ROOT}/.artifacts/${bucket_name}-info.json"
        else
            error "Failed to create bucket $bucket_name"

            # Check if it's a naming issue
            if [[ "$bucket_name" =~ [A-Z] ]]; then
                error "Bucket name contains uppercase letters. S3 bucket names must be lowercase."
            fi

            # Check if it's a uniqueness issue
            error "Bucket names must be globally unique. Try a different name."
            return 1
        fi
    fi
}

# Check if bucket names are set
if [ -z "$TF_STATE_BUCKET" ]; then
    error "TF_STATE_BUCKET is not set in .env"
    info "Generating unique bucket name..."
    TF_STATE_BUCKET="tfstate-k8s-airflow-${USER}-$(date +%s)"
    echo "export TF_STATE_BUCKET=\"$TF_STATE_BUCKET\"" >> "${PROJECT_ROOT}/.env"
    export TF_STATE_BUCKET
    info "Using bucket name: $TF_STATE_BUCKET"
fi

if [ -z "$LOKI_S3_BUCKET" ]; then
    warning "LOKI_S3_BUCKET is not set, using default"
    LOKI_S3_BUCKET="loki-k8s-airflow-${USER}-$(date +%s)"
    echo "export LOKI_S3_BUCKET=\"$LOKI_S3_BUCKET\"" >> "${PROJECT_ROOT}/.env"
    export LOKI_S3_BUCKET
fi

# Ensure bucket names are lowercase and valid
TF_STATE_BUCKET=$(echo "$TF_STATE_BUCKET" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
LOKI_S3_BUCKET=$(echo "$LOKI_S3_BUCKET" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')

# Create Terraform state bucket
create_bucket "$TF_STATE_BUCKET" "Terraform state storage"

# Create Loki bucket
create_bucket "$LOKI_S3_BUCKET" "Loki logs storage"

# Save bucket list to artifacts
mkdir -p "${PROJECT_ROOT}/.artifacts"
yc storage bucket list --format json > "${PROJECT_ROOT}/.artifacts/s3-buckets.json"

# Test write access to buckets
info "Testing write access to buckets..."
echo "test" > /tmp/test-file.txt

if aws s3 cp /tmp/test-file.txt "s3://$TF_STATE_BUCKET/test-write.txt" \
    --endpoint-url=https://storage.yandexcloud.net &>/dev/null; then
    success "Write access to Terraform state bucket confirmed"
    aws s3 rm "s3://$TF_STATE_BUCKET/test-write.txt" --endpoint-url=https://storage.yandexcloud.net &>/dev/null
else
    warning "Cannot test write access with AWS CLI"
fi

rm -f /tmp/test-file.txt

echo ""
success "All S3 buckets are ready!"
info "Terraform state bucket: $TF_STATE_BUCKET"
info "Loki storage bucket: $LOKI_S3_BUCKET"
info "Access Key: ${ACCESS_KEY:0:10}..."
info "Artifacts saved to: ${PROJECT_ROOT}/.artifacts/"

# Update .env with correct bucket names if they were modified
sed -i.bak "s/^export TF_STATE_BUCKET=.*/export TF_STATE_BUCKET=\"$TF_STATE_BUCKET\"/" "${PROJECT_ROOT}/.env"
sed -i.bak "s/^export LOKI_S3_BUCKET=.*/export LOKI_S3_BUCKET=\"$LOKI_S3_BUCKET\"/" "${PROJECT_ROOT}/.env"

info "Next step: ./scripts/01-infrastructure/02-terraform-init.sh"