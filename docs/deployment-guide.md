# Руководство по развертыванию

## Содержание

1. [Требования](#требования)
2. [Подготовка окружения](#подготовка-окружения)
3. [Развертывание инфраструктуры](#развертывание-инфраструктуры)
4. [Установка Kubernetes](#установка-kubernetes)
5. [Развертывание приложений](#развертывание-приложений)
6. [Проверка работоспособности](#проверка-работоспособности)
7. [Устранение проблем](#устранение-проблем)

## Требования

### Аппаратные требования

**Минимальная конфигурация:**
- 3 VM (1 master + 2 workers)
- 2 vCPU, 4GB RAM на каждую VM
- 50GB диска для master, 100GB для workers
- Стоимость: ~100₽/день в Yandex Cloud

**Рекомендуемая конфигурация для production:**
- 3 masters + 3 workers
- 4 vCPU, 8GB RAM на каждую VM
- 100GB SSD диска
- Стоимость: ~500₽/день

### Программные требования

- OS: Ubuntu 20.04+ или macOS
- Terraform >= 1.6.0
- Ansible >= 8.5.0
- kubectl >= 1.28.0
- Helm >= 3.13.0
- Python >= 3.8
- Git

### Требования Yandex Cloud

- Активный аккаунт с балансом
- Квоты:
  - Compute instances: минимум 3
  - vCPUs: минимум 6
  - RAM: минимум 12GB
  - Disk: минимум 250GB
  - Load balancers: 1

## Подготовка окружения

### 1. Клонирование репозитория

```bash
git clone https://github.com/yourusername/k8s-airflow-project.git
cd k8s-airflow-project
```

### 2. Установка инструментов

```bash
# Автоматическая установка всех инструментов
./scripts/setup-tools.sh

# Или установка вручную
# Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Ansible
pip3 install --user ansible==8.5.0

# kubectl
curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Yandex Cloud CLI
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
```

### 3. Настройка Yandex Cloud

```bash
# Инициализация
yc init

# Проверка конфигурации
yc config list

# Создание service account
yc iam service-account create --name k8s-terraform-sa
yc resource-manager folder add-access-binding \
  --id $(yc config get folder-id) \
  --role editor \
  --service-account-name k8s-terraform-sa

# Создание ключа доступа
yc iam key create \
  --service-account-name k8s-terraform-sa \
  --output key.json
```

### 4. Создание SSH ключей

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-airflow -N ""
```

## Развертывание инфраструктуры

### Автоматическое развертывание

```bash
# Самый простой способ - одна команда
make deploy-all

# Или через скрипт
./scripts/quick-deploy.sh
```

### Ручное развертывание

#### 1. Создание S3 bucket для Terraform state

```bash
export BUCKET_NAME="tfstate-k8s-airflow-$(date +%s)"
yc storage bucket create --name $BUCKET_NAME
```

#### 2. Настройка Terraform

```bash
cd infrastructure/terraform

# Обновить имя bucket в main.tf
sed -i "s/tfstate-k8s-airflow/$BUCKET_NAME/g" main.tf

# Создать terraform.tfvars
cat > terraform.tfvars << EOF
yc_cloud_id  = "$(yc config get cloud-id)"
yc_folder_id = "$(yc config get folder-id)"
yc_zone      = "ru-central1-a"
ssh_public_key_path  = "~/.ssh/k8s-airflow.pub"
ssh_private_key_path = "~/.ssh/k8s-airflow"

master_count  = 1
master_cpu    = 2
master_memory = 4

worker_count  = 2
worker_cpu    = 2
worker_memory = 4

preemptible   = true
core_fraction = 50
EOF
```

#### 3. Инициализация и применение Terraform

```bash
# Установка переменной окружения для ключа
export YC_SERVICE_ACCOUNT_KEY_FILE=$PWD/../../key.json

# Инициализация
terraform init

# Планирование
terraform plan

# Применение
terraform apply

# Сохранение outputs
terraform output -json > outputs.json
```

## Установка Kubernetes

### 1. Проверка доступности серверов

```bash
cd ../../infrastructure/ansible

# Проверка подключения
ansible all -i inventory/hosts.yml -m ping
```

### 2. Подготовка нод

```bash
ansible-playbook -i inventory/hosts.yml playbooks/prepare-nodes.yml
```

### 3. Установка k3s

```bash
ansible-playbook -i inventory/hosts.yml playbooks/install-k3s.yml
```

### 4. Получение kubeconfig

```bash
cd ../..
./scripts/get-kubeconfig.sh

# Настройка kubectl
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes
```

## Развертывание приложений

### 1. Создание необходимых секретов

```bash
# Создание namespace
kubectl create namespace airflow

# Airflow Fernet Key
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" | \
  kubectl create secret generic airflow-fernet-key \
  --from-file=fernet-key=/dev/stdin -n airflow
```

### 2. Установка ArgoCD

```bash
# Создание namespace и установка
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Ожидание готовности
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# Получение пароля
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 3. Развертывание приложений через ArgoCD

```bash
# Применение namespaces
kubectl apply -f kubernetes/namespaces/

# Применение ArgoCD applications
kubectl apply -f kubernetes/argocd/apps/

# Проверка статуса
kubectl get applications -n argocd

# Ожидание синхронизации
watch kubectl get applications -n argocd
```

## Проверка работоспособности

### 1. Проверка состояния кластера

```bash
# Nodes
kubectl get nodes

# Все pods
kubectl get pods --all-namespaces

# Проблемные pods
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Services
kubectl get svc --all-namespaces
```

### 2. Проверка доступа к сервисам

```bash
# Получение IP Load Balancer
LB_IP=$(cd infrastructure/terraform && terraform output -raw load_balancer_ip)

# Проверка Airflow
curl -s -o /dev/null -w "%{http_code}" http://$LB_IP:32080
# Должно вернуть 200

# Проверка через браузер
echo "Airflow: http://$LB_IP:32080"
echo "Grafana: http://$LB_IP:32080/grafana"
```

### 3. Проверка логов

```bash
# Airflow scheduler
kubectl logs -n airflow -l component=scheduler --tail=50

# ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

# Ingress
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
```

## Устранение проблем

### Pods не запускаются

```bash
# Детальная информация о pod
kubectl describe pod <pod-name> -n <namespace>

# События
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Логи
kubectl logs <pod-name> -n <namespace> --previous
```

### Нет доступа к сервисам

```bash
# Проверка Ingress
kubectl get ingress --all-namespaces
kubectl describe ingress -n <namespace>

# Проверка endpoints
kubectl get endpoints -n <namespace>

# Проверка service
kubectl get svc -n <namespace>
kubectl describe svc <service-name> -n <namespace>
```

### ArgoCD не синхронизируется

```bash
# Ручная синхронизация
kubectl patch application <app-name> -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"true"}}}'

# Проверка репозитория
kubectl logs -n argocd deployment/argocd-repo-server

# Hard refresh
argocd app sync <app-name> --hard-refresh
```

### Недостаточно ресурсов

```bash
# Проверка использования ресурсов
kubectl top nodes
kubectl top pods --all-namespaces

# Проверка лимитов
kubectl describe resourcequota --all-namespaces
kubectl describe limitrange --all-namespaces
```

## Очистка и удаление

### Удаление приложений

```bash
# Через ArgoCD
kubectl delete applications --all -n argocd

# Удаление namespaces
kubectl delete namespace airflow monitoring argocd ingress-nginx
```

### Удаление инфраструктуры

```bash
cd infrastructure/terraform
terraform destroy -auto-approve
```

### Полная очистка

```bash
make destroy-all
# или
make emergency-cleanup
```