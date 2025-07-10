# scripts/setup/install-prerequisites.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log STEP "Установка базовых инструментов"

# Определение ОС
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f /etc/debian_version ]; then
        log INFO "Обнаружена Debian/Ubuntu система"

        # Обновление пакетов
        sudo apt update

        # Установка базовых инструментов
        sudo apt install -y \
            curl \
            wget \
            git \
            make \
            jq \
            unzip \
            python3 \
            python3-pip \
            apt-transport-https \
            ca-certificates \
            gnupg \
            lsb-release \
            software-properties-common

        # Установка Python пакетов
        pip3 install --user cryptography pyyaml

    elif [ -f /etc/redhat-release ]; then
        log INFO "Обнаружена RedHat/CentOS система"

        sudo yum install -y \
            curl \
            wget \
            git \
            make \
            jq \
            unzip \
            python3 \
            python3-pip
    fi

elif [[ "$OSTYPE" == "darwin"* ]]; then
    log INFO "Обнаружена macOS"

    # Проверка Homebrew
    if ! command -v brew &> /dev/null; then
        log INFO "Установка Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Установка через Homebrew
    brew install \
        curl \
        wget \
        git \
        make \
        jq \
        python3

    # Установка Python пакетов
    pip3 install --user cryptography pyyaml
fi

# Добавление ~/.local/bin в PATH если нужно
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
fi

log SUCCESS "Базовые инструменты установлены"