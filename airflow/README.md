# Apache Airflow DAGs

Эта директория содержит DAGs (Directed Acyclic Graphs) для Apache Airflow.

## 📁 Структура

```
airflow/
├── dags/                          # DAG файлы
│   ├── hello_world_dag.py        # Простой демо DAG
│   └── kubernetes_monitoring_dag.py # Мониторинг K8s кластера
├── plugins/                       # Кастомные плагины (пока пусто)
├── requirements.txt              # Python зависимости
└── README.md                     # Этот файл
```

## 🚀 DAGs

### hello_world_dag.py
- **Назначение**: Простая демонстрация возможностей Airflow
- **Расписание**: Ежедневно
- **Задачи**:
  - `start` - Dummy оператор для начала
  - `hello_task` - Python функция печатающая "Hello"
  - `world_task` - Python функция с использованием XCom
  - `bash_task` - Выполнение bash команды
  - `end` - Dummy оператор для завершения

### kubernetes_monitoring_dag.py
- **Назначение**: Мониторинг состояния Kubernetes кластера
- **Расписание**: Каждые 30 минут
- **Задачи**:
  - `check_nodes` - Проверка состояния нод
  - `check_pods` - Проверка проблемных подов
  - `check_storage` - Проверка PVC и storage
  - `analyze_health` - Анализ собранных данных
  - `send_alert` - Отправка уведомления при проблемах

## 🔧 Настройка

### ServiceAccount для Kubernetes

Для работы `kubernetes_monitoring_dag` нужен ServiceAccount с правами:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: airflow
  namespace: airflow
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: airflow-k8s-reader
rules:
- apiGroups: [""]
  resources: ["nodes", "pods", "persistentvolumeclaims"]
  verbs: ["get", "list"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["nodes", "pods"]
  verbs: ["get", "list"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: airflow-k8s-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: airflow-k8s-reader
subjects:
- kind: ServiceAccount
  name: airflow
  namespace: airflow
```

### Git Sync

DAGs автоматически синхронизируются из Git репозитория каждые 60 секунд.

## 📝 Создание нового DAG

Пример простого DAG:

```python
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

default_args = {
    'owner': 'your-name',
    'start_date': datetime(2024, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'my_new_dag',
    default_args=default_args,
    description='Описание DAG',
    schedule_interval='@hourly',
    catchup=False,
    tags=['custom'],
)

def my_task():
    print("Doing something...")
    return "Success!"

task = PythonOperator(
    task_id='my_task',
    python_callable=my_task,
    dag=dag,
)
```

## 🐛 Отладка

### Локальное тестирование

```bash
# Проверка синтаксиса
python dags/hello_world_dag.py

# Список DAGs
airflow dags list

# Тестирование задачи
airflow tasks test hello_world hello_task 2024-01-01
```

### В Kubernetes

```bash
# Логи scheduler
kubectl logs -n airflow -l component=scheduler

# Логи конкретной задачи
kubectl logs -n airflow <pod-name>

# Проверка Git sync
kubectl logs -n airflow -l component=git-sync
```

## 📊 Метрики

Airflow экспортирует метрики в StatsD формате:
- Количество выполненных задач
- Время выполнения
- Количество ошибок
- Состояние пула воркеров

Метрики доступны в Grafana через Prometheus.

## 🔗 Полезные ссылки

- [Airflow Documentation](https://airflow.apache.org/docs/)
- [Best Practices](https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html)
- [KubernetesPodOperator Guide](https://airflow.apache.org/docs/apache-airflow-providers-kubernetes/stable/operators.html)