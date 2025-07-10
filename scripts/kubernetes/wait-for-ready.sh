# scripts/kubernetes/wait-for-ready.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Ожидание готовности приложений"

# Валидация
validate_kubeconfig || exit 1

# Функция проверки приложения ArgoCD
check_argocd_app() {
    local app_name=$1
    local status=$(kubectl get application "${app_name}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    local sync=$(kubectl get application "${app_name}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

    if [ "$status" == "Healthy" ] && [ "$sync" == "Synced" ]; then
        return 0
    else
        return 1
    fi
}

# Список приложений для проверки
apps=(
    "ingress-nginx"
    "prometheus-stack"
    "loki-stack"
    "airflow"
)

# Проверка каждого приложения
for app in "${apps[@]}"; do
    log INFO "Проверка ${app}..."

    retries=0
    max_retries=30

    while [ $retries -lt $max_retries ]; do
        if check_argocd_app "${app}"; then
            log SUCCESS "${app} готов"
            break
        else
            log INFO "Ожидание ${app}... ($((retries+1))/$max_retries)"
            sleep 20
            ((retries++))
        fi
    done

    if [ $retries -eq $max_retries ]; then
        log WARN "${app} не готов после $max_retries попыток"
    fi
done

# Проверка основных сервисов
log INFO "Проверка сервисов..."

# Airflow
if wait_for_deployment airflow airflow-webserver; then
    log SUCCESS "Airflow webserver готов"
fi

# Grafana
if wait_for_deployment monitoring prometheus-stack-grafana; then
    log SUCCESS "Grafana готова"
fi

# Prometheus
if kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.phase}' | grep -q Running; then
    log SUCCESS "Prometheus готов"
fi

log SUCCESS "Проверка завершена"