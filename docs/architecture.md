# Архитектура проекта

## Обзор

Проект представляет собой production-ready развертывание Apache Airflow в Kubernetes с полным стеком мониторинга и GitOps подходом.

## Компоненты системы

### Инфраструктура

```
┌─────────────────────────────────────────────────────────────┐
│                        Yandex Cloud                           │
│                                                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │   Master    │  │   Worker    │  │   Worker    │          │
│  │    Node     │  │    Node     │  │    Node     │          │
│  │  (2CPU/4GB) │  │  (2CPU/4GB) │  │  (2CPU/4GB) │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│         │                │                │                   │
│         └────────────────┼────────────────┘                   │
│                          │                                    │
│                   ┌──────────────┐                           │
│                   │Load Balancer │                           │
│                   │   (L4 NLB)   │                           │
│                   └──────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

### Kubernetes Layer

```
┌─────────────────────────────────────────────────────────────┐
│                      Kubernetes (k3s)                         │
├───────────────────────┬─────────────────┬──────────────────┤
│      Namespace:       │    Namespace:   │    Namespace:    │
│       airflow         │    monitoring   │     argocd       │
├───────────────────────┼─────────────────┼──────────────────┤
│ • Webserver          │ • Prometheus    │ • ArgoCD Server  │
│ • Scheduler          │ • Grafana       │ • Repo Server    │
│ • Workers (2-10)     │ • Loki          │ • Redis          │
│ • PostgreSQL         │ • Promtail      │ • Dex            │
│ • Redis              │ • AlertManager  │                  │
│ • StatsD             │                 │                  │
└───────────────────────┴─────────────────┴──────────────────┘
```

## Сетевая архитектура

### External Access
- Load Balancer (L4) - единая точка входа
- NodePort Services:
  - 32080 - HTTP (Nginx Ingress)
  - 32443 - HTTPS (Nginx Ingress)

### Internal Networking
- Cluster CIDR: 10.42.0.0/16 (k3s default)
- Service CIDR: 10.43.0.0/16 (k3s default)
- VPC Network: 10.0.1.0/24 (Yandex Cloud)

## Storage Architecture

### Persistent Storage
- NFS Server на master ноде (для учебного проекта)
- StorageClass: nfs-client (default)
- Backup: не настроен (рекомендуется для production)

### Persistent Volumes
- PostgreSQL: 20Gi
- Redis: 10Gi
- Prometheus: 20Gi
- Loki: 20Gi
- Grafana: 5Gi
- Airflow logs: 20Gi

## Security Architecture

### Network Security
- Security Groups в Yandex Cloud
- NetworkPolicies в Kubernetes (базовые)
- Ingress контролируется через Nginx

### Access Control
- RBAC включен
- ServiceAccounts для каждого компонента
- Secrets management через Sealed Secrets (опционально)

### Authentication
- Airflow: встроенная аутентификация
- Grafana: встроенная аутентификация
- ArgoCD: встроенная + возможность OIDC

## High Availability

### Control Plane
- Single master (для учебного проекта)
- Рекомендуется 3 masters для production

### Data Layer
- PostgreSQL: single instance
- Redis: single instance
- Рекомендуется репликация для production

### Application Layer
- Airflow Webserver: 2 replicas
- Airflow Scheduler: 2 replicas
- Airflow Workers: autoscaling 2-10
- Nginx Ingress: 2 replicas

## Monitoring Stack

### Metrics Collection
```
Airflow StatsD → StatsD Exporter → Prometheus → Grafana
Node Exporters → Prometheus → Grafana
kube-state-metrics → Prometheus → Grafana
```

### Logs Collection
```
Container Logs → Promtail → Loki → Grafana
System Logs → Promtail → Loki → Grafana
```

### Alerting
```
Prometheus → AlertManager → Email/Webhook
                         ↓
                   Airflow DAG (optional)
```

## CI/CD Pipeline

### Infrastructure Pipeline
```
GitHub Push → GitHub Actions → Terraform → Yandex Cloud
                            ↓
                         Ansible → k3s Installation
```

### Application Pipeline
```
GitHub Push → ArgoCD → Kubernetes Deployment
                    ↓
              Helm Charts → Applications
```

## Disaster Recovery

### Backup Strategy
- Infrastructure as Code (восстановление через Terraform)
- GitOps (восстановление приложений через ArgoCD)
- Данные: требуется отдельная стратегия

### RTO/RPO
- RTO: ~30-40 минут (полное восстановление)
- RPO: зависит от стратегии бэкапа данных

## Масштабирование

### Horizontal Scaling
- Worker Nodes: добавление через Terraform
- Airflow Workers: автоматическое (HPA)
- Ingress Controllers: автоматическое (HPA)

### Vertical Scaling
- Изменение размера VM через Terraform
- Требуется пересоздание нод

## Ограничения текущей архитектуры

1. **Single Point of Failure**
   - Master нода
   - NFS сервер
   - PostgreSQL/Redis

2. **Безопасность**
   - Базовая настройка NetworkPolicies
   - Отсутствие шифрования данных в покое
   - Простая аутентификация

3. **Производительность**
   - NFS может быть узким местом
   - Отсутствие кэширования

## Рекомендации для Production

1. **High Availability**
   - 3+ master nodes
   - Managed PostgreSQL
   - Redis Sentinel/Cluster
   - Distributed storage (Ceph/GlusterFS)

2. **Security**
   - Внешний Identity Provider (OIDC)
   - Hashicorp Vault для секретов
   - Шифрование данных
   - Сетевая сегментация

3. **Monitoring**
   - Внешний мониторинг кластера
   - Долгосрочное хранение метрик
   - Централизованное логирование

4. **Backup**
   - Velero для backup кластера
   - Регулярный backup БД
   - Snapshot дисков