#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "COMPLETE INFRASTRUCTURE DESTRUCTION"

echo ""
echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                    ⚠️  DANGER ZONE ⚠️                           ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║  This will destroy:                                            ║${NC}"
echo -e "${RED}║  - All Kubernetes applications                                 ║${NC}"
echo -e "${RED}║  - The entire k3s cluster                                      ║${NC}"
echo -e "${RED}║  - All virtual machines                                        ║${NC}"
echo -e "${RED}║  - Load balancer                                               ║${NC}"
echo -e "${RED}║  - Network infrastructure                                      ║${NC}"
echo -e "${RED}║  - All data (except S3 buckets)                              ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

read -p "Are you sure you want to destroy EVERYTHING? Type 'yes' to confirm: " confirm

if [ "$confirm" != "yes" ]; then
    info "Destruction cancelled"
    exit 0
fi

# Load environment
load_env || exit 1

# Step 1: Backup important data
info "Creating backup of configurations..."
BACKUP_DIR="${PROJECT_ROOT}/backups/destroy-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup configurations
cp "${PROJECT_ROOT}/.env" "$BACKUP_DIR/" 2>/dev/null || true
cp "${PROJECT_ROOT}/kubeconfig" "$BACKUP_DIR/" 2>/dev/null || true
cp "${PROJECT_ROOT}/argocd-password.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "${PROJECT_ROOT}/terraform-outputs.json" "$BACKUP_DIR/" 2>/dev/null || true
cp -r "${PROJECT_ROOT}/infrastructure/terraform/terraform.tfstate"* "$BACKUP_DIR/" 2>/dev/null || true

success "Backup created in: $BACKUP_DIR"

# Step 2: Clean up Kubernetes resources
if [ -f "${PROJECT_ROOT}/kubeconfig" ]; then
    info "Cleaning up Kubernetes resources..."
    "${SCRIPT_DIR}/../05-operations/04-cleanup.sh" || warning "Some Kubernetes resources may not have been cleaned"
else
    warning "kubeconfig not found, skipping Kubernetes cleanup"
fi

# Step 3: Destroy Terraform infrastructure
info "Destroying Terraform infrastructure..."
"${SCRIPT_DIR}/../01-infrastructure/04-terraform-destroy.sh"

# Step 4: Optional - Delete S3 buckets
echo ""
info "S3 buckets were preserved. To delete them:"
echo "  yc storage bucket delete --name $TF_STATE_BUCKET"
echo "  yc storage bucket delete --name $LOKI_S3_BUCKET"
echo ""
read -p "Do you want to delete S3 buckets now? (yes/no): " delete_s3

if [ "$delete_s3" = "yes" ]; then
    info "Deleting S3 buckets..."
    yc storage bucket delete --name "$TF_STATE_BUCKET" 2>/dev/null || warning "Failed to delete $TF_STATE_BUCKET"
    yc storage bucket delete --name "$LOKI_S3_BUCKET" 2>/dev/null || warning "Failed to delete $LOKI_S3_BUCKET"

    # Clean up service account
    info "Cleaning up service account..."
    yc iam service-account delete --name s3-storage-sa 2>/dev/null || true
fi

# Step 5: Final cleanup
info "Final cleanup..."
rm -f "${PROJECT_ROOT}/.env.bak"*
rm -f "${PROJECT_ROOT}/infrastructure/terraform/.terraform.lock.hcl"
rm -rf "${PROJECT_ROOT}/infrastructure/terraform/.terraform"
rm -f "${PROJECT_ROOT}/infrastructure/terraform/destroy.tfplan"
rm -f "${PROJECT_ROOT}/infrastructure/terraform/tfplan"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Infrastructure has been completely destroyed${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
info "Backup of configurations saved in: $BACKUP_DIR"
info "Thank you for using k3s-airflow-infrastructure!"