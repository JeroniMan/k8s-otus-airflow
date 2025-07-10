# scripts/setup/install-yc-cli.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log STEP "Установка Yandex Cloud CLI"

if check_command yc; then
    log INFO "Yandex Cloud CLI уже установлен: $(yc version)"
    exit 0
fi

# Установка
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash

# Добавление в PATH
if [ -d "$HOME/yandex-cloud/bin" ]; then
    if [[ ":$PATH:" != *":$HOME/yandex-cloud/bin:"* ]]; then
        echo 'export PATH="$HOME/yandex-cloud/bin:$PATH"' >> ~/.bashrc
        echo 'export PATH="$HOME/yandex-cloud/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
        export PATH="$HOME/yandex-cloud/bin:$PATH"
    fi
fi

# Проверка установки
if yc version &> /dev/null; then
    log SUCCESS "Yandex Cloud CLI установлен: $(yc version)"
else
    log ERROR "Ошибка установки Yandex Cloud CLI"
    exit 1
fi

log INFO "Для настройки выполните: yc init"