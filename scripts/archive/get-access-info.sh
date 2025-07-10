#!/bin/bash
# scripts/get-access-info.sh
# Показать информацию о доступе к сервисам

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Проверка наличия .env
if [ -f .env ]; then
    source .env
else
    echo -e "${YELLOW}[!]${NC} Файл .env не найден. Получаю информацию из Terraform..."

    # Получаем из Terraform
    cd infrastructure/terraform
    export LB_IP=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "N/A")
    export MASTER_IP=$(terraform output -json master_ips 2>/dev/null | jq -r '.["master-0"].public_ip' || echo "N/A")
    cd ../..
fi

# Получение пароля ArgoCD
get_argocd_password() {
    if [ -f argocd-password.txt ]; then
        cat argocd-password.txt
    elif [ -f kubeconfig ]; then
        export KUBECONFIG=$PWD/kubeconfig
        kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "N/A"
    else
        echo "N/A"
    fi
}

ARGOCD_PASSWORD=$(get_argocd_password)

# Вывод информации
clear
echo "================================================"
echo -e "${GREEN}     Информация о доступе к сервисам${NC}"
echo "================================================"
echo ""
echo -e "${BLUE}Load Balancer IP:${NC} $LB_IP"
echo -e "${BLUE}Master Node IP:${NC} $MASTER_IP"
echo ""
echo "================================================"
echo -e "${GREEN}📊 Apache Airflow${NC}"
echo "================================================"
echo "URL: http://$LB_IP:32080"
echo "Username: admin"
echo "Password: admin"
echo ""
echo "Local access:"
echo "  kubectl port-forward svc/airflow-webserver -n airflow 8080:8080"
echo "  http://localhost:8080"
echo ""
echo "================================================"
echo -e "${GREEN}📈 Grafana${NC}"
echo "================================================"
echo "URL: http://$LB_IP:32080/grafana"
echo "Username: admin"
echo "Password: changeme123"
echo ""
echo "Local access:"
echo "  kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80"
echo "  http://localhost:3000"
echo ""
echo "================================================"
echo -e "${GREEN}🔄 ArgoCD${NC}"
echo "================================================"
echo "Local access only:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  https://localhost:8080"
echo ""
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
echo ""
echo "================================================"
echo -e "${GREEN}🔍 Prometheus${NC}"
echo "================================================"
echo "Local access only:"
echo "  kubectl port-forward svc/prometheus-stack-kube-prom-prometheus -n monitoring 9090:9090"
echo "  http://localhost:9090"
echo ""
echo "================================================"
echo -e "${GREEN}🔧 Kubernetes${NC}"
echo "================================================"
echo "Kubeconfig: export KUBECONFIG=$PWD/kubeconfig"
echo ""
echo "SSH to master:"
echo "  ssh -i ~/.ssh/k8s-airflow ubuntu@$MASTER_IP"
echo ""
echo "================================================"
echo -e "${GREEN}📚 Полезные команды${NC}"
echo "================================================"
echo "# Статус кластера"
echo "kubectl get nodes"
echo "kubectl get pods --all-namespaces"
echo ""
echo "# Логи Airflow"
echo "kubectl logs -n airflow -l component=scheduler --tail=100"
echo ""
echo "# Статус ArgoCD приложений"
echo "kubectl get applications -n argocd"
echo ""
echo "# Открыть все сервисы локально"
echo "make port-forward-airflow    # В отдельном терминале"
echo "make port-forward-grafana    # В отдельном терминале"
echo "make port-forward-argocd     # В отдельном терминале"
echo ""
echo "================================================"