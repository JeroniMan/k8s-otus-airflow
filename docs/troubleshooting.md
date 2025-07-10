# Troubleshooting Guide

## Содержание

1. [Частые проблемы](#частые-проблемы)
2. [Terraform ошибки](#terraform-ошибки)
3. [Ansible проблемы](#ansible-проблемы)
4. [Kubernetes проблемы](#kubernetes-проблемы)
5. [Airflow проблемы](#airflow-проблемы)
6. [Мониторинг проблемы](#мониторинг-проблемы)
7. [Сетевые проблемы](#сетевые-проблемы)
8. [Полезные команды](#полезные-команды)

## Частые проблемы

### "Command not found" при запуске скриптов

**Проблема:** Скрипты не запускаются, ошибка "command not found"

**Решение:**
```bash
# Сделать скрипты исполняемыми
chmod +x scripts/*.sh

# Запустить через bash явно
bash scripts/setup-tools.sh
```

### Недостаточно прав для выполнения команд

**Проблема:** Permission denied при установке инструментов

**Решение:**
```bash
# Для команд требующих sudo
sudo apt update  # вместо apt update

# Для pip установки в user space
pip3 install --user ansible

# Добавить user bin в PATH
export PATH=$PATH:~/.local/bin
```

## Terraform ошибки

### "Error: Failed to query available provider packages"

**Проблема:** Terraform не может загрузить провайдеры

**Решение:**
```bash
# Очистить кэш
rm -rf .terraform
rm .terraform.lock.hcl

# Переинициализировать
terraform init -upgrade
```

### "Error: creating VPC network: operation error"

**Проблема:** Недостаточно прав или превышены квоты

**Решение:**
```bash
# Проверить права service account
yc iam service-account list
yc resource-manager folder list-access-bindings --id <folder-id>

# Проверить квоты
yc resource-manager quota list
```

### "Error: Bucket already exists"

**Проблема:** S3 bucket с таким именем уже существует

**Решение:**
```bash
# Использовать уникальное имя
export TF_STATE_BUCKET="tfstate-k8s-airflow-$(date +%s)"

# Или удалить существующий
yc storage bucket delete --name <bucket-name>
```

### Terraform apply зависает

**Проблема:** Процесс создания ресурсов не завершается

**Решение:**
```bash
# Увеличить таймауты
export TF_TIMEOUT=30m

# Применить с debug логами
TF_LOG=DEBUG terraform apply

# Применить по частям
terraform apply -target=yandex_vpc_network.k8s_network
terraform apply -target=yandex_compute_instance.k8s_node
```

## Ansible проблемы

### "Failed to connect to the host via ssh"

**Проблема:** Ansible не может подключиться к серверам

**Решение:**
```bash
# Проверить SSH ключ
ssh -i ~/.ssh/k8s-airflow ubuntu@<ip-address>

# Добавить в known_hosts
ssh-keyscan -H <ip-address> >> ~/.ssh/known_hosts

# Использовать правильный inventory
ansible all -i inventory/hosts.yml -m ping
```

### "Timeout waiting for connection"

**Проблема:** Серверы еще не готовы после создания

**Решение:**
```bash
# Подождать больше времени
sleep 120

# Проверить статус VM
yc compute instance list

# Проверить cloud-init лог
ssh ubuntu@<ip> "sudo cloud-init status"
```

### Python interpreter not found

**Проблема:** Ansible не находит Python на целевых серверах

**Решение:**
```bash
# Указать путь к Python в inventory
ansible_python_interpreter=/usr/bin/python3

# Или установить Python
ansible all -i inventory/hosts.yml -m raw -a "apt update && apt install -y python3"
```

## Kubernetes проблемы

### Nodes в состоянии NotReady

**Проблема:** `kubectl get nodes` показывает NotReady

**Решение:**
```bash
# Проверить состояние k3s
ssh ubuntu@<master-ip> "sudo systemctl status k3s"

# Проверить логи
ssh ubuntu@<master-ip> "sudo journalctl -u k3s -n 100"

# Перезапустить k3s
ssh ubuntu@<master-ip> "sudo systemctl restart k3s"

# Проверить сеть
kubectl get pods -n kube-system
```

### Pods в состоянии Pending

**Проблема:** Pods не могут запуститься

**Решение:**
```bash
# Проверить события
kubectl describe pod <pod-name> -n <namespace>

# Проверить ресурсы
kubectl top nodes
kubectl describe nodes

# Проверить PVC
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>

# Проверить storage class
kubectl get storageclass
```

### ImagePullBackOff

**Проблема:** Не удается скачать Docker образ

**Решение:**
```bash
# Проверить название образа
kubectl describe pod <pod-name> -n <namespace> | grep Image

# Проверить доступность registry
kubectl run test-curl --image=curlimages/curl --rm -it -- \
  curl -I https://registry.hub.docker.com

# Проверить секреты (если private registry)
kubectl get secrets -n <namespace>
```

### CrashLoopBackOff

**Проблема:** Контейнер постоянно перезапускается

**Решение:**
```bash
# Посмотреть логи
kubectl logs <pod-name> -n <namespace> --previous

# Проверить команду запуска
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A5 command

# Временно изменить команду для отладки
kubectl edit deployment <deployment-name> -n <namespace>
# Изменить command на: ["sleep", "3600"]
```

## Airflow проблемы

### Webserver не запускается

**Проблема:** Airflow webserver pod в состоянии Error или CrashLoopBackOff

**Решение:**
```bash
# Проверить секреты
kubectl get secrets -n airflow
kubectl get secret airflow-fernet-key -n airflow -o yaml

# Пересоздать Fernet key
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" | \
  kubectl create secret generic airflow-fernet-key \
  --from-file=fernet-key=/dev/stdin -n airflow --dry-run=client -o yaml | \
  kubectl apply -f -

# Перезапустить pods
kubectl rollout restart deployment airflow-webserver -n airflow
```

### Scheduler не видит DAGs

**Проблема:** DAGs не появляются в UI

**Решение:**
```bash
# Проверить git-sync
kubectl logs -n airflow -l component=git-sync

# Проверить монтирование
kubectl exec -n airflow deployment/airflow-scheduler -- ls -la /opt/airflow/dags

# Принудительная синхронизация
kubectl delete pod -n airflow -l component=git-sync
```

### База данных недоступна

**Проблема:** Connection refused to PostgreSQL

**Решение:**
```bash
# Проверить PostgreSQL pod
kubectl get pods -n airflow | grep postgres
kubectl logs -n airflow -l app.kubernetes.io/name=postgresql

# Проверить service
kubectl get svc -n airflow | grep postgres
kubectl get endpoints -n airflow | grep postgres

# Проверить подключение
kubectl exec -n airflow deployment/airflow-webserver -- \
  nc -zv airflow-postgresql 5432
```

## Мониторинг проблемы

### Grafana не показывает метрики

**Проблема:** Дашборды пустые

**Решение:**
```bash
# Проверить Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
# Открыть http://localhost:9090/targets

# Проверить datasource в Grafana
kubectl exec -n monitoring deployment/prometheus-stack-grafana -- \
  curl -s http://localhost:3000/api/datasources

# Проверить service monitors
kubectl get servicemonitor --all-namespaces
```

### Loki не собирает логи

**Проблема:** Логи не появляются в Grafana

**Решение:**
```bash
# Проверить Promtail
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail

# Проверить права доступа
kubectl get clusterrole promtail -o yaml
kubectl get clusterrolebinding promtail -o yaml

# Проверить Loki
kubectl logs -n monitoring -l app.kubernetes.io/name=loki
```

## Сетевые проблемы

### Сервисы недоступны извне

**Проблема:** Не открывается http://<LB-IP>:32080

**Решение:**
```bash
# Проверить Load Balancer
yc lb nlb list
yc lb nlb get <lb-name>

# Проверить target group
yc lb tg list
yc lb tg get <tg-name>

# Проверить NodePort
kubectl get svc -n ingress-nginx

# Проверить firewall
yc vpc security-group list-rules <sg-id>
```

### Ingress не работает

**Проблема:** 404 при обращении к сервисам

**Решение:**
```bash
# Проверить Ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Проверить Ingress ресурсы
kubectl get ingress --all-namespaces
kubectl describe ingress <name> -n <namespace>

# Проверить backend сервисы
kubectl get endpoints -n <namespace>
```

### DNS не работает внутри кластера

**Проблема:** Pods не могут резолвить имена сервисов

**Решение:**
```bash
# Проверить CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Тест DNS
kubectl run test-dns --image=busybox --rm -it -- \
  nslookup kubernetes.default.svc.cluster.local
```

## Полезные команды

### Отладка Pod

```bash
# Запустить отладочный контейнер
kubectl debug <pod-name> -n <namespace> -it --image=busybox

# Скопировать файлы из pod
kubectl cp <namespace>/<pod>:/path/to/file ./local-file

# Port-forward для отладки
kubectl port-forward <pod-name> -n <namespace> 8080:8080

# Выполнить команду в pod
kubectl exec -n <namespace> <pod-name> -- <command>
```

### Анализ ресурсов

```bash
# Найти pods с высоким потреблением CPU
kubectl top pods --all-namespaces | sort -k3 -nr | head -10

# Найти pods с высоким потреблением памяти
kubectl top pods --all-namespaces | sort -k4 -nr | head -10

# Проверить квоты
kubectl describe resourcequota --all-namespaces

# Найти большие PVC
kubectl get pvc --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): \(.status.capacity.storage)"'
```

### Очистка ресурсов

```bash
# Удалить Evicted pods
kubectl get pods --all-namespaces | grep Evicted | \
  awk '{print $2 " --namespace=" $1}' | xargs kubectl delete pod

# Удалить завершенные Jobs
kubectl delete jobs --all-namespaces --field-selector status.successful=1

# Очистить неиспользуемые PVC
kubectl get pvc --all-namespaces | grep Released
```

### Бэкап и восстановление

```bash
# Экспорт всех ресурсов
kubectl get all,cm,secret,ing,pvc --all-namespaces -o yaml > backup.yaml

# Экспорт конкретного namespace
kubectl get all,cm,secret,ing,pvc -n <namespace> -o yaml > namespace-backup.yaml

# Восстановление
kubectl apply -f backup.yaml
```