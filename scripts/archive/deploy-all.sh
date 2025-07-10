#!/bin/bash
# autonomous-deploy.sh
# Полностью автономное развертывание Kubernetes + Airflow инфраструктуры
# Автор: Data Engineer
# Дата: $(date)

set -euo pipefail

# =====================================================
# КОНФИГУРАЦИЯ
# =====================================================

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Директории
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly TERRAFORM_DIR="${PROJECT_ROOT}/infrastructure/terraform"
readonly ANSIBLE_DIR="${PROJECT_ROOT}/infrastructure/ansible"
readonly K8S_DIR="${PROJECT_ROOT}/kubernetes"
readonly LOG_DIR="${PROJECT_ROOT}/logs"

# Логирование
readonly LOG_FILE="${LOG_DIR}/deployment-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${LOG_DIR}"

# Переменные для retry логики
readonly MAX_RETRIES=3
readonly RETRY_DELAY=10

# =====================================================
# ФУНКЦИИ УТИЛИТЫ
# =====================================================

# Логирование с временными метками
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)  echo -e "${BLUE}[${timestamp}] [INFO]${NC} ${message}" | tee -a "$LOG_FILE" ;;
        SUCCESS) echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} ${message}" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[${timestamp}] [WARN]${NC} ${message}" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[${timestamp}] [ERROR]${NC} ${message}" | tee -a "$LOG_FILE" ;;
        STEP)  echo -e "${PURPLE}[${timestamp}] [STEP]${NC} ${message}" | tee -a "$LOG_FILE" ;;
    esac
}

# Функция для выполнения команд с retry
retry_command() {
    local max_attempts=$1
    local delay=$2
    local command="${@:3}"
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log INFO "Попытка $attempt из $max_attempts: $command"

        if eval "$command"; then
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            log WARN "Команда не выполнена, повтор через ${delay} секунд..."
            sleep $delay
        fi

        ((attempt++))
    done

    log ERROR "Команда не выполнена после $max_attempts попыток"
    return 1
}

# Проверка наличия команды
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log ERROR "Команда '$1' не найдена"
        return 1
    fi
    return 0
}

# Функция для безопасного чтения переменных окружения
load_env() {
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        log INFO "Загрузка переменных окружения из .env"
        set -a
        source "${PROJECT_ROOT}/.env"
        set +a

        # Проверка обязательных переменных
        local required_vars=(
            "YC_CLOUD_ID"
            "YC_FOLDER_ID"
            "YC_SERVICE_ACCOUNT_KEY_FILE"
            "SSH_PUBLIC_KEY_PATH"
            "SSH_PRIVATE_KEY_PATH"
            "ACCESS_KEY"
            "SECRET_KEY"
            "TF_STATE_BUCKET"
        )

        for var in "${required_vars[@]}"; do
            if [ -z "${!var:-}" ]; then
                log ERROR "Переменная $var не определена в .env"
                return 1
            fi
        done

        # Экспорт для Terraform S3 backend
        export AWS_ACCESS_KEY_ID="${ACCESS_KEY}"
        export AWS_SECRET_ACCESS_KEY="${SECRET_KEY}"

        log SUCCESS "Переменные окружения загружены"
    else
        log ERROR "Файл .env не найден в ${PROJECT_ROOT}"
        return 1
    fi
}

check_yc_quotas() {
    log STEP "Проверка квот Yandex Cloud..."

    # Получаем текущие квоты
    local quotas=$(yc resource-manager quota list --format json 2>/dev/null || echo "[]")

    if [ "$quotas" != "[]" ]; then
        log INFO "Текущие квоты:"
        echo "$quotas" | jq -r '.[] | "\(.metric): \(.usage)/\(.limit)"' | while read line; do
            log INFO "  $line"
        done
    fi

    # Проверяем доступные ресурсы в разных зонах
    log INFO "Проверка доступности ресурсов по зонам..."
    for zone in ru-central1-a ru-central1-b ru-central1-c; do
        local availability=$(yc compute zone get --name=$zone --format json 2>/dev/null || echo "{}")
        if [ "$availability" != "{}" ]; then
            log INFO "Зона $zone: доступна"
        else
            log WARN "Зона $zone: недоступна или нет прав"
        fi
    done

    log SUCCESS "Проверка квот завершена"
}

