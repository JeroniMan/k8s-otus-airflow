# scripts/setup/configure-environment.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log STEP "Настройка окружения"

# Создание .env из примера если не существует
if [ ! -f "${PROJECT_ROOT}/.env" ]; then
    if [ -f "${PROJECT_ROOT}/.env.example" ]; then
        log INFO "Создание .env из .env.example"
        cp "${PROJECT_ROOT}/.env.example" "${PROJECT_ROOT}/.env"
        log WARN "Обязательно отредактируйте .env файл!"
    else
        log ERROR "Файл .env.example не найден"
        exit 1
    fi
else
    log INFO "Файл .env уже существует"
fi

# Создание SSH ключей если не существуют
load_env || exit 1

if [ ! -f "${SSH_PUBLIC_KEY_PATH}" ] || [ ! -f "${SSH_PRIVATE_KEY_PATH}" ]; then
    log INFO "Генерация SSH ключей..."
    ssh-keygen -t rsa -b 4096 -f "${SSH_PRIVATE_KEY_PATH}" -N "" -q
    log SUCCESS "SSH ключи созданы"
else
    log INFO "SSH ключи уже существуют"
fi

# Права на SSH ключ
chmod 600 "${SSH_PRIVATE_KEY_PATH}"
chmod 644 "${SSH_PUBLIC_KEY_PATH}"

# Создание необходимых директорий
log INFO "Создание директорий..."
mkdir -p "${LOG_DIR}"
mkdir -p "${PROJECT_ROOT}/tmp"
mkdir -p "${PROJECT_ROOT}/backups"

# Проверка Yandex Cloud
if check_command yc; then
    if ! yc config list &> /dev/null; then
        log WARN "Yandex Cloud CLI не настроен"
        log INFO "Запустите: yc init"
    else
        log SUCCESS "Yandex Cloud CLI настроен"
    fi
fi

log SUCCESS "Окружение настроено"