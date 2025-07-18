#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Destroying Terraform Infrastructure"

# Load environment
load_env || exit 1

cd "${PROJECT_ROOT}/infrastructure/terraform"

# Set AWS credentials for S3 backend
export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ] && ! terraform state list &>/dev/null; then
    warning "No Terraform state found. Nothing to destroy."
    exit 0
fi

# Show what will be destroyed
info "Getting destruction plan..."
terraform plan -destroy -out=destroy.tfplan

# Confirmation
echo ""
echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}⚠️  WARNING: This will destroy ALL infrastructure resources! ⚠️${NC}"
echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
echo ""
info "Resources to be destroyed:"
terraform show -json destroy.tfplan | jq -r '.resource_changes[] | select(.change.actions[] == "delete") | "  - \(.type): \(.name)"'
echo ""

read -p "Are you ABSOLUTELY sure? Type 'destroy' to confirm: " confirm

if [ "$confirm" != "destroy" ]; then
    info "Destruction cancelled"
    exit 0
fi

# Second confirmation for safety
read -p "This is your last chance. Type 'yes' to proceed: " confirm2

if [ "$confirm2" != "yes" ]; then
    info "Destruction cancelled"
    exit 0
fi

# Destroy infrastructure
info "Destroying infrastructure..."
terraform apply destroy.tfplan

# Clean up local files
info "Cleaning up local files..."
rm -f "${PROJECT_ROOT}/terraform-outputs.json"
rm -f "${PROJECT_ROOT}/infrastructure/ansible/inventory/hosts.yml"

success "Infrastructure destroyed successfully!"

# Note about S3 buckets
warning "Note: S3 buckets were not deleted to preserve state and logs."
info "To delete S3 buckets manually:"
info "  yc storage bucket delete --name $TF_STATE_BUCKET"
info "  yc storage bucket delete --name $LOKI_S3_BUCKET"

# Ask about cleaning up ALL cloud resources
echo ""
read -p "Do you want to delete S3 buckets and ALL service accounts? (yes/no): " delete_all

if [ "$delete_all" = "yes" ]; then
    info "Performing complete cleanup..."

    # Delete S3 buckets
    info "Deleting S3 buckets..."
    yc storage bucket delete --name "$TF_STATE_BUCKET" 2>/dev/null || warning "Failed to delete $TF_STATE_BUCKET"
    yc storage bucket delete --name "$LOKI_S3_BUCKET" 2>/dev/null || warning "Failed to delete $LOKI_S3_BUCKET"

    # Delete s3-storage-sa
    SA_NAME="s3-storage-sa"
    if yc iam service-account get "$SA_NAME" &>/dev/null; then
        info "Deleting $SA_NAME and its access keys..."

        # Delete all access keys
        ACCESS_KEYS=$(yc iam access-key list --service-account-name "$SA_NAME" --format json | jq -r '.[].id')
        for key_id in $ACCESS_KEYS; do
            yc iam access-key delete --id "$key_id" || true
        done

        # Delete service account
        yc iam service-account delete --name "$SA_NAME" || warning "Failed to delete $SA_NAME"
    fi

    # Delete terraform-sa
    SA_NAME="terraform-sa"
    if yc iam service-account get "$SA_NAME" &>/dev/null; then
        info "Deleting $SA_NAME and its keys..."

        # Delete all IAM keys
        IAM_KEYS=$(yc iam key list --service-account-name "$SA_NAME" --format json | jq -r '.[].id')
        for key_id in $IAM_KEYS; do
            yc iam key delete --id "$key_id" || true
        done

        # Delete service account
        yc iam service-account delete --name "$SA_NAME" || warning "Failed to delete $SA_NAME"
    fi

    # Clean up all key files and artifacts
    info "Cleaning up key files and artifacts..."
    rm -f "${PROJECT_ROOT}/yc-terraform-key.json"
    rm -f "${PROJECT_ROOT}/key.json"
    rm -rf "${PROJECT_ROOT}/.artifacts"

    # Clean up .env entries
    info "Cleaning up .env entries..."
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        sed -i.bak '/^export ACCESS_KEY=/d' "${PROJECT_ROOT}/.env"
        sed -i.bak '/^export SECRET_KEY=/d' "${PROJECT_ROOT}/.env"
        sed -i.bak '/^export YC_SERVICE_ACCOUNT_KEY_FILE=/d' "${PROJECT_ROOT}/.env"
    fi

    success "Complete cleanup finished!"

    # Show remaining resources
    echo ""
    info "Remaining service accounts in folder:"
    yc iam service-account list || true

    echo ""
    info "Remaining S3 buckets:"
    yc storage bucket list || true
fi