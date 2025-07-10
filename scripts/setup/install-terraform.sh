# scripts/setup/install-terraform.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

TF_VERSION="1.6.0"

log STEP "Установка Terraform ${TF_VERSION}"

if check_command terraform; then
    current_version=$(terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    log WARN "Terraform уже установлен: ${current_version}"

    if [ "${current_version}" != "${TF_VERSION}" ]; then
        log INFO "Обновление до версии ${TF_VERSION}"
    else
        log SUCCESS "Нужная версия уже установлена"
        exit 0
    fi
fi

# Определение архитектуры
if [[ "$OSTYPE" == "darwin"* ]]; then
    ARCH="darwin_amd64"
    if [[ $(uname -m) == "arm64" ]]; then
        ARCH="darwin_arm64"
    fi
else
    ARCH="linux_amd64"
fi

# Скачивание и установка
cd /tmp
wget -q "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${ARCH}.zip"
unzip -q "terraform_${TF_VERSION}_${ARCH}.zip"
sudo mv terraform /usr/local/bin/
rm "terraform_${TF_VERSION}_${ARCH}.zip"

# Проверка установки
if terraform version &> /dev/null; then
    log SUCCESS "Terraform установлен: $(terraform version | head -1)"
else
    log ERROR "Ошибка установки Terraform"
    exit 1
fi