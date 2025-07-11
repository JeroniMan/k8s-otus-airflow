#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Creating Application Secrets"

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Load environment
load_env || exit 1

# Create namespaces first
info "Creating namespaces..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/base/namespaces.yaml"

# Airflow secrets
info "Creating Airflow secrets..."
kubectl create namespace airflow --dry-run=client -o yaml | kubectl apply -f -

# Generate Fernet key if not exists
if [ -z "$AIRFLOW_FERNET_KEY" ]; then
    AIRFLOW_FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
    echo "export AIRFLOW_FERNET_KEY=\"$AIRFLOW_FERNET_KEY\"" >> "${PROJECT_ROOT}/.env"
fi

# Create Airflow secrets
kubectl create secret generic airflow-fernet-key \
    --from-literal=fernet-key="$AIRFLOW_FERNET_KEY" \
    --namespace airflow \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic airflow-webserver-secret \
    --from-literal=webserver-secret-key="$AIRFLOW_WEBSERVER_SECRET_KEY" \
    --namespace airflow \
    --dry-run=client -o yaml | kubectl apply -f -

# Git SSH secret for DAG sync (if using private repo)
if [ -f "$HOME/.ssh/id_rsa" ]; then
    kubectl create secret generic airflow-git-ssh-secret \
        --from-file=gitSshKey="$HOME/.ssh/id_rsa" \
        --namespace airflow \
        --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
fi

# Monitoring secrets
info "Creating monitoring secrets..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Grafana admin password
kubectl create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
    --namespace monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

# Loki S3 credentials
kubectl create secret generic loki-s3-secret \
    --from-literal=access_key_id="$S3_ACCESS_KEY" \
    --from-literal=secret_access_key="$S3_SECRET_KEY" \
    --namespace monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

# Registry credentials (if using private registry)
if [ -n "$REGISTRY_USERNAME" ] && [ -n "$REGISTRY_PASSWORD" ]; then
    kubectl create secret docker-registry regcred \
        --docker-server="$REGISTRY_SERVER" \
        --docker-username="$REGISTRY_USERNAME" \
        --docker-password="$REGISTRY_PASSWORD" \
        --docker-email="$REGISTRY_EMAIL" \
        --namespace airflow \
        --dry-run=client -o yaml | kubectl apply -f -
fi

success "Application secrets created!"

# List secrets
echo ""
info "Created secrets:"
kubectl get secrets -n airflow
kubectl get secrets -n monitoring