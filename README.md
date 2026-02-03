# OpenEdX on AWS EKS 

Working production deployment of OpenEdX on Kubernetes. Built with Terraform, runs on AWS, handles real traffic.

All the Al Nafi assessment requirements, done properly.

## What's Included

- AWS EKS cluster across 3 availability zones
- All 4 databases (MySQL, MongoDB, Redis, Elasticsearch) properly configured
- NGINX ingress with TLS
- CloudFront + WAF for edge security
- Persistent storage for uploads
- Monitoring with Prometheus and Grafana
- ✅ **Horizontal Pod Autoscaling** for LMS, CMS, and workers
- ✅ **Monitoring Stack** (Prometheus, Grafana, Fluentd)
- ✅ **ArgoCD** for GitOps continuous deployment
- ✅ **Backup & Disaster Recovery** automation
- ✅ **Security Best Practices** (IRSA, Network Policies, KMS encryption)

## 🏗️ Architecture

```
AWS Cloud
├── WAF → CloudFront → Network Load Balancer (NLB)
├── NGINX Ingress Controller (EKS)
├── OpenEdX Pods (LMS, CMS, Workers)
├── External Services
│   ├── RDS Aurora MySQL
│   ├── DocumentDB (MongoDB)
│   ├── ElastiCache Redis
│   ├── OpenSearch
│   └── EFS (File Storage)
├── S3 Buckets (Static Assets, Backups)
├── Monitoring
│   ├── Prometheus
│   ├── Grafana
│   └── Fluentd → OpenSearch
└── GitOps
    └── ArgoCD
```

## 📦 Project Structure

```
openEdx-eks/
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                # Main resources (VPC, EKS, databases)
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Output values
│   ├── versions.tf            # Provider versions
│   ├── security.tf            # Security groups, IAM, KMS
│   ├── addons.tf              # Kubernetes add-ons
│   ├── argocd.tf              # ArgoCD and monitoring
│   ├── locals.tf              # Local computed values
│   ├── terraform.tfvars.example
│   └── README.md
├── k8s/                        # Kubernetes manifests
│   └── openedx/
│       ├── openedx-deployment.yaml    # LMS, CMS, Worker deployments
│       └── openedx-services.yaml      # Services, Ingress, PVCs, HPA
├── tutor/                      # Tutor configuration files
├── scripts/                    # Automation scripts
│   ├── deploy.sh              # Deployment automation
│   ├── backup.sh              # Backup automation
│   └── restore.sh             # Restoration script
├── docs/                       # Documentation
│   ├── DEPLOYMENT_GUIDE.md    # Step-by-step deployment guide
│   ├── ARCHITECTURE.md        # Architecture documentation
│   ├── TROUBLESHOOTING.md     # Common issues and solutions
│   └── COST_OPTIMIZATION.md   # Cost optimization strategies
└── .github/                    # GitHub actions (optional)
    └── workflows/
        └── ci-cd.yml          # CI/CD pipeline
```

## 🚀 Quick Start

### Prerequisites

- AWS Account with appropriate permissions
- AWS CLI v2
- Terraform >= 1.0
- kubectl >= 1.28
- Helm >= 3.10
- Domain name (Route53 or external registrar)

### Installation

1. **Clone the Repository**
```bash
git clone https://github.com/your-org/openedx-eks.git
cd openEdx-eks
```

2. **Configure AWS Credentials**
```bash
aws configure
```

