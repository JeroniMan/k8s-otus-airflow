#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Access Information"

# Load environment
load_env || exit 1

# Get IPs from Terraform
if [ -f "${PROJECT_ROOT}/infrastructure/terraform/terraform.tfstate" ]; then
    cd "${PROJECT_ROOT}/infrastructure/terraform"
    LB_IP=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "N/A")
    MASTER_IP=$(terraform output -json master_ips 2>/dev/null | jq -r '.["master-0"].public_ip' || echo "N/A")
    cd - > /dev/null
else
    warning "Terraform state not found"
    LB_IP="N/A"
    MASTER_IP="N/A"
fi

# Get ArgoCD password
if [ -f "${PROJECT_ROOT}/argocd-password.txt" ]; then
    ARGOCD_PASSWORD=$(cat "${PROJECT_ROOT}/argocd-password.txt")
else
    ARGOCD_PASSWORD="Check argocd-password.txt"
fi

echo ""
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${PURPLE}                    ACCESS INFORMATION                         ${NC}"
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${CYAN}Infrastructure:${NC}"
echo "  Load Balancer IP: ${LB_IP}"
echo "  Master Node IP:   ${MASTER_IP}"
echo ""

echo -e "${CYAN}Apache Airflow:${NC}"
echo "  URL:      http://${LB_IP}:32080"
echo "  Username: admin"
echo "  Password: admin"
echo ""

echo -e "${CYAN}Grafana:${NC}"
echo "  URL:      http://${LB_IP}:32080/grafana"
echo "  Username: admin"
echo "  Password: ${GRAFANA_ADMIN_PASSWORD}"
echo ""

echo -e "${CYAN}ArgoCD:${NC}"
echo "  Access:   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  URL:      https://localhost:8080"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""

echo -e "${CYAN}Kubernetes:${NC}"
echo "  Config:   export KUBECONFIG=${PROJECT_ROOT}/kubeconfig"
echo "  SSH:      ssh -i ${SSH_PRIVATE_KEY_PATH} ubuntu@${MASTER_IP}"
echo ""

echo -e "${CYAN}Quick commands:${NC}"
echo "  make pf-airflow   # Port-forward Airflow"
echo "  make pf-grafana   # Port-forward Grafana"
echo "  make pf-argocd    # Port-forward ArgoCD"
echo "  make ssh-master   # SSH to master node"
echo "  make status       # Show cluster status"
echo ""