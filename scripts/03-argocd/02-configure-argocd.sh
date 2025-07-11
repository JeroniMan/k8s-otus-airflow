#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Configuring ArgoCD"

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Patch ArgoCD server for insecure mode (for development)
info "Configuring ArgoCD server..."
kubectl patch configmap argocd-cmd-params-cm -n argocd \
    --type merge \
    -p '{"data":{"server.insecure":"true"}}'

# Restart ArgoCD server to apply changes
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd

# Configure RBAC
info "Configuring RBAC..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow
    g, argocd-admins, role:admin
EOF

# Add Git repository (if needed)
info "Configuring repositories..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: airflow-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/YOUR_USERNAME/k8s-airflow-project.git
EOF

success "ArgoCD configured successfully!"

# Show access information
echo ""
info "ArgoCD Access Information:"
info "Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
info "URL: https://localhost:8080"
info "Username: admin"
info "Password: $(cat ${PROJECT_ROOT}/argocd-password.txt)"

# Optional: Install ArgoCD CLI
if ! command_exists argocd; then
    warning "ArgoCD CLI not installed. To install:"
    info "curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
    info "chmod +x /usr/local/bin/argocd"
fi