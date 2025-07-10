# scripts/lib/validation.sh
#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Проверка обязательных переменных окружения
validate_env_vars() {
    local required_vars=(
        "YC_CLOUD_ID"
        "YC_FOLDER_ID"
        "YC_SERVICE_ACCOUNT_KEY_FILE"
        "SSH_PUBLIC_KEY_PATH"
        "SSH_PRIVATE_KEY_PATH"
    )

    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        log ERROR "Отсутствуют обязательные переменные: ${missing_vars[*]}"
        log INFO "Проверьте файл .env"
        return 1
    fi

    return 0
}

# Проверка установленных инструментов
validate_tools() {
    local tools=("$@")
    local missing_tools=()

    for tool in "${tools[@]}"; do
        if ! check_command "$tool"; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log ERROR "Не установлены инструменты: ${missing_tools[*]}"
        log INFO "Запустите: make setup-tools"
        return 1
    fi

    return 0
}

# Проверка SSH ключей
validate_ssh_keys() {
    if [ ! -f "${SSH_PUBLIC_KEY_PATH}" ]; then
        log ERROR "SSH публичный ключ не найден: ${SSH_PUBLIC_KEY_PATH}"
        return 1
    fi

    if [ ! -f "${SSH_PRIVATE_KEY_PATH}" ]; then
        log ERROR "SSH приватный ключ не найден: ${SSH_PRIVATE_KEY_PATH}"
        return 1
    fi

    # Проверка прав на приватный ключ
    local perms=$(stat -c "%a" "${SSH_PRIVATE_KEY_PATH}" 2>/dev/null || stat -f "%OLp" "${SSH_PRIVATE_KEY_PATH}")
    if [ "$perms" != "600" ]; then
        log WARN "Исправляю права на SSH ключ"
        chmod 600 "${SSH_PRIVATE_KEY_PATH}"
    fi

    return 0
}

# Проверка Yandex Cloud конфигурации
validate_yc_config() {
    if ! yc config list &> /dev/null; then
        log ERROR "Yandex Cloud CLI не настроен"
        log INFO "Запустите: yc init"
        return 1
    fi

    if [ ! -f "${YC_SERVICE_ACCOUNT_KEY_FILE}" ]; then
        log ERROR "Service account key не найден: ${YC_SERVICE_ACCOUNT_KEY_FILE}"
        return 1
    fi

    return 0
}

# Проверка Terraform state
validate_terraform_state() {
    if [ ! -d "${TERRAFORM_DIR}/.terraform" ]; then
        log WARN "Terraform не инициализирован"
        return 1
    fi

    return 0
}

# Проверка kubeconfig
validate_kubeconfig() {
    if [ ! -f "${PROJECT_ROOT}/kubeconfig" ]; then
        log WARN "Kubeconfig не найден"
        return 1
    fi

    export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"
    if ! kubectl cluster-info &> /dev/null; then
        log ERROR "Не могу подключиться к кластеру"
        return 1
    fi

    return 0
}