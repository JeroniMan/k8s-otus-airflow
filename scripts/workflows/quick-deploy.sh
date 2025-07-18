#!/bin/bash
# scripts/workflows/quick-deploy.sh

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

step "БЫСТРОЕ РАЗВЕРТЫВАНИЕ"

# Проверка .env
if [ ! -f "${PROJECT_ROOT}/.env" ]; then
    error ".env файл не найден!"
    info "Скопируйте .env.example в .env и заполните переменные"
    exit 1
fi

# Загрузка переменных
load_env || exit 1

# Проверка обязательных переменных
REQUIRED_VARS=(
    "YC_CLOUD_ID"
    "YC_FOLDER_ID"
    "SSH_PUBLIC_KEY_PATH"
    "SSH_PRIVATE_KEY_PATH"
    "TF_STATE_BUCKET"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        error "$var не установлена в .env"
        exit 1
    fi
done

# Автоматическое создание SSH ключей если их нет
SSH_KEY_PATH="${SSH_PRIVATE_KEY_PATH%.key}"
SSH_KEY_PATH="${SSH_KEY_PATH%.pem}"

if [ ! -f "$SSH_PUBLIC_KEY_PATH" ] || [ ! -f "$SSH_PRIVATE_KEY_PATH" ]; then
    info "Создание SSH ключей..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""

    # Обновляем пути в .env если нужно
    if [ -f "${SSH_KEY_PATH}.pub" ]; then
        sed -i.bak "s|^export SSH_PUBLIC_KEY_PATH=.*|export SSH_PUBLIC_KEY_PATH=\"${SSH_KEY_PATH}.pub\"|" "${PROJECT_ROOT}/.env"
    fi
    if [ -f "${SSH_KEY_PATH}" ]; then
        sed -i.bak "s|^export SSH_PRIVATE_KEY_PATH=.*|export SSH_PRIVATE_KEY_PATH=\"${SSH_KEY_PATH}\"|" "${PROJECT_ROOT}/.env"
    fi

    # Перезагружаем env
    load_env
fi

# Запуск полного развертывания
info "Запуск полного развертывания..."
"${SCRIPT_DIR}/full-deploy.sh"