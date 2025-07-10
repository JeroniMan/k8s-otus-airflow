# airflow/dags/kubernetes_monitoring_dag.py
# DAG для мониторинга Kubernetes кластера

from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from airflow.operators.python import PythonOperator
from airflow.operators.email import EmailOperator
from airflow.utils.trigger_rule import TriggerRule
import json

default_args = {
    'owner': 'devops',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email': ['admin@example.com'],
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'kubernetes_monitoring',
    default_args=default_args,
    description='Мониторинг состояния Kubernetes кластера',
    schedule_interval='*/30 * * * *',  # Каждые 30 минут
    catchup=False,
    tags=['monitoring', 'kubernetes', 'production'],
)


def analyze_cluster_health(**context):
    """Анализ здоровья кластера на основе данных из предыдущей задачи"""
    ti = context['ti']

    # В реальном случае здесь бы был анализ данных из XCom
    print("Analyzing cluster health...")

    # Пример простой проверки
    cluster_healthy = True
    issues = []

    # Здесь была бы реальная логика анализа
    if not cluster_healthy:
        issues.append("Some nodes are not ready")
        issues.append("High memory usage detected")

    # Сохраняем результат для следующих задач
    ti.xcom_push(key='cluster_healthy', value=cluster_healthy)
    ti.xcom_push(key='issues', value=issues)

    return "Analysis completed"


# Задача для проверки состояния нод
check_nodes = KubernetesPodOperator(
    task_id='check_nodes',
    name='check-nodes',
    namespace='airflow',
    image='bitnami/kubectl:latest',
    cmds=['sh', '-c'],
    arguments=['''
        echo "=== Checking Kubernetes Nodes ==="
        kubectl get nodes -o wide
        echo ""
        echo "=== Node Resources ==="
        kubectl top nodes 2>/dev/null || echo "Metrics not available"
        echo ""
        echo "=== Node Conditions ==="
        kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, conditions: .status.conditions}'
    '''],
    get_logs=True,
    dag=dag,
    is_delete_operator_pod=True,
    service_account_name='airflow',  # Нужен SA с правами на чтение
)

# Задача для проверки подов
check_pods = KubernetesPodOperator(
    task_id='check_pods',
    name='check-pods',
    namespace='airflow',
    image='bitnami/kubectl:latest',
    cmds=['sh', '-c'],
    arguments=['''
        echo "=== Checking Failed Pods ==="
        kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded | head -20
        echo ""
        echo "=== Pod Restarts ==="
        kubectl get pods --all-namespaces --sort-by='.status.containerStatuses[0].restartCount' | tail -20
        echo ""
        echo "=== Resource Usage Top 10 ==="
        kubectl top pods --all-namespaces --sort-by=memory | head -10 2>/dev/null || echo "Metrics not available"
    '''],
    get_logs=True,
    dag=dag,
    is_delete_operator_pod=True,
    service_account_name='airflow',
)

# Задача для проверки PVC
check_storage = KubernetesPodOperator(
    task_id='check_storage',
    name='check-storage',
    namespace='airflow',
    image='bitnami/kubectl:latest',
    cmds=['sh', '-c'],
    arguments=['''
        echo "=== Checking Persistent Volume Claims ==="
        kubectl get pvc --all-namespaces
        echo ""
        echo "=== Storage Classes ==="
        kubectl get storageclass
    '''],
    get_logs=True,
    dag=dag,
    is_delete_operator_pod=True,
    service_account_name='airflow',
)

# Python задача для анализа
analyze_health = PythonOperator(
    task_id='analyze_health',
    python_callable=analyze_cluster_health,
    provide_context=True,
    dag=dag,
)

# Задача отправки уведомления (выполняется только при проблемах)
send_alert = EmailOperator(
    task_id='send_alert',
    to=['admin@example.com'],
    subject='Kubernetes Cluster Health Alert',
    html_content="""
    <h3>Cluster Health Issues Detected</h3>
    <p>The following issues were found during the health check:</p>
    <ul>
    <li>Issue 1</li>
    <li>Issue 2</li>
    </ul>
    <p>Please check the Airflow logs for more details.</p>
    """,
    trigger_rule=TriggerRule.ONE_FAILED,  # Выполняется если хотя бы одна задача упала
    dag=dag,
)

# Определяем последовательность выполнения
[check_nodes, check_pods, check_storage] >> analyze_health >> send_alert