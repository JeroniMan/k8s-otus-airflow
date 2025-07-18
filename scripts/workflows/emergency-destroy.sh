#!/bin/bash
# scripts/workflows/emergency-destroy.sh

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log STEP "ЭКСТРЕННОЕ УДАЛЕНИЕ ИНФРАСТРУКТУРЫ"

warning "Это экстренное удаление - будут игнорироваться ошибки!"
echo ""

# Загрузка env если возможно
load_env 2>/dev/null || warning ".env не найден, используем yc config"

# Получение folder-id
if [ -z "$YC_FOLDER_ID" ]; then
    YC_FOLDER_ID=$(yc config get folder-id 2>/dev/null || echo "")
fi

if [ -z "$YC_FOLDER_ID" ]; then
    error "Не удалось получить YC_FOLDER_ID"
    exit 1
fi

# Удаление всех compute instances
log INFO "Удаление виртуальных машин..."
for instance_id in $(yc compute instance list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    yc compute instance delete --id="$instance_id" --async 2>/dev/null || true
done

# Ждем удаления VM
sleep 30

# Удаление load balancers
log INFO "Удаление load balancers..."
for lb_id in $(yc lb nlb list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    yc lb nlb delete --id="$lb_id" 2>/dev/null || true
done

# Удаление target groups
log INFO "Удаление target groups..."
for tg_id in $(yc lb tg list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    yc lb tg delete --id="$tg_id" 2>/dev/null || true
done

# Удаление дисков
log INFO "Удаление дисков..."
for disk_id in $(yc compute disk list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    yc compute disk delete --id="$disk_id" 2>/dev/null || true
done

# Удаление подсетей
log INFO "Удаление подсетей..."
for subnet_id in $(yc vpc subnet list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    yc vpc subnet delete --id="$subnet_id" 2>/dev/null || true
done

# Удаление security groups
log INFO "Удаление security groups..."
for sg_id in $(yc vpc security-group list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    yc vpc security-group delete --id="$sg_id" 2>/dev/null || true
done

# Удаление сетей
log INFO "Удаление сетей..."
for net_id in $(yc vpc network list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .id'); do
    yc vpc network delete --id="$net_id" 2>/dev/null || true
done

# Удаление S3 buckets
log INFO "Удаление S3 buckets..."
for bucket in $(yc storage bucket list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .name'); do
    yc storage bucket delete --name="$bucket" 2>/dev/null || true
done

# Удаление service accounts
log INFO "Удаление service accounts..."
for sa in "s3-storage-sa" "terraform-sa"; do
    if yc iam service-account get "$sa" --folder-id="$YC_FOLDER_ID" &>/dev/null; then
        # Удаление ключей
        for key_id in $(yc iam access-key list --service-account-name="$sa" --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[].id'); do
            yc iam access-key delete --id="$key_id" 2>/dev/null || true
        done
        for key_id in $(yc iam key list --service-account-name="$sa" --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[].id'); do
            yc iam key delete --id="$key_id" 2>/dev/null || true
        done
        # Удаление SA
        yc iam service-account delete --name="$sa" --folder-id="$YC_FOLDER_ID" 2>/dev/null || true
    fi
done

# Очистка локальных файлов
log INFO "Очистка локальных файлов..."
rm -rf "${PROJECT_ROOT}/.terraform" 2>/dev/null || true
rm -rf "${PROJECT_ROOT}/infrastructure/terraform/.terraform" 2>/dev/null || true
rm -f "${PROJECT_ROOT}/infrastructure/terraform/terraform.tfstate"* 2>/dev/null || true
rm -f "${PROJECT_ROOT}/terraform-outputs.json" 2>/dev/null || true
rm -f "${PROJECT_ROOT}/kubeconfig" 2>/dev/null || true
rm -f "${PROJECT_ROOT}/yc-terraform-key.json" 2>/dev/null || true
rm -f "${PROJECT_ROOT}/key.json" 2>/dev/null || true
rm -rf "${PROJECT_ROOT}/.artifacts" 2>/dev/null || true
rm -f "${PROJECT_ROOT}/argocd-password.txt" 2>/dev/null || true
rm -f "${PROJECT_ROOT}/access-info.txt" 2>/dev/null || true

success "Экстренная очистка завершена!"

# Показать оставшиеся ресурсы
echo ""
log INFO "Проверка оставшихся ресурсов:"
echo "VMs: $(yc compute instance list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .name' | wc -l)"
echo "Networks: $(yc vpc network list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .name' | wc -l)"
echo "Buckets: $(yc storage bucket list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("k8s-airflow")) | .name' | wc -l)"
echo "Service Accounts: $(yc iam service-account list --folder-id="$YC_FOLDER_ID" --format json | jq -r '.[] | select(.name | contains("s3-storage-sa") or contains("terraform-sa")) | .name' | wc -l)"