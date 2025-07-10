#!/bin/bash
# fix-argocd-complete.sh
# Полное исправление проблем с ArgoCD

set -e

echo "=== Исправление проблем с ArgoCD ==="

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 1. Исправляем ArgoCD Project чтобы разрешить все ресурсы
echo -e "${BLUE}Шаг 1: Обновление ArgoCD Project разрешений...${NC}"

kubectl patch appproject production -n argocd --type merge -p '{
  "spec": {
    "clusterResourceWhitelist": [
      {"group": "*", "kind": "*"}
    ],
    "destinations": [
      {"namespace": "*", "server": "https://kubernetes.default.svc"}
    ]
  }
}'

echo -e "${GREEN}✓ Project разрешения обновлены${NC}"

# 2. Устанавливаем Prometheus CRDs если их нет
echo -e "\n${BLUE}Шаг 2: Проверка Prometheus CRDs...${NC}"

if ! kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
    echo "Устанавливаю Prometheus CRDs..."
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml
    echo -e "${GREEN}✓ CRDs установлены${NC}"
else
    echo -e "${GREEN}✓ CRDs уже установлены${NC}"
fi

# 3. Обновляем master IP в NFS provisioner
echo -e "\n${BLUE}Шаг 3: Обновление NFS provisioner с правильным IP...${NC}"

# Получаем IP master ноды
MASTER_IP=$(kubectl get nodes -o wide | grep master | awk '{print $6}')
echo "Master IP: $MASTER_IP"

# Обновляем NFS provisioner если он есть
if kubectl get application nfs-provisioner -n argocd &> /dev/null; then
    # Создаем временный файл с обновленными values
    cat > /tmp/nfs-values.yaml << EOF
nfs:
  server: $MASTER_IP
  path: /srv/nfs/k8s

storageClass:
  name: nfs-client
  defaultClass: true
  archiveOnDelete: true

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi
EOF

    # Патчим приложение
    kubectl patch application nfs-provisioner -n argocd --type merge -p "{
      \"spec\": {
        \"source\": {
          \"helm\": {
            \"values\": \"$(cat /tmp/nfs-values.yaml | sed 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')\"
          }
        }
      }
    }"

    rm /tmp/nfs-values.yaml
    echo -e "${GREEN}✓ NFS provisioner обновлен${NC}"
fi

# 4. Принудительная синхронизация всех приложений
echo -e "\n${BLUE}Шаг 4: Синхронизация приложений...${NC}"

# Сначала синхронизируем core приложения
echo "Синхронизация ingress-nginx..."
kubectl patch application ingress-nginx -n argocd --type merge -p '{"operation":{"sync":{"syncOptions":["CreateNamespace=true"]}}}'

# Ждем немного
sleep 30

# Затем monitoring
echo "Синхронизация prometheus-stack..."
kubectl patch application prometheus-stack -n argocd --type merge -p '{"operation":{"sync":{"syncOptions":["CreateNamespace=true","ServerSideApply=true"]}}}'

echo "Синхронизация loki-stack..."
kubectl patch application loki-stack -n argocd --type merge -p '{"operation":{"sync":{"syncOptions":["CreateNamespace=true"]}}}'

# Ждем установки
sleep 60

# И наконец airflow
echo "Синхронизация airflow..."
kubectl patch application airflow -n argocd --type merge -p '{"operation":{"sync":{"syncOptions":["CreateNamespace=true","ServerSideApply=true"]}}}'

# 5. Проверяем статус
echo -e "\n${BLUE}Шаг 5: Проверка статуса...${NC}"
sleep 30

kubectl get applications -n argocd

echo -e "\n${YELLOW}Проверка подов:${NC}"
kubectl get pods --all-namespaces | grep -E "(airflow|ingress|monitoring)"

echo -e "\n${GREEN}Готово!${NC}"
echo ""
echo "Если приложения все еще не синхронизируются, проверьте:"
echo "1. kubectl describe application <app-name> -n argocd"
echo "2. kubectl logs -n argocd deployment/argocd-repo-server"
echo ""
echo "Для доступа к ArgoCD UI:"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Пароль: $(cat argocd-password.txt 2>/dev/null || echo 'см. argocd-password.txt')"