#!/bin/bash

set -e

echo "Installing ArgoCD..."

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "nodePort": 32443, "targetPort": 8080}]}}'

echo ""
echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "ArgoCD is ready!"
echo "Access ArgoCD UI:"
echo "  - NodePort: https://<NODE_IP>:32443"
echo "  - Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"