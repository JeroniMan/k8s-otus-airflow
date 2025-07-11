# 🚀 Kubernetes + Airflow + Monitoring Stack на Yandex Cloud

Production-ready развертывание Apache Airflow на Kubernetes (k3s) с полным стеком мониторинга с использованием Infrastructure as Code.

## 📋 Обзор проекта

Этот проект автоматизирует развертывание полноценной платформы для оркестрации данных:

- **Apache Airflow 2.8.1** - оркестратор workflow для data pipelines
- **Kubernetes (k3s)** - легковесная версия K8s для управления контейнерами
- **Мониторинг** - Prometheus + Grafana + Loki для метрик и логов
- **GitOps** - ArgoCD для автоматического развертывания из Git
- **Infrastructure as Code** - Terraform для облачных ресурсов, Ansible для настройки

### Что особенно полезно для Data Engineer:

- ✅ **Airflow с KubernetesExecutor** - каждая задача в отдельном pod'е, изоляция и масштабирование
- ✅ **Git-sync для DAGs** - автоматическая синхронизация DAG'ов из репозитория
- ✅ **Мониторинг DAG'ов** - готовые дашборды для отслеживания выполнения задач
- ✅ **Централизованные логи** - все логи Airflow доступны через Grafana/Loki
- ✅ **CI/CD для DAG'ов** - push в Git → автоматическое обновление в кластере

## 🏗️ Архитектура решения

```
┌─────────────────────────────────────────────────────────────┐
│                     Yandex Cloud                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Master Node │  │Worker Node 1│  │Worker Node 2│         │
│  │   (k3s)     │  │   (k3s)     │  │   (k3s)     │         │
│  │  • etcd     │  │ • Airflow   │  │ • Airflow   │         │
│  │  • API      │  │   Workers   │  │   Workers   │         │
│  │  • NFS      │  │ • Promtail  │  │ • Promtail  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                │                │                  │
│         └────────────────┼────────────────┘                  │
│                          │                                   │
│                   ┌──────────────┐                          │
│                   │Load Balancer │                          │
│                   │  (External)  │                          │
│                   └──────────────┘                          │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │   Internet   │
                    └──────────────┘
```

### Компоненты для работы с данными:

1. **Airflow Components**:
   - Webserver - UI для управления DAG'ами
   - Scheduler - планировщик задач
   - Workers - динамические pod'ы для выполнения задач
   - PostgreSQL - метаданные Airflow
   - Git-sync - синхронизация DAG'ов

2. **Мониторинг Pipeline'ов**:
   - Метрики выполнения DAG'ов и задач
   - Время выполнения, успешность, ошибки
   - Алерты при сбоях
   - История выполнения

## ⚡ Быстрый старт

### Требования

- Аккаунт Yandex Cloud с бюджетом ~100₽/день
- macOS или Linux (Ubuntu 20.04+)
- Базовые знания Kubernetes (не обязательно глубокие)

### 1. Подготовка окружения

```bash
# Клонируем репозиторий
git clone https://github.com/yourusername/k8s-otus-airflow.git
cd k8s-otus-airflow

# Копируем шаблон настроек
cp .env.example .env

# Редактируем настройки
nano .env  # Указываем YC_CLOUD_ID, YC_FOLDER_ID и другие параметры

# Устанавливаем необходимые инструменты
make init
```

### 2. Развертывание всей инфраструктуры

```bash
# Полное развертывание одной командой (~20-30 минут)
make deploy

# Или пошагово для понимания процесса:
make infra    # Создаем облачную инфраструктуру (VMs, сеть, LB)
make k8s      # Устанавливаем Kubernetes
make argocd   # Устанавливаем GitOps систему
make apps     # Развертываем Airflow и мониторинг
make info     # Показываем информацию для доступа
```

### 3. Доступ к сервисам

После развертывания получаем информацию для доступа:

```bash
make info
```

Сервисы будут доступны по адресам:
- **Airflow UI**: `http://<LB-IP>:32080` (admin/admin)
- **Grafana**: `http://<LB-IP>:32080/grafana` (admin/changeme123)
- **ArgoCD**: через port-forward (см. инструкцию ниже)

### 4. Добавление своих DAG'ов

Просто добавьте DAG файлы в папку `airflow/dags/` и сделайте commit:

