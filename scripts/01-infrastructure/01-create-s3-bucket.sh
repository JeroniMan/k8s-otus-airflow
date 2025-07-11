#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Creating S3 Buckets for Terraform State and Loki"

# Load environment
load_env || exit 1

# Check prerequisites
check_prerequisites yc || exit 1

# Create service account for S3 if not exists
info "Checking S3 service account..."
SA_NAME="s3-storage-sa"

if ! yc iam service-account get "$SA_NAME" &>/dev/null; then
    info "Creating service account $SA_NAME..."
    yc iam service-account create --name "$SA_NAME" \
        --description "Service account for S3 storage"

    # Assign roles
    yc resource-manager folder add-access-binding \
        --id "$YC_FOLDER_ID" \
        --role storage.admin \
        --service-account-name "$SA_NAME"

    success "Service account created"
else
    success "Service account already exists"
fi

# Create access keys if not set
if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
    info "Creating S3 access keys..."

    # Create key
    KEY_OUTPUT=$(yc iam access-key create --service-account-name "$SA_NAME" --format json)

    ACCESS_KEY=$(echo "$KEY_OUTPUT" | jq -r '.access_key.key_id')
    SECRET_KEY=$(echo "$KEY_OUTPUT" | jq -r '.secret')

    # Update .env
    sed -i.bak "s/^export S3_ACCESS_KEY=.*/export S3_ACCESS_KEY=\"$ACCESS_KEY\"/" "${PROJECT_ROOT}/.env"
    sed -i.bak "s/^export S3_SECRET_KEY=.*/export S3_SECRET_KEY=\"$SECRET_KEY\"/" "${PROJECT_ROOT}/.env"

    success "Access keys created and saved to .env"

    # Reload env
    load_env
fi

# Function to create bucket
create_bucket() {
    local bucket_name="$1"
    local description="$2"

    if yc storage bucket get "$bucket_name" &>/dev/null; then
        success "Bucket $bucket_name already exists"
    else
        info "Creating bucket $bucket_name..."
        yc storage bucket create \
            --name "$bucket_name" \
            --default-storage-class standard \
            --max-size 10737418240 \
            --public-read

        success "Bucket $bucket_name created"
    fi
}

# Create Terraform state bucket
create_bucket "$TF_STATE_BUCKET" "Terraform state storage"

# Create Loki bucket
create_bucket "$LOKI_S3_BUCKET" "Loki logs storage"

echo ""
success "All S3 buckets are ready!"
info "Terraform state bucket: $TF_STATE_BUCKET"
info "Loki storage bucket: $LOKI_S3_BUCKET"