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