```bash
# Создаем новый DAG
cat > airflow/dags/my_etl_pipeline.py << 'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.kubernetes.operators.kubernetes_pod import KubernetesPodOperator

default_args = {
    'owner': 'data-team',
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'my_etl_pipeline',
    default_args=default_args,
    description='ETL pipeline example',
    schedule_interval='@daily',
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['etl', 'production'],
)

# Пример задачи на Python
def extract_data():
    print("Extracting data from source...")
    # Ваш код извлечения данных
    return "data_extracted"

extract_task = PythonOperator(
    task_id='extract_data',
    python_callable=extract_data,
    dag=dag,
)

# Пример задачи в отдельном контейнере (например, dbt)
transform_task = KubernetesPodOperator(
    task_id='transform_data',
    name='dbt-transform',
    namespace='airflow',
    image='your-registry/dbt:latest',
    cmds=['dbt', 'run'],
    dag=dag,
)

extract_task >> transform_task
EOF

# Коммитим и пушим
git add airflow/dags/my_etl_pipeline.py
git commit -m "Add new ETL pipeline"
git push
```

DAG автоматически появится в Airflow через 60 секунд!

### 5. Удаление инфраструктуры

```bash
# Полное удаление всех ресурсов
make destroy

# Экстренное удаление (если обычное не работает)
make destroy-emergency
```

## 💰 Стоимость решения

| Конфигурация | Ресурсы | Стоимость (₽/день) |
|--------------|---------|-------------------|
| Минимальная | 3 VM (прерываемые, 50% CPU) | ~70-100 |
| Стандартная | 3 VM (обычные, 100% CPU) | ~150-200 |
| Production | 6 VM (HA, 100% CPU) | ~300-500 |

Проверка текущих расходов: `make cost-estimate`

## 📊 Мониторинг Data Pipeline'ов

### Готовые дашборды Grafana

1. **Airflow Overview**:
   - Количество активных DAG'ов
   - Успешность выполнения задач
   - Среднее время выполнения
   - Очередь задач

2. **Task Performance**:
   - Время выполнения по задачам
   - Топ долгих задач
   - История сбоев
   - Тренды производительности

3. **System Resources**:
   - CPU/Memory по pod'ам Airflow
   - Использование дисков
   - Сетевая активность

### Просмотр логов

Все логи Airflow централизованно собираются в Loki и доступны через Grafana:

```
1. Открыть Grafana
2. Перейти в Explore
3. Выбрать Loki как источник
4. Использовать запрос: {namespace="airflow", pod=~".*worker.*"}
```

### Настройка алертов

Пример алерта для длительных задач:

```yaml
# monitoring/alerts/airflow-custom.yaml
- alert: AirflowTaskRunningTooLong
  expr: airflow_task_duration > 3600  # больше часа
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Задача {{ $labels.task_id }} выполняется больше часа"
```

## 🛠️ Продвинутая настройка

### Использование с Kafka

Пример DAG для работы с Kafka:

```python
from airflow.providers.apache.kafka.operators.produce import ProduceToTopicOperator
from airflow.providers.apache.kafka.operators.consume import ConsumeFromTopicOperator

# Продюсер
produce_task = ProduceToTopicOperator(
    task_id='produce_to_kafka',
    topic='my_topic',
    producer_function=lambda: {"key": "value"},
    kafka_config={'bootstrap.servers': 'kafka:9092'},
    dag=dag,
)

# Консьюмер
consume_task = ConsumeFromTopicOperator(
    task_id='consume_from_kafka',
    topics=['my_topic'],
    consumer_config={'bootstrap.servers': 'kafka:9092'},
    dag=dag,
)
```

### Интеграция с dbt

```python
from airflow.providers.docker.operators.docker import DockerOperator

dbt_run = DockerOperator(
    task_id='dbt_run',
    image='your-registry/dbt:latest',
    command='dbt run --profiles-dir /dbt --project-dir /dbt',
    docker_url='unix://var/run/docker.sock',
    network_mode='bridge',
    volumes=['/path/to/dbt:/dbt'],
    dag=dag,
)

dbt_test = DockerOperator(
    task_id='dbt_test',
    image='your-registry/dbt:latest',
    command='dbt test --profiles-dir /dbt --project-dir /dbt',
    docker_url='unix://var/run/docker.sock',
    network_mode='bridge',
    volumes=['/path/to/dbt:/dbt'],
    dag=dag,
)

dbt_run >> dbt_test
```

### Масштабирование workers

