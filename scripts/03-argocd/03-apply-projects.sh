#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Applying ArgoCD Projects"

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Check if ArgoCD is ready
if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
    error "ArgoCD is not installed. Run install-argocd.sh first!"
    exit 1
fi

info "Creating ArgoCD projects..."

# Apply all projects
for project_file in "${PROJECT_ROOT}"/kubernetes/argocd-apps/projects/*.yaml; do
    if [ -f "$project_file" ]; then
        info "Applying $(basename $project_file)..."
        kubectl apply -f "$project_file"
    fi
done

# Create default project if not exists
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  description: Default project
  sourceRepos:
  - '*'
  destinations:
  - namespace: '*'
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
EOF

# List projects
echo ""
info "ArgoCD Projects:"
kubectl get appprojects -n argocd

success "ArgoCD projects configured!"