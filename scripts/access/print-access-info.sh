# scripts/access/print-access-info.sh
#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validation.sh"

log STEP "Информация о доступе к сервисам"

# Загрузка окружения
load_env || true

# Получение IP адресов
if [ -z "${LB_IP}" ] && [ -f "${PROJECT_ROOT}/terraform-outputs.json" ]; then
    LB_IP=$(jq -r '.load_balancer_ip.value' "${PROJECT_ROOT}/terraform-outputs.json" 2>/dev/null || echo "N/A")
    MASTER_IP=$(jq -r '.master_ips.value["master-0"].public_ip' "${PROJECT_ROOT}/terraform-outputs.json" 2>/dev/null || echo "N/A")
fi

echo ""
echo "============================================================"
echo "                  ИНФОРМАЦИЯ О ДОСТУПЕ"
echo "============================================================"
echo ""
echo -e "${GREEN}Load Balancer IP:${NC} ${LB_IP}"
echo -e "${GREEN}Master Node IP:${NC} ${MASTER_IP}"
echo ""
echo "============================================================"
echo -e "${GREEN}📊 Apache Airflow${NC}"
echo "============================================================"
echo "External URL: http://${LB_IP}:32080"
echo "Local access: make port-forward-airflow"
echo "Username: admin"
echo "Password: admin"
echo ""
echo "============================================================"
echo -e "${GREEN}📈 Grafana${NC}"
echo "============================================================"
echo "External URL: http://${LB_IP}:32080/grafana"
echo "Local access: make port-forward-grafana"
echo "Username: admin"
echo "Password: changeme123"
echo ""
echo "============================================================"
echo -e "${GREEN}🔄 ArgoCD${NC}"
echo "============================================================"
echo "Local access only: make port-forward-argocd"
echo "URL: https://localhost:8080"
echo "Username: admin"
echo "Password: $(cat ${PROJECT_ROOT}/argocd-password.txt 2>/dev/null || echo 'See argocd-password.txt')"
echo ""
echo "============================================================"
echo -e "${GREEN}🔧 Kubernetes${NC}"
echo "============================================================"
echo "Kubeconfig: export KUBECONFIG=${PROJECT_ROOT}/kubeconfig"
echo "SSH to master: ssh -i ${SSH_PRIVATE_KEY_PATH} ubuntu@${MASTER_IP}"
echo ""
echo "============================================================"

log SUCCESS "Используйте команды выше для доступа к сервисам"