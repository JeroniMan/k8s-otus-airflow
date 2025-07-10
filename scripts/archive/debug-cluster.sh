#!/bin/bash
# scripts/debug-cluster.sh
# Отладочная информация о кластере

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Проверка kubeconfig
if [ ! -f kubeconfig ]; then
    echo -e "${RED}[✗]${NC} kubeconfig не найден. Выполните: make get-kubeconfig"
    exit 1
fi

export KUBECONFIG=$PWD/kubeconfig

echo "================================================"
echo -e "${BLUE}     Отладочная информация о кластере${NC}"
echo "================================================"
echo ""

# Nodes
echo -e "${GREEN}=== Nodes ===${NC}"
kubectl get nodes -o wide
echo ""

# System Pods
echo -e "${GREEN}=== System Pods ===${NC}"
kubectl get pods -n kube-system
echo ""

# All Namespaces
echo -e "${GREEN}=== All Namespaces ===${NC}"
kubectl get namespaces
echo ""

# Pods by Namespace
echo -e "${GREEN}=== Pods by Namespace ===${NC}"
for ns in airflow monitoring argocd ingress-nginx; do
    echo -e "${YELLOW}Namespace: $ns${NC}"
    kubectl get pods -n $ns 2>/dev/null || echo "  Namespace не найден"
    echo ""
done

# Services
echo -e "${GREEN}=== Services ===${NC}"
kubectl get svc --all-namespaces
echo ""

# PVCs
echo -e "${GREEN}=== Persistent Volume Claims ===${NC}"
kubectl get pvc --all-namespaces
echo ""

# ArgoCD Applications
echo -e "${GREEN}=== ArgoCD Applications ===${NC}"
kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD не установлен"
echo ""

# Resource Usage
echo -e "${GREEN}=== Resource Usage ===${NC}"
echo "Top Nodes:"
kubectl top nodes 2>/dev/null || echo "Metrics не доступны"
echo ""
echo "Top Pods:"
kubectl top pods --all-namespaces | head -20 2>/dev/null || echo "Metrics не доступны"
echo ""

# Recent Events
echo -e "${GREEN}=== Recent Events (Warnings/Errors) ===${NC}"
kubectl get events --all-namespaces --field-selector type!=Normal --sort-by='.lastTimestamp' | tail -20
echo ""

# Failed Pods
echo -e "${GREEN}=== Failed/Pending Pods ===${NC}"
kubectl get pods --all-namespaces --field-selector='status.phase!=Running,status.phase!=Succeeded' 2>/dev/null
echo ""

# Logs from problem pods
echo -e "${GREEN}=== Logs from Problem Pods ===${NC}"
problem_pods=$(kubectl get pods --all-namespaces --field-selector='status.phase!=Running,status.phase!=Succeeded' -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"')
if [ ! -z "$problem_pods" ]; then
    echo "$problem_pods" | while read ns pod; do
        echo -e "${YELLOW}Logs for $ns/$pod:${NC}"
        kubectl logs -n $ns $pod --tail=10 2>/dev/null || kubectl logs -n $ns $pod --previous --tail=10 2>/dev/null || echo "  No logs available"
        echo ""
    done
else
    echo "No problem pods found"
fi

echo "================================================"