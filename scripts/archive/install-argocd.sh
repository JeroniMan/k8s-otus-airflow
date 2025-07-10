#!/bin/bash
# Скрипт установки ArgoCD

echo "=== Шаг 1: Создание namespace для ArgoCD ==="
kubectl create namespace argocd

echo -e "\n=== Шаг 2: Установка ArgoCD ==="
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo -e "\n=== Шаг 3: Ждем готовности ArgoCD (это займет 2-3 минуты) ==="
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

echo -e "\n=== Шаг 4: Проверяем статус ==="
kubectl get pods -n argocd

echo -e "\n=== Шаг 5: Получаем пароль администратора ==="
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Пароль ArgoCD admin: $ARGOCD_PASSWORD"
echo "$ARGOCD_PASSWORD" > argocd-password.txt

echo -e "\n=== Готово! ArgoCD установлен ==="