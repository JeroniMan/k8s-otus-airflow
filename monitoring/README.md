# Monitoring Configuration

Эта директория содержит конфигурации для мониторинга кластера и приложений.

## 📁 Структура

```
monitoring/
├── dashboards/              # Grafana дашборды
│   ├── airflow-dashboard.json    # Мониторинг Airflow
│   └── k8s-cluster.json         # Обзор Kubernetes кластера
├── alerts/                  # Prometheus алерты
│   ├── airflow-alerts.yaml      # Алерты для Airflow
│   └── cluster-alerts.yaml      # Алерты для кластера
├── .gitignore
└── README.md
```

## 📊 Дашборды

### airflow-dashboard.json
Отображает метрики Apache Airflow:
- Успешность/неудачи выполнения задач
- Количество запущенных задач
- Среднее время выполнения
- Heartbeat scheduler'а

### k8s-cluster.json
Общий обзор Kubernetes кластера:
- Статус кластера и нод
- Использование CPU и памяти по нодам
- Общее количество подов и namespaces
- Тренды использования ресурсов

## 🚨 Алерты

### Airflow алерты
- `AirflowSchedulerDown` - Scheduler недоступен
- `AirflowWebserverDown` - Webserver недоступен
- `AirflowNoWorkersAvailable` - Нет доступных воркеров
- `AirflowHighTaskFailureRate` - Высокий процент неудачных задач
- `AirflowSchedulerHeartbeatMissing` - Отсутствует heartbeat
- `AirflowHighQueuedTasks` - Много задач в очереди
- `AirflowDatabaseDown` - База данных недоступна
- `AirflowRedisDown` - Redis недоступен

### Кластер алерты
- `KubernetesNodeNotReady` - Нода не готова
- `KubernetesNodeHighCpuUsage` - Высокая загрузка CPU (>85%)
- `KubernetesNodeHighMemoryUsage` - Высокое использование памяти (>85%)
- `KubernetesNodeLowDiskSpace` - Мало места на диске (<15%)
- `KubernetesPodCrashLooping` - Pod в CrashLoopBackOff
- `KubernetesPersistentVolumeClaimPending` - PVC в состоянии Pending
- `KubernetesDeploymentReplicasMismatch` - Несоответствие реплик Deployment
- `KubernetesStatefulsetReplicasMismatch` - Несоответствие реплик StatefulSet
- `KubernetesContainerHighRestartCount` - Много перезапусков контейнера

## 🔧 Установка

### Импорт дашбордов в Grafana

1. Через UI:
   - Откройте Grafana
   - Перейдите в Dashboards → Import
   - Загрузите JSON файл или вставьте содержимое

2. Через ConfigMap (автоматически):
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: grafana-dashboards
     namespace: monitoring
   data:
     airflow.json: |
       <содержимое dashboards/airflow-dashboard.json>
   ```

### Применение алертов

```bash
# Применить алерты
kubectl apply -f alerts/

# Проверить что алерты загружены
kubectl logs -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0 | grep "Loading configuration"
```

## 📈 Метрики Airflow

Для работы дашбордов Airflow нужно настроить StatsD exporter:

```yaml
# Уже включено в конфигурации Airflow
airflow:
  config:
    AIRFLOW__METRICS__STATSD_ON: "True"
    AIRFLOW__METRICS__STATSD_HOST: "airflow-statsd"
    AIRFLOW__METRICS__STATSD_PORT: "9125"
```

## 🔗 Доступ к сервисам

### Grafana
- URL: `http://<LB-IP>:32080/grafana`
- Login: `admin`
- Password: `changeme123`

### Prometheus
```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
```
URL: `http://localhost:9090`

### AlertManager
```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093
```
URL: `http://localhost:9093`

## 🛠️ Troubleshooting

### Дашборд не показывает данные
1. Проверьте что Prometheus scrape успешен:
   ```
   http://prometheus:9090/targets
   ```
2. Проверьте наличие метрик:
   ```
   http://prometheus:9090/graph
   ```
3. Проверьте правильность datasource в Grafana

### Алерты не срабатывают
1. Проверьте что правила загружены:
   ```bash
   kubectl exec -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0 -- \
     promtool rules list /etc/prometheus/rules/
   ```
2. Проверьте статус алертов:
   ```
   http://prometheus:9090/alerts
   ```

## 📝 Создание новых дашбордов

1. Создайте дашборд в Grafana UI
2. Экспортируйте JSON: Settings → JSON Model
3. Сохраните в `dashboards/`
4. Коммитните в репозиторий

## 🎯 Best Practices

1. **Дашборды**: Используйте переменные для фильтрации
2. **Алерты**: Всегда добавляйте аннотации с описанием
3. **Метрики**: Используйте recording rules для сложных запросов
4. **Нейминг**: Следуйте конвенции `component_metric_unit`