#!/bin/bash
# scripts/backup-configs.sh
# Создание резервной копии конфигураций

set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Директория для бэкапов
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "================================================"
echo "     Создание резервной копии конфигураций"
echo "================================================"
echo ""
echo "Backup directory: $BACKUP_DIR"
echo ""

# Функция для безопасного копирования
safe_copy() {
    local src=$1
    local dst=$2
    if [ -e "$src" ]; then
        cp -r "$src" "$dst"
        echo -e "${GREEN}[✓]${NC} Скопировано: $src"
    else
        echo -e "${YELLOW}[!]${NC} Не найдено: $src"
    fi
}

# Terraform state
echo "Backup Terraform state..."
if [ -d "infrastructure/terraform" ]; then
    cd infrastructure/terraform
    if [ -f "terraform.tfstate" ]; then
        cp terraform.tfstate "../../$BACKUP_DIR/"
    fi
    terraform output -json > "../../$BACKUP_DIR/terraform-outputs.json" 2>/dev/null || true
    cd ../..
fi

# Kubeconfig
echo ""
echo "Backup Kubernetes configs..."
safe_copy "kubeconfig" "$BACKUP_DIR/"

# Environment variables
safe_copy ".env" "$BACKUP_DIR/"

# ArgoCD password
safe_copy "argocd-password.txt" "$BACKUP_DIR/"

# Kubernetes resources
if [ -f "kubeconfig" ]; then
    export KUBECONFIG=$PWD/kubeconfig

    echo ""
    echo "Backup Kubernetes resources..."

    # All resources
    kubectl get all,cm,secret,pvc,pv,ing --all-namespaces -o yaml > "$BACKUP_DIR/k8s-all-resources.yaml" 2>/dev/null || true

    # ArgoCD applications
    kubectl get applications -n argocd -o yaml > "$BACKUP_DIR/argocd-applications.yaml" 2>/dev/null || true

    # Specific namespaces
    for ns in airflow monitoring argocd; do
        kubectl get all,cm,secret,pvc -n $ns -o yaml > "$BACKUP_DIR/k8s-$ns-namespace.yaml" 2>/dev/null || true
    done
fi

# Custom configurations
echo ""
echo "Backup custom configurations..."
safe_copy "infrastructure/terraform/terraform.tfvars" "$BACKUP_DIR/"
safe_copy "infrastructure/ansible/inventory/hosts.yml" "$BACKUP_DIR/"

# Git info
echo ""
echo "Saving Git information..."
cat > "$BACKUP_DIR/git-info.txt" << EOF
Repository: $(git config --get remote.origin.url)
Branch: $(git branch --show-current)
Commit: $(git rev-parse HEAD)
Date: $(date)
EOF

# Create restore script
cat > "$BACKUP_DIR/restore-instructions.txt" << 'EOF'
Инструкция по восстановлению
============================

1. Восстановление Terraform state:
   cp terraform.tfstate ../../infrastructure/terraform/

2. Восстановление kubeconfig:
   cp kubeconfig ../../
   export KUBECONFIG=$PWD/../../kubeconfig

3. Восстановление переменных окружения:
   cp .env ../../
   source ../../.env

4. Восстановление паролей:
   cp argocd-password.txt ../../

5. Проверка восстановления:
   cd ../..
   kubectl get nodes
   kubectl get applications -n argocd

Примечание: Этот бэкап содержит конфигурационные файлы и состояние.
Для полного восстановления кластера используйте Terraform и ArgoCD.
EOF

# Archive
echo ""
echo "Creating archive..."
cd backups
tar -czf "$(basename "$BACKUP_DIR").tar.gz" "$(basename "$BACKUP_DIR")"
cd ..

echo ""
echo "================================================"
echo -e "${GREEN}Backup completed successfully!${NC}"
echo "================================================"
echo "Backup location: $BACKUP_DIR"
echo "Archive: backups/$(basename "$BACKUP_DIR").tar.gz"
echo ""
echo "To restore, see: $BACKUP_DIR/restore-instructions.txt"