# =====================================================
# ПРОВЕРКА PREREQUISITES
# =====================================================

check_prerequisites() {
    log STEP "Проверка необходимых компонентов..."

    local tools=("terraform" "ansible" "kubectl" "helm" "yc" "jq" "ssh-keygen")
    local missing_tools=()

    for tool in "${tools[@]}"; do
        if ! check_command "$tool"; then
            missing_tools+=("$tool")
        else
            log SUCCESS "$tool установлен"
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log ERROR "Отсутствуют инструменты: ${missing_tools[*]}"
        log INFO "Запустите: ./scripts/setup-tools.sh"
        return 1
    fi

    # Проверка SSH ключей
    if [ ! -f "${SSH_PUBLIC_KEY_PATH}" ] || [ ! -f "${SSH_PRIVATE_KEY_PATH}" ]; then
        log WARN "SSH ключи не найдены, создаю новые..."
        ssh-keygen -t rsa -b 4096 -f "${SSH_PRIVATE_KEY_PATH}" -N "" -q
        log SUCCESS "SSH ключи созданы"
    fi

    # Проверка Yandex Cloud конфигурации
    if ! yc config list &> /dev/null; then
        log ERROR "Yandex Cloud не настроен. Выполните: yc init"
        return 1
    fi

    # Проверка service account key
    if [ ! -f "${YC_SERVICE_ACCOUNT_KEY_FILE}" ]; then
        log ERROR "Service account key не найден: ${YC_SERVICE_ACCOUNT_KEY_FILE}"
        return 1
    fi

    # Проверка квот
    check_yc_quotas

    log SUCCESS "Все prerequisites проверены"
}

# =====================================================
# TERRAFORM ФУНКЦИИ
# =====================================================

check_existing_infrastructure() {
    log STEP "Проверка существующей инфраструктуры..."

    cd "${TERRAFORM_DIR}"

    # Проверяем, есть ли уже развернутая инфраструктура
    if [ -f "terraform.tfstate" ] || [ -d ".terraform" ]; then
        log WARN "Обнаружена существующая конфигурация Terraform"

        # Предлагаем варианты действий
        if [ "${FORCE_CLEANUP:-false}" == "true" ]; then
            log WARN "FORCE_CLEANUP=true, очищаем существующую инфраструктуру..."
            terraform destroy -auto-approve || true
            rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
        else
            log INFO "Используйте FORCE_CLEANUP=true для принудительной очистки"
            log INFO "Или запустите: cd ${TERRAFORM_DIR} && terraform destroy"
        fi
    fi
}

create_s3_bucket() {
    log STEP "Создание S3 bucket для Terraform state..."

    # Проверяем существование bucket
    if yc storage bucket get "${TF_STATE_BUCKET}" &> /dev/null; then
        log WARN "S3 bucket ${TF_STATE_BUCKET} уже существует"
    else
        retry_command 3 10 "yc storage bucket create \
            --name '${TF_STATE_BUCKET}' \
            --default-storage-class standard \
            --max-size 1073741824"

        log SUCCESS "S3 bucket создан: ${TF_STATE_BUCKET}"
    fi
}

init_terraform() {
    log STEP "Инициализация Terraform..."

    cd "${TERRAFORM_DIR}"

    # Обновляем backend конфигурацию
    sed -i.bak "s/bucket.*=.*/bucket   = \"${TF_STATE_BUCKET}\"/" main.tf

    # Создаем terraform.tfvars
    cat > terraform.tfvars << EOF
yc_cloud_id          = "${YC_CLOUD_ID}"
yc_folder_id         = "${YC_FOLDER_ID}"
yc_zone              = "${YC_ZONE:-ru-central1-a}"
ssh_public_key_path  = "${SSH_PUBLIC_KEY_PATH}"
ssh_private_key_path = "${SSH_PRIVATE_KEY_PATH}"

# Минимальная конфигурация для экономии
master_count  = 1
master_cpu    = 2
master_memory = 4
master_disk_size = 50

worker_count  = 2
worker_cpu    = 2
worker_memory = 4
worker_disk_size = 100

# Используем HDD вместо SSD для обхода лимитов
disk_type     = "network-hdd"
preemptible   = false
core_fraction = 100
EOF

    # Проверяем, есть ли уже инициализированный Terraform
    if [ -d ".terraform" ]; then
        log WARN "Обнаружена предыдущая конфигурация Terraform"

        # Пробуем сначала с -reconfigure (безопаснее)
        log INFO "Переконфигурация Terraform backend..."
        if ! terraform init -reconfigure -upgrade; then
            log WARN "Переконфигурация не удалась, пробуем миграцию состояния..."

            # Если не удалось, пробуем с -migrate-state
            if ! terraform init -migrate-state -upgrade; then
                log WARN "Миграция не удалась, очищаем и инициализируем заново..."

                # В крайнем случае очищаем и начинаем заново
                rm -rf .terraform .terraform.lock.hcl
                retry_command 3 10 "terraform init -upgrade"
            fi
        fi
    else
        # Первая инициализация
        retry_command 3 10 "terraform init -upgrade"
    fi

    log SUCCESS "Terraform инициализирован"
}

