#!/bin/bash
set -e

source "$(dirname "$0")/../lib/common.sh"

step "Verifying Applications"

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Function to check namespace resources
check_namespace() {
    local namespace=$1
    local expected_deployments=$2

    echo ""
    info "Checking $namespace namespace..."

    # Check pods
    local running_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local total_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$running_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
        success "$namespace: All $running_pods pods are running"
    else
        warning "$namespace: Only $running_pods out of $total_pods pods are running"
        kubectl get pods -n "$namespace" | grep -v "Running" || true
    fi

    # Check services
    local services=$(kubectl get svc -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$services" -gt 0 ]; then
        info "$namespace: $services services found"
    fi

    # Check PVCs
    local pvcs=$(kubectl get pvc -n "$namespace" --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    if [ "$pvcs" -gt 0 ]; then
        info "$namespace: $pvcs PVCs bound"
    fi

    return 0
}

# Check ingress-nginx
check_namespace "ingress-nginx" 1

# Check cert-manager
check_namespace "cert-manager" 3

# Check monitoring stack
check_namespace "monitoring" 5

# Check Airflow
check_namespace "airflow" 5

# Check ingresses
echo ""
info "Checking Ingresses..."
kubectl get ingress --all-namespaces

# Check certificates
echo ""
info "Checking Certificates..."
kubectl get certificates --all-namespaces 2>/dev/null || info "No certificates found (cert-manager might not be ready)"

# Get Load Balancer IP
echo ""
info "Getting Load Balancer IP..."
LB_IP=$(cd "${PROJECT_ROOT}/infrastructure/terraform" && terraform output -raw load_balancer_ip 2>/dev/null || echo "N/A")

if [ "$LB_IP" != "N/A" ]; then
    success "Load Balancer IP: $LB_IP"

    # Test endpoints
    info "Testing endpoints..."

    # Test Airflow
    if curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP:32080" | grep -q "200\|302\|401"; then
        success "Airflow is accessible at http://$LB_IP:32080"
    else
        warning "Airflow is not accessible yet"
    fi

    # Test Grafana
    if curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP:32080/grafana" | grep -q "200\|302"; then
        success "Grafana is accessible at http://$LB_IP:32080/grafana"
    else
        warning "Grafana is not accessible yet"
    fi
fi

# Summary
echo ""
echo "================================="
success "Application verification complete!"
echo "================================="

# Show any failing pods
failing_pods=$(kubectl get pods --all-namespaces | grep -E "(Error|CrashLoopBackOff|Pending)" || true)
if [ -n "$failing_pods" ]; then
    warning "Some pods are having issues:"
    echo "$failing_pods"
else
    success "All applications appear to be healthy!"
fi