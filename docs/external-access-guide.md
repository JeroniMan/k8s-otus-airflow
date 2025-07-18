# Руководство по внешнему доступу к приложениям

## Быстрый старт

После развертывания кластера ваши приложения доступны по следующим адресам:

```bash
# Получить IP Load Balancer
LB_IP=$(cd infrastructure/terraform && terraform output -raw load_balancer_ip)

# Основные URL
Airflow: http://$LB_IP:32080
Grafana: http://$LB_IP:32080/grafana
```

## Архитектура доступа

```
Internet
    |
    v
[Yandex Load Balancer] - Внешний IP
    |
    ├── :32080 → Ingress NGINX → /        → Airflow:8080
    ├── :32080 → Ingress NGINX → /grafana → Grafana:3000
    ├── :30880 → Direct NodePort → Airflow:8080
    └── :30300 → Direct NodePort → Grafana:3000
```

## Способы доступа

### 1. Через Ingress Controller (Рекомендуется)

Это основной способ. Все приложения доступны через единый порт 32080:

```yaml
# Ingress автоматически направляет трафик по путям:
http://<LB-IP>:32080/         → Airflow
http://<LB-IP>:32080/grafana  → Grafana
http://<LB-IP>:32080/argocd   → ArgoCD
```

**Преимущества:**
- Единая точка входа
- Поддержка SSL/TLS
- Гибкая маршрутизация
- Возможность добавить домены

### 2. Прямой NodePort доступ

Каждое приложение на своем порту:

```yaml
http://<LB-IP>:30880  → Airflow
http://<LB-IP>:30300  → Grafana
http://<LB-IP>:30090  → Prometheus
```

**Преимущества:**
- Прямой доступ без прокси
- Меньше накладных расходов
- Проще для отладки

### 3. Port Forwarding (для разработки)

```bash
# Запустить все port-forward
./port-forward-all.sh

# Или отдельно
kubectl port-forward -n airflow svc/airflow-webserver 8080:8080
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
```

## Настройка для production

### Добавление доменного имени

1. Купите домен или используйте поддомен
2. Создайте A-запись указывающую на IP Load Balancer
3. Обновите Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: airflow-ingress
  namespace: airflow
spec:
  ingressClassName: nginx
  rules:
  - host: airflow.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: airflow-webserver
            port:
              number: 8080
```

### Настройка SSL/TLS

1. Установите cert-manager (уже включен в проект)
2. Добавьте аннотации в Ingress:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - airflow.yourdomain.com
    secretName: airflow-tls
```

### Ограничение доступа по IP

Добавьте в Ingress аннотацию:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "1.2.3.4/32,5.6.7.8/32"
```

## Решение проблем

### Сервис недоступен

1. Проверьте Load Balancer:
```bash
yc lb nlb list
yc lb nlb get <lb-name>
```

2. Проверьте NodePort сервисы:
```bash
kubectl get svc --all-namespaces | grep NodePort
```

3. Проверьте Ingress:
```bash
kubectl get ingress --all-namespaces
kubectl describe ingress airflow-ingress -n airflow
```

4. Проверьте поды:
```bash
kubectl get pods -n airflow
kubectl get pods -n ingress-nginx
```

### Медленная загрузка

1. Проверьте ресурсы:
```bash
kubectl top nodes
kubectl top pods --all-namespaces
```

2. Масштабируйте Ingress controller:
```bash
kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=3
```

### 502 Bad Gateway

Обычно означает что backend сервис недоступен:

```bash
# Проверить endpoints
kubectl get endpoints -n airflow
kubectl describe svc airflow-webserver -n airflow
```

## Добавление нового приложения

1. Создайте Service:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: default
spec:
  type: ClusterIP
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
```

2. Создайте Ingress:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /myapp
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

3. Или создайте NodePort для прямого доступа:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-nodeport
  namespace: default
spec:
  type: NodePort
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30123  # Выберите порт 30000-32767
```

## Мониторинг доступности

Создайте простой скрипт для проверки:

```bash
#!/bin/bash
# health-check.sh

LB_IP=$(yc lb nlb list --format json | jq -r '.[0].listeners[0].address')

services=(
    "http://$LB_IP:32080|Airflow"
    "http://$LB_IP:32080/grafana|Grafana"
    "http://$LB_IP:30880|Airflow-Direct"
)

for service in "${services[@]}"; do
    IFS='|' read -r url name <<< "$service"
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    echo "$name: $status"
done
```

## Полезные команды

```bash
# Показать все внешние endpoints
kubectl get svc --all-namespaces -o wide | grep -E 'NodePort|LoadBalancer'

# Показать все Ingress правила
kubectl get ingress --all-namespaces

# Тест доступности
curl -I http://<LB-IP>:32080

# Логи Ingress controller
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Перезапустить Ingress controller
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```