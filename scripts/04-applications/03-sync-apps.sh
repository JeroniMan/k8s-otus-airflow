#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Syncing ArgoCD Applications"

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Check if ArgoCD is available
if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
    error "ArgoCD is not running!"
    exit 1
fi

# Function to sync an app
sync_app() {
    local app_name=$1
    local timeout=${2:-300}

    info "Syncing $app_name..."

    # Trigger sync
    kubectl patch application "$app_name" -n argocd \
        --type merge \
        -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' || true

    # Wait for sync
    local count=0
    while [ $count -lt $timeout ]; do
        local sync_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        local health_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

        if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
            success "$app_name is synced and healthy"
            return 0
        elif [ "$health_status" = "Progressing" ]; then
            echo -n "."
        else
            echo -n "?"
        fi

        sleep 5
        count=$((count + 5))
    done

    warning "$app_name sync timeout after ${timeout}s (status: $sync_status, health: $health_status)"
    return 1
}

# Get all applications
info "Getting ArgoCD applications..."
apps=$(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}')

if [ -z "$apps" ]; then
    warning "No ArgoCD applications found!"
    exit 0
fi

# Sync in order of dependencies
priority_apps=("ingress-nginx" "cert-manager")
monitoring_apps=("prometheus" "loki" "promtail" "grafana")
application_apps=("airflow")

# Sync priority apps first
for app in "${priority_apps[@]}"; do
    if echo "$apps" | grep -q "$app"; then
        sync_app "$app" 600
        sleep 10
    fi
done

# Sync monitoring apps
for app in "${monitoring_apps[@]}"; do
    if echo "$apps" | grep -q "$app"; then
        sync_app "$app" 300
    fi
done

# Sync application apps
for app in "${application_apps[@]}"; do
    if echo "$apps" | grep -q "$app"; then
        sync_app "$app" 600
    fi
done

# Sync any remaining apps
for app in $apps; do
    if ! echo "${priority_apps[@]} ${monitoring_apps[@]} ${application_apps[@]}" | grep -q "$app"; then
        sync_app "$app" 300
    fi
done

echo ""
success "Application sync completed!"

# Show final status
echo ""
info "Application status:"
kubectl get applications -n argocd