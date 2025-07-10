# scripts/access/get-passwords.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/kubernetes.sh"

log STEP "Получение паролей"

echo -e "\n${GREEN}=== Пароли доступа ===${NC}\n"

# ArgoCD
if [ -f "${PROJECT_ROOT}/argocd-password.txt" ]; then
   echo "ArgoCD admin password: $(cat ${PROJECT_ROOT}/argocd-password.txt)"
elif validate_kubeconfig; then
   ARGOCD_PASS=$(get_secret_value argocd argocd-initial-admin-secret password 2>/dev/null || echo "N/A")
   echo "ArgoCD admin password: ${ARGOCD_PASS}"
fi

# Grafana
echo "Grafana admin password: changeme123 (default)"

# Airflow
echo "Airflow admin password: admin (default)"

# Flower
echo "Flower username: admin"
echo "Flower password: admin"

# PostgreSQL (Airflow)
if validate_kubeconfig; then
   PG_PASS=$(kubectl get secret airflow-postgresql -n airflow -o jsonpath='{.data.postgresql-password}' 2>/dev/null | base64 -d || echo "airflow")
   echo "PostgreSQL password: ${PG_PASS}"
fi

# Redis (Airflow)
if validate_kubeconfig; then
   REDIS_PASS=$(kubectl get secret airflow-redis -n airflow -o jsonpath='{.data.redis-password}' 2>/dev/null | base64 -d || echo "airflow")
   echo "Redis password: ${REDIS_PASS}"
fi

echo -e "\n${YELLOW}Примечание: Рекомендуется изменить пароли по умолчанию${NC}"

log SUCCESS "Пароли получены"