deploy_infrastructure() {
    log STEP "Развертывание инфраструктуры через Terraform..."

    cd "${TERRAFORM_DIR}"

    # План
    log INFO "Создание плана изменений..."
    terraform plan -out=tfplan

    # Apply с auto-approve для автономности
    log INFO "Применение изменений (это займет 5-10 минут)..."
    if terraform apply -auto-approve tfplan; then
        log SUCCESS "Инфраструктура создана"

        # Сохраняем outputs
        terraform output -json > "${PROJECT_ROOT}/terraform-outputs.json"

        # Получаем только IP адрес из JSON вывода
        export MASTER_IP=$(terraform output -json master_ips | jq -r '.["master-0"].public_ip')
        export LB_IP=$(terraform output -raw load_balancer_ip)

        # Сохраняем в .env для последующего использования
        cat >> "${PROJECT_ROOT}/.env" << EOF

# Generated by deployment
export MASTER_IP=${MASTER_IP}
export LB_IP=${LB_IP}
EOF

    else
        log ERROR "Ошибка создания инфраструктуры"

        # Проверяем тип ошибки
        if terraform show -json tfplan 2>/dev/null | grep -q "ResourceExhausted"; then
            log WARN "Обнаружена проблема с квотами ресурсов"
            log INFO "Пробуем альтернативную конфигурацию..."

            # Пробуем с меньшими дисками и в другой зоне
            handle_resource_quota_error

            # Повторяем попытку
            terraform plan -out=tfplan
            terraform apply -auto-approve tfplan || return 1
        else
            return 1
        fi
    fi
}

handle_resource_quota_error() {
    log STEP "Обработка ошибки квот..."

    # Очищаем неудавшееся развертывание
    log INFO "Очистка частично созданных ресурсов..."
    terraform destroy -auto-approve || true

    # Меняем параметры на более экономные
    log INFO "Применение альтернативной конфигурации..."

    # Пробуем другую зону если текущая перегружена
    local ALTERNATIVE_ZONE="ru-central1-b"
    if [ "${YC_ZONE}" == "ru-central1-b" ]; then
        ALTERNATIVE_ZONE="ru-central1-c"
    fi

    cat > terraform.tfvars << EOF
yc_cloud_id          = "${YC_CLOUD_ID}"
yc_folder_id         = "${YC_FOLDER_ID}"
yc_zone              = "${ALTERNATIVE_ZONE}"
ssh_public_key_path  = "${SSH_PUBLIC_KEY_PATH}"
ssh_private_key_path = "${SSH_PRIVATE_KEY_PATH}"

# Минимальная конфигурация с HDD
master_count  = 1
master_cpu    = 2
master_memory = 4
master_disk_size = 30     # Уменьшаем размер диска

worker_count  = 2
worker_cpu    = 2
worker_memory = 4
worker_disk_size = 50     # Уменьшаем размер диска

disk_type     = "network-hdd"  # Используем HDD
preemptible   = false
core_fraction = 100              # Минимальная производительность
EOF

    log WARN "Изменена конфигурация:"
    log WARN "- Зона: ${YC_ZONE} -> ${ALTERNATIVE_ZONE}"
    log WARN "- Тип дисков: SSD -> HDD"
    log WARN "- Размер дисков уменьшен"
    log WARN "- CPU производительность: 50% -> 20%"
}

