#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Installing Required Tools"

# Detect OS
OS="unknown"
if [ "$(uname)" = "Darwin" ]; then
    OS="macos"
elif [ -f /etc/debian_version ]; then
    OS="debian"
elif [ -f /etc/redhat-release ]; then
    OS="redhat"
fi

info "Detected OS: $OS"

# Function to install tool
install_tool() {
    local tool=$1
    local install_cmd=$2

    if ! command_exists "$tool"; then
        info "Installing $tool..."
        eval "$install_cmd"
        if command_exists "$tool"; then
            success "$tool installed"
        else
            error "Failed to install $tool"
            return 1
        fi
    else
        success "$tool already installed"
    fi
}

# macOS installation
if [ "$OS" = "macos" ]; then
    # Check Homebrew
    if ! command_exists brew; then
        error "Homebrew is required on macOS"
        info "Install with: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi

    # Update Homebrew
    info "Updating Homebrew..."
    brew update

    # Install tools
    install_tool "terraform" "brew install terraform"
    install_tool "ansible" "brew install ansible"
    install_tool "kubectl" "brew install kubectl"
    install_tool "helm" "brew install helm"
    install_tool "jq" "brew install jq"

    # Yandex Cloud CLI
    if ! command_exists yc; then
        info "Installing Yandex Cloud CLI..."
        curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash

        # Add to PATH
        if [ -d "$HOME/yandex-cloud/bin" ]; then
            echo 'export PATH="$HOME/yandex-cloud/bin:$PATH"' >> ~/.bash_profile
            echo 'export PATH="$HOME/yandex-cloud/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
            export PATH="$HOME/yandex-cloud/bin:$PATH"
        fi
    fi

    # Python packages
    info "Installing Python packages..."
    pip3 install --user cryptography pyyaml

# Linux installation
elif [ "$OS" = "debian" ]; then
    # Update package list
    sudo apt-get update

    # Install basic tools
    sudo apt-get install -y curl wget unzip python3-pip

    # Terraform
    if ! command_exists terraform; then
        info "Installing Terraform..."
        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update && sudo apt-get install -y terraform
    fi

    # Ansible
    install_tool "ansible" "pip3 install --user ansible==8.5.0"

    # kubectl
    if ! command_exists kubectl; then
        info "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    fi

    # Helm
    if ! command_exists helm; then
        info "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    # yc CLI
    if ! command_exists yc; then
        info "Installing Yandex Cloud CLI..."
        curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash

        # Add to PATH
        if [ -d "$HOME/yandex-cloud/bin" ]; then
            echo 'export PATH="$HOME/yandex-cloud/bin:$PATH"' >> ~/.bashrc
            export PATH="$HOME/yandex-cloud/bin:$PATH"
        fi
    fi

    # jq
    install_tool "jq" "sudo apt-get install -y jq"

    # Python packages
    pip3 install --user cryptography pyyaml

else
    error "Unsupported OS: $OS"
    exit 1
fi

# Add local bin to PATH if needed
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc 2>/dev/null || true
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
fi

success "All tools installed!"
info "You may need to restart your shell or run: source ~/.bashrc (or ~/.zshrc)"