```bash
# Изменить количество worker нод
cd infrastructure/terraform
nano terraform.tfvars  # worker_count = 5

# Применить изменения
terraform apply

# Обновить Ansible inventory и переустановить k3s на новых нодах
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbooks/install-k3s.yml
```

## 📁 Структура проекта

```
.
├── airflow/                     # DAG файлы и конфигурация Airflow
│   ├── dags/                   # Ваши DAG'и
│   ├── plugins/                # Кастомные операторы и хуки
│   └── requirements.txt        # Python зависимости
│
├── infrastructure/             
│   ├── terraform/              # IaC для облачных ресурсов
│   │   ├── main.tf            # Основная конфигурация
│   │   ├── variables.tf       # Переменные
│   │   └── outputs.tf         # Выходные данные
│   │
│   └── ansible/                # Конфигурация и установка k3s
│       ├── playbooks/         # Playbook'и
│       └── roles/             # Ansible роли
│
├── kubernetes/                 
│   ├── argocd-apps/           # ArgoCD приложения
│   ├── base/                  # Базовые K8s ресурсы
│   └── helm-values/           # Настройки Helm чартов
│
├── monitoring/                 
│   ├── dashboards/            # Grafana дашборды
│   └── alerts/                # Prometheus алерты
│
├── scripts/                    # Скрипты автоматизации
│   ├── 00-prerequisites/      # Проверка и установка зависимостей
│   ├── 01-infrastructure/     # Управление инфраструктурой
│   ├── 02-kubernetes/         # Установка K8s
│   ├── 03-argocd/            # Настройка GitOps
│   ├── 04-applications/       # Развертывание приложений
│   └── 05-operations/         # Операционные задачи
│
├── .env.example               # Шаблон переменных окружения
├── Makefile                   # Команды автоматизации
└── README.md                  # Этот файл
```

## 🔧 Полезные команды

### Работа с DAG'ами

```bash
# Просмотр логов Airflow
make logs-airflow

# Port-forward для локального доступа к Airflow
make pf-airflow

# SSH на master ноду для отладки
make ssh-master

# Перезапуск scheduler'а
kubectl rollout restart deployment airflow-scheduler -n airflow
```

### Мониторинг и отладка

```bash
# Статус всех компонентов
make status

# Последние события в кластере
make events

# Проверка здоровья системы
make health-check

# Детальная диагностика проблем
make troubleshoot
```

### Backup и восстановление

```bash
# Создание backup конфигураций
make backup

# Экспорт DAG'ов и конфигов
kubectl cp airflow/airflow-scheduler-xxx:/opt/airflow/dags ./backup/dags

# Backup базы данных Airflow
kubectl exec -n airflow airflow-postgresql-0 -- \
  pg_dump -U airflow airflow > airflow-backup.sql
```

## 🚨 Решение типичных проблем

### DAG не появляется в UI

1. Проверить git-sync:
```bash
kubectl logs -n airflow -l component=git-sync
```

2. Проверить ошибки парсинга:
```bash
kubectl exec -n airflow deployment/airflow-scheduler -- \
  airflow dags list-import-errors
```

### Задачи зависают в состоянии "queued"

1. Проверить ресурсы кластера:
```bash
kubectl top nodes
kubectl describe nodes
```

2. Проверить лимиты namespace:
```bash
kubectl describe resourcequota -n airflow
```

### Проблемы с логами

1. Проверить Promtail:
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail
```

2. Проверить Loki:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=loki
```

## 🤝 Вклад в проект

1. Fork репозитория
2. Создайте feature branch (`git checkout -b feature/amazing-feature`)
3. Commit изменения (`git commit -m 'Add amazing feature'`)
4. Push в branch (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

## 📚 Дополнительные ресурсы

- [Airflow Best Practices](https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html)
- [Kubernetes для Airflow](https://airflow.apache.org/docs/apache-airflow/stable/kubernetes.html)
- [k3s документация](https://docs.k3s.io/)
- [Yandex Cloud Terraform Provider](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs)

## 📝 Лицензия

MIT License - подробности в файле [LICENSE](LICENSE)

## 🙏 Благодарности

- Команде Apache Airflow за отличный оркестратор
- Rancher Labs за k3s
- OTUS за вдохновение и знания
- Сообществу Data Engineers за обратную связь

---

**Примечание для Data Engineers**: Этот проект оптимизирован для запуска data pipeline'ов. Если вам нужна помощь с интеграцией специфичных инструментов (Spark, Flink, Beam), создайте issue в репозитории.