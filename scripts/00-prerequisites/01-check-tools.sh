#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Checking Required Tools"

# Define required tools and versions
declare -A REQUIRED_TOOLS=(
    ["terraform"]="1.6"
    ["ansible"]="2.10"
    ["kubectl"]="1.28"
    ["helm"]="3.13"
    ["yc"]="0.100"
    ["jq"]="1.6"
    ["git"]="2.0"
)

# Check each tool
MISSING_TOOLS=()
WRONG_VERSION=()

for tool in "${!REQUIRED_TOOLS[@]}"; do
    required_version="${REQUIRED_TOOLS[$tool]}"

    if command_exists "$tool"; then
        # Get version
        case $tool in
            terraform)
                version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
            ansible)
                version=$(ansible --version | head -1 | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
            kubectl)
                version=$(kubectl version --client --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | tr -d 'v' || echo "0.0")
                ;;
            helm)
                version=$(helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | tr -d 'v' || echo "0.0")
                ;;
            yc)
                version=$(yc version | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
            jq)
                version=$(jq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
            git)
                version=$(git --version | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
        esac

        # Compare versions (simple major.minor check)
        if [[ "${version}" < "${required_version}" ]]; then
            warning "$tool version $version is older than required $required_version"
            WRONG_VERSION+=("$tool")
        else
            success "$tool $version ${CHECK_MARK}"
        fi
    else
        error "$tool not found ${CROSS_MARK}"
        MISSING_TOOLS+=("$tool")
    fi
done

echo ""

# Check Python packages
info "Checking Python packages..."
if command_exists python3; then
    success "Python3 $(python3 --version | cut -d' ' -f2) ${CHECK_MARK}"

    if python3 -c "import cryptography" 2>/dev/null; then
        success "cryptography module ${CHECK_MARK}"
    else
        warning "cryptography module not found"
        MISSING_TOOLS+=("python3-cryptography")
    fi
else
    error "Python3 not found ${CROSS_MARK}"
    MISSING_TOOLS+=("python3")
fi

echo ""

# Check Yandex Cloud configuration
info "Checking Yandex Cloud configuration..."
if command_exists yc; then
    if yc config list &>/dev/null; then
        success "Yandex Cloud CLI configured ${CHECK_MARK}"
        yc config list | grep -E "cloud-id|folder-id" | sed 's/^/  /'
    else
        warning "Yandex Cloud CLI not configured"
        info "Run: yc init"
    fi
fi

echo ""

# Summary
if [ ${#MISSING_TOOLS[@]} -eq 0 ] && [ ${#WRONG_VERSION[@]} -eq 0 ]; then
    success "All tools are installed and configured!"
    exit 0
else
    if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
        error "Missing tools: ${MISSING_TOOLS[*]}"
    fi
    if [ ${#WRONG_VERSION[@]} -ne 0 ]; then
        warning "Tools with wrong version: ${WRONG_VERSION[*]}"
    fi
    echo ""
    info "Run: ./scripts/00-prerequisites/02-install-tools.sh"
    exit 1
fi