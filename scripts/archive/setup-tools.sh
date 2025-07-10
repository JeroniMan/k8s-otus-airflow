#!/bin/bash
# scripts/setup-tools.sh
# Автоматическая установка всех необходимых инструментов

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функции для вывода
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# Определение ОС
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/debian_version ]; then
            OS="debian"
        elif [ -f /etc/redhat-release ]; then
            OS="redhat"
        else
            OS="linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        error "Неподдерживаемая ОС: $OSTYPE"
    fi
    success "Определена ОС: $OS"
}

# Установка базовых инструментов
install_base_tools() {
    log "Установка базовых инструментов..."

    if [ "$OS" == "debian" ]; then
        sudo apt update
        sudo apt install -y curl wget git make jq unzip python3 python3-pip
    elif [ "$OS" == "macos" ]; then
        if ! command -v brew &> /dev/null; then
            warning "Homebrew не установлен. Устанавливаем..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install curl wget git make jq python3
    fi

    success "Базовые инструменты установлены"
}

# Установка Terraform
install_terraform() {
    if command -v terraform &> /dev/null; then
        warning "Terraform уже установлен: $(terraform version | head -1)"
        return
    fi

    log "Установка Terraform..."

    TF_VERSION="1.6.0"
    if [ "$OS" == "macos" ]; then
        ARCH="darwin_amd64"
        if [[ $(uname -m) == "arm64" ]]; then
            ARCH="darwin_arm64"
        fi
    else
        ARCH="linux_amd64"
    fi

    cd /tmp
    wget -q "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${ARCH}.zip"
    unzip -q "terraform_${TF_VERSION}_${ARCH}.zip"
    sudo mv terraform /usr/local/bin/
    rm "terraform_${TF_VERSION}_${ARCH}.zip"

    success "Terraform установлен: $(terraform version | head -1)"
}

# Установка Ansible
install_ansible() {
    if command -v ansible &> /dev/null; then
        warning "Ansible уже установлен: $(ansible --version | head -1)"
        return
    fi

    log "Установка Ansible..."

    pip3 install --user ansible==8.5.0

    # Добавляем в PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
        export PATH="$HOME/.local/bin:$PATH"
    fi

    success "Ansible установлен"
}

# Установка kubectl
install_kubectl() {
    if command -v kubectl &> /dev/null; then
        warning "kubectl уже установлен: $(kubectl version --client --short 2>/dev/null)"
        return
    fi

    log "Установка kubectl..."

    K8S_VERSION="v1.28.0"
    if [ "$OS" == "macos" ]; then
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

    success "kubectl установлен"
}

# Установка Helm
install_helm() {
    if command -v helm &> /dev/null; then
        warning "Helm уже установлен: $(helm version --short)"
        return
    fi

    log "Установка Helm..."

    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh

    success "Helm установлен"
}

# Установка Yandex Cloud CLI
install_yc() {
    if command -v yc &> /dev/null; then
        warning "Yandex Cloud CLI уже установлен: $(yc version)"
        return
    fi

    log "Установка Yandex Cloud CLI..."

    curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash

    # Добавляем в PATH
    if [ -d "$HOME/yandex-cloud/bin" ]; then
        if [[ ":$PATH:" != *":$HOME/yandex-cloud/bin:"* ]]; then
            echo 'export PATH="$HOME/yandex-cloud/bin:$PATH"' >> ~/.bashrc
            echo 'export PATH="$HOME/yandex-cloud/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
            export PATH="$HOME/yandex-cloud/bin:$PATH"
        fi
    fi

    success "Yandex Cloud CLI установлен"
}

# Проверка всех инструментов
verify_installation() {
    log "Проверка установленных инструментов..."

    local all_ok=true

    for tool in terraform ansible kubectl helm yc git make jq; do
        if command -v $tool &> /dev/null; then
            success "$tool: OK"
        else
            error "$tool: НЕ НАЙДЕН"
            all_ok=false
        fi
    done

    if [ "$all_ok" = true ]; then
        success "Все инструменты успешно установлены!"
    else
        error "Некоторые инструменты не установлены"
    fi
}

# Создание структуры проекта
setup_project_structure() {
    log "Настройка проекта..."

    # SSH ключи
    if [ ! -f ~/.ssh/k8s-airflow ]; then
        log "Генерация SSH ключей..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-airflow -N ""
        success "SSH ключи созданы"
    else
        warning "SSH ключи уже существуют"
    fi

    # Создаем директорию для логов
    mkdir -p logs

    success "Структура проекта готова"
}

# Основная функция
main() {
    echo "================================================"
    echo "     Установка инструментов для проекта"
    echo "================================================"
    echo ""

    detect_os
    install_base_tools
    install_terraform
    install_ansible
    install_kubectl
    install_helm
    install_yc

    echo ""
    verify_installation

    setup_project_structure

    echo ""
    echo "================================================"
    echo -e "${GREEN}     Установка завершена успешно!${NC}"
    echo "================================================"
    echo ""
    echo "Следующие шаги:"
    echo "1. Перезапустите терминал или выполните:"
    echo "   source ~/.bashrc"
    echo ""
    echo "2. Настройте Yandex Cloud:"
    echo "   yc init"
    echo ""
    echo "3. Запустите развертывание:"
    echo "   make deploy-all"
}

# Запуск
main "$@"