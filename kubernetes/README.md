# Kubernetes манифесты и конфигурации

Эта директория содержит все Kubernetes манифесты для развертывания инфраструктуры и приложений.

## 📁 Структура

```
kubernetes/
├── namespaces/           # Определения namespaces с квотами и политиками
│   ├── airflow.yaml     # Namespace для Apache Airflow
│   ├── monitoring.yaml  # Namespace для Prometheus/Grafana/Loki
│   └── argocd.yaml      # Namespace для ArgoCD
│
├── argocd/              # ArgoCD конфигурации
│   ├── projects/        # ArgoCD Projects
│   │   └── default-project.yaml
│   └── apps/            # ArgoCD Applications
│       ├── root-app.yaml          # Root application (App of Apps)
│       ├── ingress-nginx.yaml     # Ingress Controller
│       ├── airflow.yaml           # Apache Airflow
│       ├── prometheus-stack.yaml  # Prometheus + Grafana
│       └── loki-stack.yaml        # Loki + Promtail
│
├── manifests/           # Дополнительные манифесты
│   ├── storage/         # Storage Classes
│   └── secrets/         # Примеры секретов (НЕ КОММИТИТЬ!)
│
└── helm-charts/         # Кастомные values для Helm charts
```

## 🚀 Порядок применения

### 1. Создание namespaces

```bash
kubectl apply -f namespaces/
```

### 2. Установка ArgoCD

```bash
# Установка ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Ожидание готовности
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# Получение пароля
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 3. Создание ArgoCD Projects

```bash
kubectl apply -f argocd/projects/
```

### 4. Развертывание приложений

```bash
# Применение всех applications
kubectl apply -f argocd/apps/

# Или только root app (он развернет остальные)
kubectl apply -f argocd/apps/root-app.yaml
```

## 📊 Компоненты

### Apache Airflow
- **URL**: http://<LB-IP>:32080
- **Логин**: admin / admin
- **Executor**: Celery
- **База данных**: PostgreSQL
- **Очередь**: Redis
- **DAGs**: Синхронизация из Git

### Prometheus + Grafana
- **Grafana URL**: http://<LB-IP>:32080/grafana
- **Логин**: admin / changeme123
- **Prometheus**: Внутренний endpoint
- **Хранение**: 30 дней метрик

### Loki + Promtail
- **Интеграция**: С Grafana
- **Хранение**: 7 дней логов
- **Сбор**: Со всех подов и системных логов

### Ingress NGINX
- **HTTP**: NodePort 32080
- **HTTPS**: NodePort 32443
- **Метрики**: Экспортируются в Prometheus

## 🔧 Управление через ArgoCD

### CLI команды

```bash
# Список приложений
argocd app list

# Синхронизация приложения
argocd app sync airflow

# Просмотр статуса
argocd app get airflow

# Откат к предыдущей версии
argocd app rollback airflow
```

### Web UI

```bash
# Port-forward для доступа к UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Открыть в браузере
https://localhost:8080
```

## 🔐 Секреты

### Использование Sealed Secrets

1. Установка контроллера:
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.5/controller.yaml
```

2. Создание sealed secret:
```bash
# Создание обычного секрета
kubectl create secret generic mysecret --from-literal=password=mypassword --dry-run=client -o yaml > secret.yaml

# Шифрование
kubeseal < secret.yaml > sealed-secret.yaml

# Применение
kubectl apply -f sealed-secret.yaml
```

### Необходимые секреты

- `airflow-fernet-key` - Ключ шифрования для Airflow
- `airflow-postgresql` - Пароли PostgreSQL
- `airflow-redis` - Пароль Redis
- `flower-auth` - Basic auth для Flower UI
- `grafana-admin` - Пароль админа Grafana

## 📈 Мониторинг

### Дашборды Grafana

После развертывания доступны следующие дашборды:
- Kubernetes Cluster Overview
- Node Exporter Full
- NGINX Ingress Controller
- Airflow Metrics (нужно импортировать)

### Алерты Prometheus

Преднастроенные алерты:
- Node down
- High CPU/Memory usage
- Disk space
- Pod crashes
- Airflow task failures

## 🛠️ Troubleshooting

### Проверка статуса ArgoCD apps

```bash
# Все приложения
kubectl get applications -n argocd

# Детали конкретного приложения
kubectl describe application airflow -n argocd

# События
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

### Проверка логов

```bash
# ArgoCD
kubectl logs -n argocd deployment/argocd-server

# Airflow
kubectl logs -n airflow -l component=webserver

# Prometheus
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
```

### Ресинхронизация приложения

```bash
# Через kubectl
kubectl patch application airflow -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"true"}}}'

# Через ArgoCD CLI
argocd app sync airflow --force
```

## 📝 Заметки

1. Все приложения настроены на автоматическую синхронизацию
2. Storage Class `nfs-client` используется по умолчанию
3. NetworkPolicies применены для безопасности
4. ResourceQuotas установлены для контроля ресурсов
5. Все Helm charts берутся из официальных репозиториев