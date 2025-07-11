#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Checking Required Tools"

# Define required tools and versions (compatible with bash 3.x)
TOOLS=("terraform" "ansible" "kubectl" "helm" "yc" "jq" "git")
VERSIONS=("1.6" "2.10" "1.28" "3.13" "0.100" "1.6" "2.0")

# Check each tool
MISSING_TOOLS=()
WRONG_VERSION=()

for i in "${!TOOLS[@]}"; do
    tool="${TOOLS[$i]}"
    required_version="${VERSIONS[$i]}"

    if command_exists "$tool"; then
        # Get version
        case $tool in
            terraform)
                version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
            ansible)
                version=$(ansible --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
            kubectl)
                version=$(kubectl version --client --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | tr -d 'v' || kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | tr -d 'v' | head -1 || echo "0.0")
                ;;
            helm)
                version=$(helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | tr -d 'v' || echo "0.0")
                ;;
            yc)
                version=$(yc version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
            jq)
                version=$(jq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
            git)
                version=$(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
                ;;
        esac

        # Compare versions (simple major.minor check)
        # Using awk for compatibility with older bash
        version_ok=$(echo "$version $required_version" | awk '{if ($1 >= $2) print "yes"; else print "no"}')

        if [ "$version_ok" = "no" ]; then
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
    success "Python3 $(python3 --version 2>&1 | cut -d' ' -f2) ${CHECK_MARK}"

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
    if yc config list >/dev/null 2>&1; then
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