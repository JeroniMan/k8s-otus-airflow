#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Checking .env file"

# Try to load .env
if load_env; then
    success ".env file loaded successfully"
else
    error "Failed to load .env file"
    exit 1
fi

# Check required variables
info "Checking required environment variables..."

required_vars=(
    "YC_CLOUD_ID"
    "YC_FOLDER_ID"
    "YC_ZONE"
    "SSH_PUBLIC_KEY_PATH"
    "SSH_PRIVATE_KEY_PATH"
    "TF_STATE_BUCKET"
)

all_good=true
for var in "${required_vars[@]}"; do
    if [ -n "${!var}" ]; then
        success "$var is set: ${!var}"
    else
        error "$var is not set"
        all_good=false
    fi
done

if $all_good; then
    success "All required variables are set!"
else
    error "Some required variables are missing"
    info "Please check your .env file"
    exit 1
fi


set -e

source "$(dirname "$0")/../lib/common.sh"

step "Checking S3 Credentials"

# Load environment
load_env || exit 1

# Check S3 credentials
if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    error "S3 credentials not found in .env"
    info "Run scripts/01-infrastructure/01-create-s3-bucket.sh to create them"
    exit 1
fi

success "S3 credentials found"
info "Access Key: ${ACCESS_KEY:0:10}..."
info "Secret Key: ***hidden***"

# Test S3 access
info "Testing S3 access..."
export S3_ACCESS_KEY="$ACCESS_KEY"
export S3_SECRET_KEY="$SECRET_KEY"

export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"

if yc storage bucket list >/dev/null 2>&1; then
    success "S3 access working!"
    info "Buckets:"
    yc storage bucket list --format json | jq -r '.[].name' | sed 's/^/  - /'
else
    error "Cannot access S3"
    exit 1
fi

set -e

source "$(dirname "$0")/../lib/common.sh"

step "Checking Yandex Cloud Service Account Key"

# Load environment
load_env || exit 1

# Check if key file path is set
if [ -z "$YC_SERVICE_ACCOUNT_KEY_FILE" ]; then
    error "YC_SERVICE_ACCOUNT_KEY_FILE is not set in .env"
    exit 1
fi

info "Key file path: $YC_SERVICE_ACCOUNT_KEY_FILE"

# Expand path
KEY_FILE=$(eval echo "$YC_SERVICE_ACCOUNT_KEY_FILE")

# Check if file exists
if [ ! -f "$KEY_FILE" ]; then
    error "Key file not found: $KEY_FILE"
    info "To create a service account key:"
    info "  1. yc iam service-account create --name terraform-sa"
    info "  2. yc iam key create --service-account-name terraform-sa --output key.json"
    info "  3. Update YC_SERVICE_ACCOUNT_KEY_FILE in .env"
    exit 1
fi

# Check if file is valid JSON
if ! jq empty "$KEY_FILE" 2>/dev/null; then
    error "Key file is not valid JSON"
    info "Please recreate the service account key"
    exit 1
fi

# Check key structure
if ! jq -e '.id, .service_account_id, .private_key' "$KEY_FILE" >/dev/null 2>&1; then
    error "Key file is missing required fields"
    exit 1
fi

success "Service account key is valid"

# Show key info (without sensitive data)
info "Key ID: $(jq -r '.id' "$KEY_FILE")"
info "Service Account ID: $(jq -r '.service_account_id' "$KEY_FILE")"
info "Created At: $(jq -r '.created_at' "$KEY_FILE")"

# Test key by getting cloud list
info "Testing key..."
if YC_SERVICE_ACCOUNT_KEY_FILE="$KEY_FILE" yc resource-manager cloud list >/dev/null 2>&1; then
    success "Key is working!"
else
    error "Key authentication failed"
    exit 1
fi