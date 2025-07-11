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
        --service-account-name "$SA_NAME" || {
            warning "Failed to assign role. Trying with service account ID..."
            SA_ID=$(yc iam service-account get --name "$SA_NAME" --format json | jq -r '.id')
            yc resource-manager folder add-access-binding \
                --id "$YC_FOLDER_ID" \
                --role storage.admin \
                --subject "serviceAccount:$SA_ID"
        }

    success "Service account created"
else
    success "Service account already exists"
fi

# Create access keys if not set
if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    info "Creating S3 access keys..."

    # Create key
    KEY_OUTPUT=$(yc iam access-key create --service-account-name "$SA_NAME" --format json)

    NEW_ACCESS_KEY=$(echo "$KEY_OUTPUT" | jq -r '.access_key.key_id')
    NEW_SECRET_KEY=$(echo "$KEY_OUTPUT" | jq -r '.secret')

    # Update .env
    if grep -q "^export ACCESS_KEY=" "${PROJECT_ROOT}/.env"; then
        sed -i.bak "s/^export ACCESS_KEY=.*/export ACCESS_KEY=\"$NEW_ACCESS_KEY\"/" "${PROJECT_ROOT}/.env"
    else
        echo "export ACCESS_KEY=\"$NEW_ACCESS_KEY\"" >> "${PROJECT_ROOT}/.env"
    fi

    if grep -q "^export SECRET_KEY=" "${PROJECT_ROOT}/.env"; then
        sed -i.bak "s/^export SECRET_KEY=.*/export SECRET_KEY=\"$NEW_SECRET_KEY\"/" "${PROJECT_ROOT}/.env"
    else
        echo "export SECRET_KEY=\"$NEW_SECRET_KEY\"" >> "${PROJECT_ROOT}/.env"
    fi

    success "Access keys created and saved to .env"

    # Reload env
    load_env
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
        else
            error "Failed to create bucket $bucket_name"
            return 1
        fi
    fi
}

# Check if bucket names are set
if [ -z "$TF_STATE_BUCKET" ]; then
    error "TF_STATE_BUCKET is not set in .env"
    exit 1
fi

if [ -z "$LOKI_S3_BUCKET" ]; then
    warning "LOKI_S3_BUCKET is not set, using default"
    LOKI_S3_BUCKET="loki-k8s-airflow-$(date +%s)"

    # Update .env
    echo "export LOKI_S3_BUCKET=\"$LOKI_S3_BUCKET\"" >> "${PROJECT_ROOT}/.env"
fi

# Create Terraform state bucket
create_bucket "$TF_STATE_BUCKET" "Terraform state storage"

# Create Loki bucket
create_bucket "$LOKI_S3_BUCKET" "Loki logs storage"

echo ""
success "All S3 buckets are ready!"
info "Terraform state bucket: $TF_STATE_BUCKET"
info "Loki storage bucket: $LOKI_S3_BUCKET"