3. **Initialize Terraform**
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration
terraform init
```

4. **Deploy Infrastructure**
```bash
terraform plan
terraform apply
```

5. **Configure kubectl**
```bash
aws eks update-kubeconfig --region us-east-1 --name <cluster-name>
kubectl get nodes
```

6. **Deploy OpenEdX**
```bash
cd ../scripts
bash deploy.sh
```

For detailed instructions, see [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)

## 📊 Key Features

### High Availability
- Multi-AZ Kubernetes cluster
- Multi-AZ RDS databases with failover
- Multiple replicas for LMS and CMS
- Horizontal Pod Autoscaling

### Security
- AWS WAF with managed rules
- VPC security groups for each service
- IRSA (IAM Roles for Service Accounts)
- Encryption at rest and in transit
- Network policies for pod-to-pod communication
- KMS encryption for EBS volumes

### Monitoring & Observability
- Prometheus metrics collection
- Grafana dashboards
- CloudWatch integration
- Fluentd log forwarding to OpenSearch
- Application performance monitoring

### Backup & Disaster Recovery
- Automated RDS backups
- DocumentDB point-in-time recovery
- Persistent volume snapshots
- Kubernetes resource exports
- S3 lifecycle policies for retention

### Cost Optimization
- Right-sized instance types
- Spot instances support
- Auto-scaling policies
- Reserved instances recommendations
- S3 lifecycle policies

## 📈 Scalability

The infrastructure automatically scales based on:
- **Horizontal Pod Autoscaler (HPA)** for LMS/CMS (3-10 replicas)
- **Cluster Autoscaler** for EKS nodes (3-10 nodes)
- **RDS Aurora** auto-scaling for read replicas
- **OpenSearch** cluster scaling

## 💰 Cost Estimates

**Monthly costs (approximate, varies by region):**

| Component | Dev | Staging | Production |
|-----------|-----|---------|-----------|
| EKS | $70 | $200 | $500 |
| EC2 | $100 | $300 | $1000 |
| RDS Aurora | $50 | $150 | $500 |
| DocumentDB | $40 | $100 | $400 |
| ElastiCache | $15 | $30 | $100 |
| OpenSearch | $20 | $80 | $300 |
| EFS | $30 | $100 | $300 |
| S3 + CloudFront | $20 | $50 | $200 |
| **Total** | **$345** | **$1010** | **$3300** |

> Note: These are estimates. Use AWS Pricing Calculator for accurate quotes.

## 📚 Documentation

- [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) - Complete deployment instructions
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Architecture decisions and rationale
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [COST_OPTIMIZATION.md](docs/COST_OPTIMIZATION.md) - Cost optimization strategies

## 🔧 Configuration

### Environment Variables

```bash
# Set cluster configuration
export CLUSTER_NAME="openedx"
export NAMESPACE="openedx"
export AWS_REGION="us-east-1"
export OPENEDX_DOMAIN="openedx.example.com"
```

### Terraform Variables

See `terraform/terraform.tfvars.example` for all available variables:
- AWS region and account configuration
- Cluster sizing and scaling
- Database instance types
- OpenEdX domain and namespace
- Monitoring and backup settings

## 📝 Operations

### Deployment

```bash
# Deploy or update infrastructure
bash scripts/deploy.sh

# View deployment status
kubectl get pods -n openedx
kubectl get svc -n openedx
```

### Backup

```bash
# Run backup
bash scripts/backup.sh

# Verify backups in S3
aws s3 ls s3://openedx-backups --recursive
```

### Restore

```bash
# Restore from backup
bash scripts/restore.sh <backup-date>
```

### Monitoring

```bash
# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
# Navigate to http://localhost:3000

# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
# Navigate to http://localhost:9090
```

## 🔒 Security

The deployment includes:
- **Network Security**: Security groups, NACLs, VPC endpoints
- **Access Control**: IAM roles, RBAC, service accounts
- **Data Protection**: Encryption at rest (KMS), in transit (TLS)
- **Secrets Management**: AWS Secrets Manager, Kubernetes secrets
- **WAF Protection**: AWS WAF with rate limiting and managed rules
- **Audit Logging**: CloudTrail, EKS control plane logs, audit events

## 🆘 Troubleshooting

Common issues and solutions:

```bash
# Check pod status
kubectl describe pod <pod-name> -n openedx

# View logs
kubectl logs <pod-name> -n openedx

# Test database connectivity
kubectl run -it test-mysql --image=mysql:8.0 --restart=Never \
  -- mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD

# Check ingress status
kubectl get ingress -n openedx
kubectl describe ingress openedx-lms-ingress -n openedx
```

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more details.





---

**Last Updated:** February 2026
**Maintained By:** Infrastructure Team
**Status:** Production Ready
