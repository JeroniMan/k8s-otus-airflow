# scripts/kubernetes/create-secrets.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Создание секретов Kubernetes"

# Валидация
validate_kubeconfig || exit 1

# Создание namespace если нужно
create_namespace airflow

# Airflow Fernet Key
log INFO "Создание Airflow Fernet Key..."
if kubectl get secret airflow-fernet-key -n airflow &> /dev/null; then
    log WARN "Secret airflow-fernet-key уже существует"
else
    FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
    kubectl create secret generic airflow-fernet-key \
        --from-literal=fernet-key="${FERNET_KEY}" \
        -n airflow
    log SUCCESS "Secret airflow-fernet-key создан"
fi

# Flower Basic Auth
log INFO "Создание Flower Basic Auth..."
if kubectl get secret flower-auth -n airflow &> /dev/null; then
    log WARN "Secret flower-auth уже существует"
else
    # admin:admin в htpasswd формате
    FLOWER_AUTH='admin:$apr1$HQkFCpHM$.LrC/.7oJ6bqHFn2QPkPH1.'
    kubectl create secret generic flower-auth \
        --from-literal=auth="${FLOWER_AUTH}" \
        -n airflow
    log SUCCESS "Secret flower-auth создан"
fi

log SUCCESS "Все секреты созданы"