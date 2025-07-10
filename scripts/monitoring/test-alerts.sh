# scripts/monitoring/test-alerts.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Тестирование алертов"

# Валидация
validate_kubeconfig || exit 1

# Проверка AlertManager
if kubectl get svc -n monitoring | grep -q alertmanager; then
    log INFO "AlertManager найден"

    # Получение URL AlertManager
    log INFO "AlertManager доступен через port-forward:"
    log INFO "kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093"
else
    log WARN "AlertManager не найден"
fi

# Проверка правил алертов
log INFO "Активные алерты:"
kubectl exec -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0 -- \
    promtool query instant 'ALERTS{alertstate="firing"}' 2>/dev/null || \
    echo "Нет активных алертов или Prometheus недоступен"

log SUCCESS "Проверка завершена"