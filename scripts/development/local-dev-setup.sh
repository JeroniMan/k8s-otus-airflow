# scripts/development/local-dev-setup.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log STEP "Настройка локальной разработки"

# Создание виртуального окружения
log INFO "Создание Python виртуального окружения..."
python3 -m venv "${PROJECT_ROOT}/venv"

# Активация и установка зависимостей
source "${PROJECT_ROOT}/venv/bin/activate"

log INFO "Установка зависимостей..."
pip install --upgrade pip
pip install -r "${PROJECT_ROOT}/airflow/requirements.txt"
pip install apache-airflow==2.8.1

# Создание локальной конфигурации
cat > "${PROJECT_ROOT}/airflow/airflow.cfg" << EOF
[core]
dags_folder = ${PROJECT_ROOT}/airflow/dags
load_examples = False

[webserver]
web_server_port = 8080
EOF

log SUCCESS "Локальное окружение настроено"
log INFO "Активация: source ${PROJECT_ROOT}/venv/bin/activate"
log INFO "Запуск Airflow: airflow standalone"