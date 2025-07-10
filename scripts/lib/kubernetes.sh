# scripts/lib/kubernetes.sh
#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Ожидание готовности подов
wait_for_pods() {
    local namespace=$1
    local label_selector=$2
    local timeout=${3:-300}

    log INFO "Ожидание готовности подов в namespace ${namespace}..."

    kubectl wait --for=condition=ready pods \
        -n "${namespace}" \
        ${label_selector:+-l "$label_selector"} \
        --timeout="${timeout}s"
}

# Ожидание готовности deployment
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}

    log INFO "Ожидание готовности deployment ${deployment}..."

    kubectl wait --for=condition=available deployment/"${deployment}" \
        -n "${namespace}" \
        --timeout="${timeout}s"
}

# Создание namespace если не существует
create_namespace() {
    local namespace=$1

    kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -
}

# Получение пароля из секрета
get_secret_value() {
    local namespace=$1
    local secret_name=$2
    local key=$3

    kubectl get secret "${secret_name}" -n "${namespace}" \
        -o jsonpath="{.data.${key}}" | base64 -d
}

# Проверка готовности кластера
check_cluster_ready() {
    # Проверка нод
    local nodes_ready=$(kubectl get nodes -o json | \
        jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True")) | .metadata.name' | \
        wc -l)

    local total_nodes=$(kubectl get nodes -o json | jq '.items | length')

    if [ "$nodes_ready" -eq "$total_nodes" ]; then
        log SUCCESS "Все ноды готовы: $nodes_ready/$total_nodes"
        return 0
    else
        log ERROR "Не все ноды готовы: $nodes_ready/$total_nodes"
        return 1
    fi
}

# Port forwarding
create_port_forward() {
    local namespace=$1
    local service=$2
    local local_port=$3
    local remote_port=$4

    log INFO "Port forward: localhost:${local_port} -> ${service}:${remote_port}"
    kubectl port-forward -n "${namespace}" "svc/${service}" "${local_port}:${remote_port}"
}

# Получение external IP сервиса
get_service_ip() {
    local namespace=$1
    local service=$2

    kubectl get service "${service}" -n "${namespace}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

# Применение манифестов из директории
apply_manifests() {
    local directory=$1

    if [ -d "${directory}" ]; then
        log INFO "Применение манифестов из ${directory}"
        kubectl apply -f "${directory}"
    else
        log ERROR "Директория не найдена: ${directory}"
        return 1
    fi
}