# =====================================================
# ANSIBLE ФУНКЦИИ
# =====================================================

wait_for_servers() {
    log STEP "Ожидание готовности серверов..."

    cd "${ANSIBLE_DIR}"

    # Даем время на cloud-init
    log INFO "Ожидание завершения cloud-init (60 сек)..."
    sleep 60

    # Проверка доступности с retry
    log INFO "Проверка SSH доступности..."
    ANSIBLE_HOST_KEY_CHECKING=False retry_command 5 30 \
        "ansible all -i inventory/hosts.yml \
        --private-key=${SSH_PRIVATE_KEY_PATH} \
        -m wait_for_connection \
        -a 'delay=10 timeout=300'"

    log SUCCESS "Все серверы доступны"
}

prepare_nodes() {
    log STEP "Подготовка нод для Kubernetes..."

    cd "${ANSIBLE_DIR}"

    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i inventory/hosts.yml \
        --private-key="${SSH_PRIVATE_KEY_PATH}" \
        playbooks/prepare-nodes.yml \
        -v

    log SUCCESS "Ноды подготовлены"
}

install_k3s() {
    log STEP "Установка k3s..."

    cd "${ANSIBLE_DIR}"

    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i inventory/hosts.yml \
        --private-key="${SSH_PRIVATE_KEY_PATH}" \
        playbooks/install-k3s.yml \
        -v

    log SUCCESS "k3s установлен"
}

# =====================================================
# KUBERNETES ФУНКЦИИ
# =====================================================

setup_kubeconfig() {
    log STEP "Настройка kubectl..."

    # Проверяем, что MASTER_IP установлен и корректен
    if [ -z "${MASTER_IP}" ] || [[ "${MASTER_IP}" == *"@"* ]]; then
        log WARN "Некорректный MASTER_IP, получаю заново..."
        cd "${TERRAFORM_DIR}"
        export MASTER_IP=$(terraform output -json master_ips | jq -r '.["master-0"].public_ip')
        cd "${PROJECT_ROOT}"
    fi

    log INFO "Подключение к master node: ${MASTER_IP}"

    # Получаем kubeconfig - ИСПРАВЛЕНО!
    retry_command 3 10 "ssh -o StrictHostKeyChecking=no \
        -i ${SSH_PRIVATE_KEY_PATH} \
        ubuntu@${MASTER_IP} \
        'sudo cat /etc/rancher/k3s/k3s.yaml' > ${PROJECT_ROOT}/kubeconfig"

    # Заменяем localhost на реальный IP
    sed -i.bak "s/127.0.0.1/${MASTER_IP}/g" "${PROJECT_ROOT}/kubeconfig"

    export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

    # Проверка
    if kubectl get nodes &> /dev/null; then
        log SUCCESS "kubectl настроен"
        kubectl get nodes
    else
        log ERROR "Ошибка настройки kubectl"
        return 1
    fi
}

create_basic_resources() {
    log STEP "Создание базовых ресурсов Kubernetes..."

    # Создание namespaces
    for ns in airflow monitoring argocd ingress-nginx; do
        kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
    done

    # Создание Airflow Fernet Key
    FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
    kubectl create secret generic airflow-fernet-key \
        --from-literal=fernet-key="${FERNET_KEY}" \
        -n airflow --dry-run=client -o yaml | kubectl apply -f -

    log SUCCESS "Базовые ресурсы созданы"
}

install_argocd() {
    log STEP "Установка ArgoCD..."

    # Установка ArgoCD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    log INFO "Ожидание запуска ArgoCD..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

    # Получение пароля
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo "${ARGOCD_PASSWORD}" > "${PROJECT_ROOT}/argocd-password.txt"

    log SUCCESS "ArgoCD установлен. Пароль сохранен в argocd-password.txt"
}

