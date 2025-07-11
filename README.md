# 🚀 Kubernetes + Airflow + Monitoring Stack on Yandex Cloud

Production-ready deployment of Apache Airflow on Kubernetes (k3s) with full monitoring stack using Infrastructure as Code.

## 📋 Overview

This project automates the deployment of:
- **Apache Airflow** on Kubernetes with KubernetesExecutor
- **Full monitoring stack** (Prometheus + Grafana + Loki)
- **GitOps** with ArgoCD
- **Infrastructure as Code** with Terraform and Ansible
- **CI/CD** through GitHub Actions

## 🏗️ Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│  GitHub Actions │────▶│    Terraform    │────▶│  Yandex Cloud   │
│                 │     │                 │     │   (3 VMs)       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                         │
                                                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │   Kubernetes    │
│     ArgoCD      │────▶│     Ansible     │────▶│   (k3s)         │
│                 │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## ⚡ Quick Start

### Prerequisites

- Yandex Cloud account with ~100₽/day budget
- macOS or Linux (Ubuntu 20.04+)
- Basic knowledge of Kubernetes and Terraform

### 1. Clone and Setup

```bash
# Clone repository
git clone https://github.com/yourusername/k8s-otus-airflow.git
cd k8s-otus-airflow

# Create environment file
cp .env.example .env

# Edit .env with your values
nano .env  # Set YC_CLOUD_ID, YC_FOLDER_ID, etc.

# Initialize environment (install tools)
make init
```

### 2. Deploy Everything

```bash
# Full deployment (~20-30 minutes)
make deploy

# Or step by step:
make infra    # Create cloud infrastructure
make k8s      # Install Kubernetes
make argocd   # Install ArgoCD
make apps     # Deploy applications
make info     # Show access information
```

### 3. Access Services

After deployment, get access information:

```bash
make info
```

Services will be available at:
- **Airflow**: `http://<LB-IP>:32080`
- **Grafana**: `http://<LB-IP>:32080/grafana`
- **ArgoCD**: `kubectl port-forward svc/argocd-server -n argocd 8080:443`

### 4. Cleanup

```bash
# Destroy everything
make destroy

# Emergency cleanup (if normal destroy fails)
make destroy-emergency
```

## 📦 Components

### Infrastructure
- **Yandex Cloud VMs**: 1 master + 2 workers (configurable)
- **k3s**: Lightweight Kubernetes distribution
- **Load Balancer**: For external access
- **S3 Storage**: For Terraform state and Loki logs

### Applications
- **Apache Airflow 2.8.1**
  - KubernetesExecutor for dynamic scaling
  - PostgreSQL backend
  - Git-sync for DAGs
  - StatsD metrics

- **Monitoring Stack**
  - Prometheus for metrics
  - Grafana for visualization
  - Loki for centralized logs
  - AlertManager for notifications

### GitOps
- **ArgoCD**: Automated application deployment
- **Helm**: Package management
- **Kustomize**: Configuration management

## 💰 Cost Estimation

| Configuration | Resources | Cost (RUB/day) |
|--------------|-----------|----------------|
| Minimal | 3 VMs (preemptible, 50% CPU) | ~70-100 |
| Standard | 3 VMs (regular, 100% CPU) | ~150-200 |
| Production | 6 VMs (HA, 100% CPU) | ~300-500 |

Check current costs: `make cost-estimate`

## 📁 Project Structure

```
.
├── .github/workflows/    # CI/CD pipelines
├── infrastructure/       
│   ├── terraform/       # Cloud resources (VMs, network, LB)
│   └── ansible/         # k3s installation and configuration
├── kubernetes/          
│   ├── argocd-apps/    # ArgoCD application definitions
│   ├── base/           # Base K8s resources (RBAC, storage)
│   └── helm-values/    # Helm chart configurations
├── airflow/            
│   └── dags/           # Airflow DAG files
├── monitoring/         
│   ├── dashboards/     # Grafana dashboards
│   └── alerts/         # Prometheus alert rules
├── scripts/            # Automation scripts
│   ├── 00-prerequisites/
│   ├── 01-infrastructure/
│   ├── 02-kubernetes/
│   ├── 03-argocd/
│   ├── 04-applications/
│   └── 05-operations/
└── docs/               # Additional documentation
```

