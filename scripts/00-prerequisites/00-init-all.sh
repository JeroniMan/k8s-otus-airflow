#!/bin/bash
# scripts/00-prerequisites/00-init-all.sh
# Complete initialization script that sets up everything from scratch

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${PURPLE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${PURPLE}     K8S + Airflow Infrastructure - Complete Setup              ${NC}"
echo -e "${PURPLE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Check .env file
echo -e "${BLUE}[Step 1/6]${NC} Checking environment file..."
if [ ! -f "${PROJECT_ROOT}/.env" ]; then
    if [ -f "${PROJECT_ROOT}/.env.example" ]; then
        echo -e "${YELLOW}Creating .env from .env.example...${NC}"
        cp "${PROJECT_ROOT}/.env.example" "${PROJECT_ROOT}/.env"
        echo -e "${YELLOW}Please edit .env file with your values and run this script again.${NC}"
        exit 1
    else
        echo -e "${RED}No .env or .env.example file found!${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓ Environment file found${NC}"

# Step 2: Check and install tools
echo ""
echo -e "${BLUE}[Step 2/6]${NC} Checking required tools..."
"${SCRIPT_DIR}/01-check-tools.sh" || {
    echo -e "${YELLOW}Installing missing tools...${NC}"
    "${SCRIPT_DIR}/02-install-tools.sh"
}

# Step 3: Setup Yandex Cloud CLI
echo ""
echo -e "${BLUE}[Step 3/6]${NC} Setting up Yandex Cloud CLI..."
"${SCRIPT_DIR}/03-setup-yc.sh"

# Step 4: Setup service accounts (this is now included in setup-yc.sh)
# But we'll double-check
echo ""
echo -e "${BLUE}[Step 4/6]${NC} Verifying service accounts..."
if ! yc iam service-account get "terraform-sa" &>/dev/null || ! yc iam service-account get "s3-storage-sa" &>/dev/null; then
    echo -e "${YELLOW}Setting up service accounts...${NC}"
    "${SCRIPT_DIR}/04-setup-service-accounts.sh"
fi

# Step 5: Create SSH keys if needed
echo ""
echo -e "${BLUE}[Step 5/6]${NC} Checking SSH keys..."
if [ ! -f "$HOME/.ssh/k8s-airflow" ] || [ ! -f "$HOME/.ssh/k8s-airflow.pub" ]; then
    echo -e "${YELLOW}Creating SSH keys...${NC}"
    ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/k8s-airflow" -N "" -C "k8s-airflow@$(hostname)"
    echo -e "${GREEN}✓ SSH keys created${NC}"
else
    echo -e "${GREEN}✓ SSH keys exist${NC}"
fi

# Step 6: Final environment check
echo ""
echo -e "${BLUE}[Step 6/6]${NC} Running final environment check..."
"${SCRIPT_DIR}/05-check-environment.sh"

# Success!
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}     ✓ Environment setup completed successfully!                ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Create S3 buckets:     ./scripts/01-infrastructure/01-create-s3-bucket.sh"
echo "  2. Initialize Terraform:  ./scripts/01-infrastructure/02-terraform-init.sh"
echo "  3. Deploy infrastructure: ./scripts/01-infrastructure/03-terraform-apply.sh"
echo ""
echo "Or run everything at once: make deploy"
echo ""

# Create initialization marker
mkdir -p "${PROJECT_ROOT}/.artifacts"
cat > "${PROJECT_ROOT}/.artifacts/init-complete.txt" << EOF
Initialization completed at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
User: $(whoami)
Host: $(hostname)
YC_CLOUD_ID: $(yc config get cloud-id)
YC_FOLDER_ID: $(yc config get folder-id)
EOF

echo -e "${BLUE}Artifacts saved to: ${PROJECT_ROOT}/.artifacts/${NC}"