# 🚀 Kubernetes + Airflow + Monitoring Stack

Полностью автоматизированное развертывание Apache Airflow в Kubernetes с мониторингом.

## 📋 Описание проекта

Этот проект демонстрирует production-ready развертывание:
- **Apache Airflow** на Kubernetes с Celery Executor
- **Полный стек мониторинга** (Prometheus + Grafana + Loki)
- **GitOps** подход с использованием ArgoCD
- **Infrastructure as Code** с Terraform и Ansible
- **CI/CD** через GitHub Actions

## 🏗️ Архитектура

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│  GitHub Actions │────▶│    Terraform    │────▶│  Yandex Cloud   │
│                 │     │                 │     │   (3 VMs)       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                         │
                                                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │   Kubernetes    │
│     ArgoCD      │────▶│     Ansible     │────▶│   (k3s)         │
│                 │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                         │
                        ┌────────────────────────────────┴─────────────┐
                        │                                              │
                        ▼                                              ▼
                ┌─────────────────┐                          ┌─────────────────┐
                │     Airflow     │                          │   Monitoring    │
                │  • Webserver    │                          │  • Prometheus   │
                │  • Scheduler    │                          │  • Grafana      │
                │  • Workers      │                          │  • Loki         │
                │  • PostgreSQL   │                          │  • AlertManager │
                │  • Redis        │                          │                 │
                └─────────────────┘                          └─────────────────┘
```

## ⚡ Быстрый старт

### Предварительные требования

- Аккаунт Yandex Cloud с балансом ~100₽/день
- Установленные инструменты (или используйте `scripts/setup-tools.sh`):
  - Terraform >= 1.6.0
  - Ansible >= 8.5.0
  - kubectl >= 1.28.0
  - Helm >= 3.13.0
  - Yandex Cloud CLI

### Развертывание за 5 шагов

```bash
# 1. Клонируйте репозиторий
git clone https://github.com/yourusername/k8s-airflow-project.git
cd k8s-airflow-project

# 2. Установите инструменты
./scripts/setup-tools.sh

# 3. Настройте Yandex Cloud
yc init

# 4. Запустите автоматическое развертывание
./scripts/quick-deploy.sh

# 5. Получите доступы (займет ~30-40 минут)
./scripts/get-access-info.sh
```

## 📦 Компоненты

### Apache Airflow
- **Версия**: 2.8.1
- **Executor**: Celery
- **База данных**: PostgreSQL
- **Очередь**: Redis
- **Автомасштабирование**: 2-10 workers

### Мониторинг
- **Prometheus**: Сбор метрик
- **Grafana**: Визуализация
- **Loki**: Централизованные логи
- **AlertManager**: Уведомления

### Инфраструктура
- **Kubernetes**: k3s (легковесный дистрибутив)
- **Ingress**: NGINX Ingress Controller
- **Storage**: NFS для Persistent Volumes
- **GitOps**: ArgoCD для деплоя

## 📁 Структура проекта

```
.
├── .github/workflows/    # CI/CD пайплайны
├── infrastructure/       # Terraform и Ansible
│   ├── terraform/       # Создание облачных ресурсов
│   └── ansible/         # Настройка серверов
├── kubernetes/          # Kubernetes манифесты
│   ├── namespaces/     # Namespaces с квотами
│   ├── argocd/         # ArgoCD приложения
│   └── manifests/      # Дополнительные ресурсы
├── airflow/            # DAGs и конфигурация
│   └── dags/          # Airflow DAGs
├── monitoring/         # Дашборды и алерты
│   ├── dashboards/    # Grafana дашборды
│   └── alerts/        # Prometheus алерты
├── scripts/           # Утилиты и скрипты
├── docs/              # Документация
└── tests/             # Тесты

```

## 🚀 Использование

### Доступ к сервисам

После развертывания сервисы доступны по адресам:

| Сервис | URL | Логин | Пароль |
|--------|-----|-------|--------|
| Airflow | http://\<LB-IP\>:32080 | admin | admin |
| Grafana | http://\<LB-IP\>:32080/grafana | admin | changeme123 |
| ArgoCD | https://localhost:8080 (port-forward) | admin | см. скрипт |

### Управление через Makefile

```bash
make help                # Показать все команды
make deploy-all         # Развернуть всё
make destroy-all        # Удалить всё
make get-kubeconfig     # Получить kubeconfig
make port-forward-airflow  # Локальный доступ к Airflow
```

### Добавление DAGs

1. Создайте DAG в `airflow/dags/`
2. Закоммитьте в Git
3. Git-sync автоматически подхватит изменения

## 💰 Стоимость

При минимальной конфигурации:
- 3 прерываемые VM: ~50-70₽/день
- Load Balancer: ~20₽/день
- Трафик: ~10-20₽/день
- **Итого**: ~100₽/день

## 🔧 Конфигурация

### Изменение параметров

1. **Инфраструктура**: `infrastructure/terraform/terraform.tfvars`
2. **Airflow**: `kubernetes/argocd/apps/airflow.yaml`
3. **Мониторинг**: `kubernetes/argocd/apps/prometheus-stack.yaml`

### Масштабирование

```bash
# Добавить worker ноды
cd infrastructure/terraform
# Измените worker_count в terraform.tfvars
terraform apply

# Увеличить Airflow workers
kubectl edit application airflow -n argocd
# Измените workers.replicas
```

## 🛠️ Troubleshooting

### Частые проблемы

1. **Terraform ошибки**
   ```bash
   # Проверьте credentials
   yc config list
   ```

2. **Pods не запускаются**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   kubectl logs <pod-name> -n <namespace>
   ```

3. **ArgoCD не синхронизируется**
   ```bash
   argocd app sync <app-name>
   argocd app get <app-name>
   ```

### Полезные команды

```bash
# Статус кластера
kubectl get nodes
kubectl get pods --all-namespaces

# Логи Airflow
kubectl logs -n airflow -l component=scheduler

# Метрики
kubectl top nodes
kubectl top pods --all-namespaces
```

## 📚 Документация

- [Архитектура проекта](docs/architecture.md)
- [Руководство по развертыванию](docs/deployment-guide.md)
- [Решение проблем](docs/troubleshooting.md)

## 🤝 Вклад в проект

1. Форкните репозиторий
2. Создайте feature branch
3. Сделайте изменения
4. Создайте Pull Request

## 📝 Лицензия

MIT License - см. [LICENSE](LICENSE)

## 🙏 Благодарности

- OTUS за отличный курс по Kubernetes
- Сообщество Apache Airflow
- Разработчики k3s, ArgoCD, Prometheus

---

**Примечание**: Это учебный проект. Для production использования рекомендуется:
- Использовать управляемый Kubernetes (Managed Kubernetes Service)
- Настроить backup стратегию
- Усилить безопасность (RBAC, Network Policies, секреты)
- Использовать внешнюю БД для Airflow