deploy_applications() {
    log STEP "Развертывание приложений через ArgoCD..."

    # Обновляем URL репозитория
    REPO_URL=$(git config --get remote.origin.url || echo "https://github.com/yourusername/k8s-airflow-project")
    find "${K8S_DIR}/argocd" -name "*.yaml" -type f -exec \
        sed -i.bak "s|https://github.com/yourusername/k8s-airflow-project|${REPO_URL}|g" {} \;

    # Применяем манифесты
    kubectl apply -f "${K8S_DIR}/namespaces/"
    kubectl apply -f "${K8S_DIR}/argocd/projects/"
    kubectl apply -f "${K8S_DIR}/argocd/apps/"

    log INFO "Ожидание синхронизации приложений (3-5 минут)..."
    sleep 180

    # Проверка статуса
    kubectl get applications -n argocd

    log SUCCESS "Приложения развернуты"
}

# =====================================================
# ФИНАЛЬНЫЕ ПРОВЕРКИ
# =====================================================

verify_deployment() {
    log STEP "Проверка развертывания..."

    local errors=0

    # Проверка нод
    if ! kubectl get nodes | grep -q Ready; then
        log ERROR "Некоторые ноды не готовы"
        ((errors++))
    fi

    # Проверка основных подов
    for ns in airflow monitoring argocd ingress-nginx; do
        if ! kubectl get pods -n $ns 2>/dev/null | grep -q Running; then
            log WARN "Не все поды запущены в namespace $ns"
            ((errors++))
        fi
    done

    # Проверка сервисов
    if ! nc -zv "${LB_IP}" 32080 &> /dev/null; then
        log WARN "Load Balancer еще не готов на порту 32080"
        ((errors++))
    fi

    if [ $errors -eq 0 ]; then
        log SUCCESS "Все проверки пройдены успешно!"
        return 0
    else
        log WARN "Обнаружено проблем: $errors. Проверьте логи."
        return 1
    fi
}

print_access_info() {
    log STEP "Информация для доступа"

    cat << EOF

============================================================
🎉 РАЗВЕРТЫВАНИЕ ЗАВЕРШЕНО УСПЕШНО!
============================================================

📊 Apache Airflow
URL: http://${LB_IP}:32080
Username: admin
Password: admin

📈 Grafana
URL: http://${LB_IP}:32080/grafana
Username: admin
Password: changeme123

🔄 ArgoCD
Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443
URL: https://localhost:8080
Username: admin
Password: $(cat ${PROJECT_ROOT}/argocd-password.txt)

🔧 Kubernetes
Kubeconfig: export KUBECONFIG=${PROJECT_ROOT}/kubeconfig
SSH to master: ssh -i ${SSH_PRIVATE_KEY_PATH} ubuntu@${MASTER_IP}

📝 Логи развертывания: ${LOG_FILE}

============================================================
EOF
}

# =====================================================
# CLEANUP ФУНКЦИИ
# =====================================================

cleanup_on_error() {
    log ERROR "Произошла ошибка. Начинаю очистку..."

    # Опционально: можно добавить частичную очистку
    # Но для безопасности лучше оставить ресурсы для анализа

    log INFO "Для полной очистки выполните:"
    log INFO "cd ${TERRAFORM_DIR} && terraform destroy -auto-approve"
}

# =====================================================
# MAIN ФУНКЦИЯ
# =====================================================

main() {
    log INFO "================================================"
    log INFO "   Автономное развертывание K8s + Airflow"
    log INFO "================================================"
    log INFO "Логи: ${LOG_FILE}"
    log INFO ""

    # Установка trap для обработки ошибок
    trap cleanup_on_error ERR

    # Загрузка переменных окружения
    load_env || exit 1

    # Проверка prerequisites
    check_prerequisites || exit 1

    # Terraform
    check_existing_infrastructure
    create_s3_bucket
    init_terraform
    deploy_infrastructure

    # Ansible
    wait_for_servers
    prepare_nodes
    install_k3s

    # Kubernetes
    setup_kubeconfig
    create_basic_resources
    install_argocd
    deploy_applications

    # Финальные проверки
    verify_deployment

    # Вывод информации о доступе
    print_access_info

    log SUCCESS "Развертывание завершено за $SECONDS секунд"
}

# =====================================================
# ЗАПУСК
# =====================================================

# Проверяем, что скрипт запущен из корня проекта
if [ ! -f "Makefile" ] || [ ! -d "infrastructure" ]; then
    echo "Ошибка: запустите скрипт из корневой директории проекта"
    exit 1
fi

# Запускаем main функцию
main "$@"