## 🛠️ Configuration

### Environment Variables (.env)

```bash
# Yandex Cloud
YC_CLOUD_ID="your-cloud-id"
YC_FOLDER_ID="your-folder-id"

# SSH Keys
SSH_PUBLIC_KEY_PATH="~/.ssh/k8s-airflow.pub"
SSH_PRIVATE_KEY_PATH="~/.ssh/k8s-airflow"

# S3 Storage
TF_STATE_BUCKET="tfstate-k8s-airflow-unique"
LOKI_S3_BUCKET="loki-k8s-airflow-unique"

# Applications
GRAFANA_ADMIN_PASSWORD="your-secure-password"
```

### Terraform Variables

Edit `infrastructure/terraform/terraform.tfvars`:

```hcl
# VM configuration
master_count  = 1
master_cpu    = 2
master_memory = 4

worker_count  = 2
worker_cpu    = 2
worker_memory = 4

# Cost optimization
preemptible   = true  # Use preemptible VMs
core_fraction = 50    # Use 50% CPU
```

## 🚀 Advanced Usage

### Scaling Workers

```bash
# Edit terraform.tfvars to increase worker_count
cd infrastructure/terraform
vim terraform.tfvars  # Change worker_count = 3

# Apply changes
terraform apply

# Run Ansible to configure new nodes
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbooks/install-k3s.yml
```

### Adding Custom DAGs

1. Add DAG files to `airflow/dags/`
2. Commit and push to Git
3. Git-sync will automatically update DAGs in cluster

### Custom Monitoring

1. Add Grafana dashboards to `monitoring/dashboards/`
2. Add Prometheus rules to `monitoring/alerts/`
3. Apply via ArgoCD: `kubectl apply -f kubernetes/argocd-apps/`

## 🔧 Troubleshooting

### Common Issues

**Quota exceeded:**
```bash
make check-resources  # Show existing resources
make cleanup-old      # Remove old resources
```

**Pods not starting:**
```bash
make status          # Check cluster status
make events          # Show recent events
make troubleshoot    # Run diagnostics
```

**Can't access services:**
```bash
make info            # Show access information
make health-check    # Check system health
```

### Useful Commands

```bash
# Logs
make logs-airflow    # Airflow scheduler logs
make logs-argocd     # ArgoCD server logs

# Port forwarding
make pf-airflow      # Access Airflow locally
make pf-grafana      # Access Grafana locally
make pf-argocd       # Access ArgoCD locally

# SSH access
make ssh-master      # SSH to master node

# Maintenance
make backup          # Backup configurations
make validate        # Validate configurations
make clean           # Clean temporary files
```

## 📚 Documentation

- [Architecture Details](docs/architecture.md)
- [Deployment Guide](docs/deployment-guide.md)
- [Troubleshooting Guide](docs/troubleshooting.md)

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## ⚠️ Security Considerations

- **SSH Keys**: Never commit SSH keys to repository
- **Secrets**: Use Kubernetes secrets, never hardcode
- **Network**: Configure Security Groups properly
- **Backups**: Regular backup important data

## 📝 License

MIT License - see [LICENSE](LICENSE) file

## 🙏 Acknowledgments

- [k3s](https://k3s.io/) - Lightweight Kubernetes
- [Apache Airflow](https://airflow.apache.org/) - Workflow orchestration
- [ArgoCD](https://argoproj.github.io/cd/) - GitOps deployment
- [Prometheus](https://prometheus.io/) & [Grafana](https://grafana.com/) - Monitoring
- [OTUS](https://otus.ru/) - For excellent Kubernetes course

---

**Note**: This is an educational project. For production use:
- Use Managed Kubernetes service
- Implement proper backup strategy
- Configure high availability
- Set up proper security (RBAC, Network Policies, Secrets management)
- Use external database for Airflow