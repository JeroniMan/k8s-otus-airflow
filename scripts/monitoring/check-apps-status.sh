# scripts/monitoring/check-apps-status.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Проверка статуса приложений"

# Валидация
validate_kubeconfig || exit 1

# ArgoCD Applications
echo -e "\n${GREEN}=== ArgoCD Applications ===${NC}"
kubectl get applications -n argocd

# Airflow
echo -e "\n${GREEN}=== Airflow Status ===${NC}"
kubectl get pods -n airflow
echo ""
kubectl get svc -n airflow

# Monitoring
echo -e "\n${GREEN}=== Monitoring Status ===${NC}"
kubectl get pods -n monitoring | grep -E "(prometheus|grafana|loki)"
echo ""
kubectl get svc -n monitoring | grep -E "(prometheus|grafana|loki)"

# Ingress
echo -e "\n${GREEN}=== Ingress Status ===${NC}"
kubectl get pods -n ingress-nginx
echo ""
kubectl get ingress --all-namespaces

log SUCCESS "Проверка завершена"