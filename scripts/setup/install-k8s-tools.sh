# scripts/setup/install-k8s-tools.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

K8S_VERSION="v1.28.0"
HELM_VERSION="v3.13.0"

log STEP "Установка Kubernetes инструментов"

# Установка kubectl
if ! check_command kubectl; then
    log INFO "Установка kubectl ${K8S_VERSION}..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        ARCH="darwin/amd64"
        if [[ $(uname -m) == "arm64" ]]; then
            ARCH="darwin/arm64"
        fi
    else
        ARCH="linux/amd64"
    fi

    curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/${ARCH}/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/

    log SUCCESS "kubectl установлен"
else
    log INFO "kubectl уже установлен: $(kubectl version --client --short 2>/dev/null || kubectl version --client | grep 'Client Version')"
fi

# Установка Helm
if ! check_command helm; then
    log INFO "Установка Helm..."

    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh

    log SUCCESS "Helm установлен"
else
    log INFO "Helm уже установлен: $(helm version --short)"
fi

# Настройка автодополнения
log INFO "Настройка автодополнения..."

# kubectl
if [ -n "$BASH_VERSION" ]; then
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
elif [ -n "$ZSH_VERSION" ]; then
    echo 'source <(kubectl completion zsh)' >> ~/.zshrc
    echo 'alias k=kubectl' >> ~/.zshrc
fi

# helm
if [ -n "$BASH_VERSION" ]; then
    echo 'source <(helm completion bash)' >> ~/.bashrc
elif [ -n "$ZSH_VERSION" ]; then
    echo 'source <(helm completion zsh)' >> ~/.zshrc
fi

log SUCCESS "Kubernetes инструменты установлены"