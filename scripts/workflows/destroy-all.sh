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
fi

# Step 4.5: Clean up service accounts and access keys
echo ""
read -p "Do you want to delete ALL service accounts and access keys? (yes/no): " delete_sa

if [ "$delete_sa" = "yes" ]; then
    info "Cleaning up ALL service accounts..."

    # Delete S3 service account
    SA_NAME="s3-storage-sa"
    if yc iam service-account get "$SA_NAME" &>/dev/null; then
        # Delete all access keys first
        info "Deleting access keys for $SA_NAME..."
        ACCESS_KEYS=$(yc iam access-key list --service-account-name "$SA_NAME" --format json | jq -r '.[].id')
        for key_id in $ACCESS_KEYS; do
            yc iam access-key delete --id "$key_id" || true
        done

        # Delete the service account
        info "Deleting service account $SA_NAME..."
        yc iam service-account delete --name "$SA_NAME" || true
    fi

    # Delete terraform service account
    SA_NAME="terraform-sa"
    if yc iam service-account get "$SA_NAME" &>/dev/null; then
        # Delete all IAM keys first
        info "Deleting IAM keys for $SA_NAME..."
        IAM_KEYS=$(yc iam key list --service-account-name "$SA_NAME" --format json | jq -r '.[].id')
        for key_id in $IAM_KEYS; do
            yc iam key delete --id "$key_id" || true
        done

        # Delete the service account
        info "Deleting service account $SA_NAME..."
        yc iam service-account delete --name "$SA_NAME" || true
    fi

    # Clean up key files
    rm -f "${PROJECT_ROOT}/yc-terraform-key.json"
    rm -f "${PROJECT_ROOT}/key.json"
    rm -rf "${PROJECT_ROOT}/.artifacts"

    # Clean up .env entries
    info "Cleaning up .env entries..."
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        sed -i.bak '/^export ACCESS_KEY=/d' "${PROJECT_ROOT}/.env"
        sed -i.bak '/^export SECRET_KE