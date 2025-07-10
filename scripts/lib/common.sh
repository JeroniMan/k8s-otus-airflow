# scripts/lib/common.sh
#!/bin/bash

# Цвета для вывода
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export NC='\033[0m'

# Базовые пути
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export TERRAFORM_DIR="${PROJECT_ROOT}/infrastructure/terraform"
export ANSIBLE_DIR="${PROJECT_ROOT}/infrastructure/ansible"
export K8S_DIR="${PROJECT_ROOT}/kubernetes"
export LOG_DIR="${PROJECT_ROOT}/logs"

# Создаем директорию для логов
mkdir -p "${LOG_DIR}"

# Логирование
log() {
   local level=$1
   shift
   local message="$@"
   local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
   local log_file="${LOG_DIR}/deployment-$(date +%Y%m%d).log"

   case $level in
       INFO)    echo -e "${BLUE}[${timestamp}] [INFO]${NC} ${message}" | tee -a "$log_file" ;;
       SUCCESS) echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} ${message}" | tee -a "$log_file" ;;
       WARN)    echo -e "${YELLOW}[${timestamp}] [WARN]${NC} ${message}" | tee -a "$log_file" ;;
       ERROR)   echo -e "${RED}[${timestamp}] [ERROR]${NC} ${message}" | tee -a "$log_file" ;;
       STEP)    echo -e "${PURPLE}[${timestamp}] [STEP]${NC} ${message}" | tee -a "$log_file" ;;
   esac
}

# Проверка команды
check_command() {
   if ! command -v "$1" &> /dev/null; then
       return 1
   fi
   return 0
}

# Загрузка .env файла
load_env() {
   if [ -f "${PROJECT_ROOT}/.env" ]; then
       set -a
       source "${PROJECT_ROOT}/.env"
       set +a
       return 0
   else
       log ERROR "Файл .env не найден в ${PROJECT_ROOT}"
       return 1
   fi
}

# Retry функция
retry_command() {
   local max_attempts=$1
   local delay=$2
   local command="${@:3}"
   local attempt=1

   while [ $attempt -le $max_attempts ]; do
       if eval "$command"; then
           return 0
       fi

       if [ $attempt -lt $max_attempts ]; then
           log WARN "Попытка $attempt из $max_attempts не удалась, повтор через ${delay} секунд..."
           sleep $delay
       fi
       ((attempt++))
   done

   log ERROR "Команда не выполнена после $max_attempts попыток"
   return 1
}

# Проверка что мы в корне проекта
ensure_project_root() {
   if [ ! -f "${PROJECT_ROOT}/Makefile" ]; then
       log ERROR "Скрипт должен быть запущен из корня проекта"
       exit 1
   fi
}

# Создание временной директории
create_temp_dir() {
   mktemp -d "${PROJECT_ROOT}/tmp.XXXXXX"
}

# Очистка при выходе
cleanup_on_exit() {
   local exit_code=$?
   if [ $exit_code -ne 0 ]; then
       log WARN "Скрипт завершился с ошибкой: $exit_code"
   fi
}

# Установка trap
trap cleanup_on_exit EXIT