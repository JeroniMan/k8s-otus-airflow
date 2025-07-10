# scripts/monitoring/get-metrics.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Получение метрик"

# Валидация
validate_kubeconfig || exit 1

# CPU и Memory top pods
echo -e "\n${GREEN}=== Top CPU Usage ===${NC}"
kubectl top pods --all-namespaces --sort-by=cpu | head -10

echo -e "\n${GREEN}=== Top Memory Usage ===${NC}"
kubectl top pods --all-namespaces --sort-by=memory | head -10

# Airflow метрики
if kubectl get svc airflow-statsd -n airflow &> /dev/null; then
    echo -e "\n${GREEN}=== Airflow Metrics ===${NC}"
    # Здесь можно добавить запрос к Prometheus для получения Airflow метрик
    echo "Airflow metrics доступны в Grafana"
fi

log SUCCESS "Метрики получены"