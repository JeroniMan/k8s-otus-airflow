# scripts/development/test-dag.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log STEP "Тестирование DAG"

DAG_ID=${1:-hello_world}
TASK_ID=${2:-hello_task}
EXECUTION_DATE=${3:-$(date -I)}

log INFO "Тестирование DAG: ${DAG_ID}, Task: ${TASK_ID}"

# Локальная проверка синтаксиса
if [ -f "${PROJECT_ROOT}/airflow/dags/${DAG_ID}_dag.py" ]; then
    log INFO "Проверка синтаксиса..."
    python3 "${PROJECT_ROOT}/airflow/dags/${DAG_ID}_dag.py"
fi

# Если есть kubeconfig, можно выполнить в кластере
if [ -f "${PROJECT_ROOT}/kubeconfig" ]; then
    export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

    log INFO "Запуск теста в Airflow..."
    kubectl exec -n airflow deployment/airflow-scheduler -- \
        airflow dags test "${DAG_ID}" "${EXECUTION_DATE}"
fi

log SUCCESS "Тест завершен"