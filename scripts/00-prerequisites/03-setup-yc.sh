#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Setting up Yandex Cloud CLI"

# Check if yc is installed
if ! command_exists yc; then
    error "Yandex Cloud CLI is not installed"
    info "Run: ./scripts/00-prerequisites/02-install-tools.sh"
    exit 1
fi

# Check if already configured
if yc config list >/dev/null 2>&1 && [ -n "$(yc config get cloud-id 2>/dev/null)" ]; then
    success "Yandex Cloud CLI is already configured"
    info "Current configuration:"
    yc config list
    echo ""
    read -p "Do you want to reconfigure? (yes/no): " reconfigure
    if [ "$reconfigure" != "yes" ]; then
        exit 0
    fi
fi

# Initialize yc
info "Initializing Yandex Cloud CLI..."
info "You will need:"
info "  - Yandex account"
info "  - OAuth token from https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb"
echo ""

yc init

# Verify configuration
if yc config list >/dev/null 2>&1; then
    success "Yandex Cloud CLI configured successfully!"

    # Get configuration values
    CLOUD_ID=$(yc config get cloud-id 2>/dev/null || echo "")
    FOLDER_ID=$(yc config get folder-id 2>/dev/null || echo "")

    # Update .env file
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        info "Updating .env file with Yandex Cloud IDs..."

        # Backup .env
        cp "${PROJECT_ROOT}/.env" "${PROJECT_ROOT}/.env.backup"

        # Update values
        if [ -n "$CLOUD_ID" ]; then
            if grep -q "^export YC_CLOUD_ID=" "${PROJECT_ROOT}/.env"; then
                sed -i.bak "s/^export YC_CLOUD_ID=.*/export YC_CLOUD_ID=\"$CLOUD_ID\"/" "${PROJECT_ROOT}/.env"
            else
                echo "export YC_CLOUD_ID=\"$CLOUD_ID\"" >> "${PROJECT_ROOT}/.env"
            fi
        fi

        if [ -n "$FOLDER_ID" ]; then
            if grep -q "^export YC_FOLDER_ID=" "${PROJECT_ROOT}/.env"; then
                sed -i.bak "s/^export YC_FOLDER_ID=.*/export YC_FOLDER_ID=\"$FOLDER_ID\"/" "${PROJECT_ROOT}/.env"
            else
                echo "export YC_FOLDER_ID=\"$FOLDER_ID\"" >> "${PROJECT_ROOT}/.env"
            fi
        fi

        success ".env file updated"
    else
        warning ".env file not found. Please update YC_CLOUD_ID and YC_FOLDER_ID manually"
    fi

    # Show current configuration
    echo ""
    info "Current Yandex Cloud configuration:"
    yc config list

else
    error "Failed to configure Yandex Cloud CLI"
    exit 1
fi

# Create service account key if specified
echo ""
read -p "Do you want to create a service account key for Terraform? (yes/no): " create_sa

if [ "$create_sa" = "yes" ]; then
    SA_NAME="terraform-sa"

    # Check if service account exists
    if yc iam service-account get "$SA_NAME" >/dev/null 2>&1; then
        info "Service account $SA_NAME already exists"
    else
        info "Creating service account $SA_NAME..."
        yc iam service-account create --name "$SA_NAME" \
            --description "Service account for Terraform"
    fi

    # Assign roles
    info "Assigning roles to service account..."
    for role in editor vpc.publicAdmin load-balancer.admin compute.admin iam.serviceAccounts.user; do
        yc resource-manager folder add-access-binding \
            --id "$FOLDER_ID" \
            --role "$role" \
            --service-account-name "$SA_NAME" >/dev/null 2>&1 || true
    done

    # Create key
    KEY_FILE="${PROJECT_ROOT}/yc-terraform-key.json"
    if [ -f "$KEY_FILE" ]; then
        warning "Key file already exists: $KEY_FILE"
        read -p "Overwrite? (yes/no): " overwrite
        if [ "$overwrite" != "yes" ]; then
            exit 0
        fi
    fi

    info "Creating service account key..."
    yc iam key create \
        --service-account-name "$SA_NAME" \
        --output "$KEY_FILE"

    # Update .env
    if grep -q "^export YC_SERVICE_ACCOUNT_KEY_FILE=" "${PROJECT_ROOT}/.env"; then
        sed -i.bak "s|^export YC_SERVICE_ACCOUNT_KEY_FILE=.*|export YC_SERVICE_ACCOUNT_KEY_FILE=\"$KEY_FILE\"|" "${PROJECT_ROOT}/.env"
    else
        echo "export YC_SERVICE_ACCOUNT_KEY_FILE=\"$KEY_FILE\"" >> "${PROJECT_ROOT}/.env"
    fi

    success "Service account key created: $KEY_FILE"
    warning "Keep this key secure and do not commit it to git!"
fi

success "Yandex Cloud setup complete!"