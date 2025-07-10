# airflow/dags/hello_world_dag.py
# Простой DAG для проверки работоспособности Airflow

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.operators.dummy import DummyOperator

# Дефолтные аргументы для всех задач
default_args = {
    'owner': 'student',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Создаем DAG
dag = DAG(
    'hello_world',
    default_args=default_args,
    description='Простой DAG для демонстрации',
    schedule_interval='@daily',  # Запускается каждый день
    catchup=False,  # Не запускать за прошлые даты
    tags=['demo', 'training'],
)

# Python функция для задачи
def print_hello():
    """Простая функция которая печатает приветствие"""
    print("Hello from Airflow!")
    print(f"Current time: {datetime.now()}")
    return "Hello task completed successfully!"

def print_world(**context):
    """Функция которая использует контекст Airflow"""
    print("World!")
    print(f"DAG Run date: {context['ds']}")
    print(f"Task Instance: {context['ti']}")
    # Получаем результат предыдущей задачи через XCom
    ti = context['ti']
    hello_result = ti.xcom_pull(task_ids='hello_task')
    print(f"Result from hello_task: {hello_result}")

# Определяем задачи
start_task = DummyOperator(
    task_id='start',
    dag=dag,
)

hello_task = PythonOperator(
    task_id='hello_task',
    python_callable=print_hello,
    dag=dag,
)

world_task = PythonOperator(
    task_id='world_task',
    python_callable=print_world,
    provide_context=True,  # Передаем контекст в функцию
    dag=dag,
)

bash_task = BashOperator(
    task_id='bash_task',
    bash_command='echo "Running in Kubernetes pod: $(hostname)"',
    dag=dag,
)

end_task = DummyOperator(
    task_id='end',
    dag=dag,
)

# Определяем порядок выполнения задач
start_task >> hello_task >> world_task >> bash_task >> end_task