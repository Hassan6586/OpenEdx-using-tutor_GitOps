# OpenEdX on AWS EKS - Quick Start Guide

**5-minute overview to get OpenEdX running on AWS EKS**

## Getting Started (5 Minutes)

### What You Need

- An AWS account (you'll need permission to create resources)
- AWS CLI installed and configured
- Terraform 1.0+, kubectl 1.25+, Helm 3.10+
- A domain name (openedx.example.com or similar)

If something is missing, the deploy script will tell you.

## 🚀 Option 1: Automated Deployment (Recommended)

### Step 1: Configure Environment

```bash
# Clone/Navigate to project
cd /path/to/openEdx-eks

# Copy and edit configuration
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
nano terraform/terraform.tfvars  # edit with your values
```

### Step 2: Deploy

```bash
make setup
```

This takes about 15-20 minutes. It:
- Creates VPC, subnets, security groups
- Spins up EKS cluster
- Sets up RDS, DocumentDB, Redis, Elasticsearch
- Configures everything and deploys OpenEdX
- Verifies it's all working

Go grab coffee.

### Step 3: Access OpenEdX

```bash
# Get LoadBalancer URL
kubectl get svc -n ingress-nginx

# You should see something like:
# openedx-lms-nlb-xxxxx.elb.amazonaws.com

# Configure DNS:
# Point your domain to the LoadBalancer URL in Route53 or your DNS provider

# Access at:
# https://openedx.example.com
```

---

## 🔧 Option 2: Step-by-Step Manual Deployment

### Step 1: Initialize Terraform

```bash
cd terraform

# Download and initialize Terraform providers
terraform init

# Validate configuration
terraform validate
```

### Step 2: Plan Infrastructure

```bash
# Review what will be created
terraform plan -out=tfplan

# Expected resources:
# - 1 VPC with 6 subnets (3 public, 3 private)
# - 1 EKS cluster with 2 node groups
# - 1 RDS Aurora MySQL cluster
# - 1 DocumentDB cluster
# - 1 ElastiCache Redis cluster
# - 1 OpenSearch domain
# - 1 EFS file system
# - 2 S3 buckets
# - 1 CloudFront distribution
# - 1 WAF Web ACL
```

### Step 3: Apply Infrastructure

```bash
# Create AWS resources
terraform apply tfplan

# ⏳ Takes ~15 minutes

# Save outputs
terraform output > outputs.json

# Note the important outputs:
# - cluster_endpoint
# - rds_endpoint
# - opensearch_domain_endpoint
```

### Step 4: Configure Kubernetes Access

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --region us-east-1 \
  --name openedx

# Verify connection
kubectl get nodes
```

### Step 5: Deploy OpenEdX

```bash
cd ../scripts

# Run deployment script
bash deploy.sh

# The script will:
# 1. Check prerequisites
# 2. Deploy NGINX Ingress Controller
# 3. Deploy Cert-Manager
# 4. Deploy monitoring stack (Prometheus, Grafana)
# 5. Create OpenEdX namespace
# 6. Configure database secrets
# 7. Deploy LMS, CMS, and Worker pods
# 8. Set up HPA and networking policies
# 9. Verify all deployments
```

### Step 6: Verify Deployment

```bash
# Check pod status
kubectl get pods -n openedx

# Expected output:
# openedx-lms-xxxxx         1/1     Running
# openedx-cms-xxxxx         1/1     Running
# openedx-worker-xxxxx      1/1     Running

# Check services
kubectl get svc -n openedx

# Get LoadBalancer URL
kubectl get svc -n ingress-nginx
```

---

## 📊 Common Operations

### View Logs

```bash
# LMS logs
make logs

# CMS logs
make logs-cms

# Worker logs
make logs-worker

# View Kubernetes events
kubectl get events -n openedx
```

### Monitor System

```bash
# Access Grafana dashboards
make monitoring

# Username: admin
# Password: [check output from command]
# Access: http://localhost:3000
```

### Scale Services

```bash
# Scale LMS to 5 replicas
kubectl scale deployment openedx-lms --replicas=5 -n openedx

# HPA will scale between 3-10 automatically based on CPU/Memory
kubectl get hpa -n openedx
```

### Execute Database Migration

```bash
# Connect to LMS pod
kubectl exec -it deployment/openedx-lms -n openedx -- bash

# Run migrations
./manage.py migrate --database=default
./manage.py collectstatic --noinput
```

### Backup Data

```bash
# Create backup
make backup

# Backups stored in:
# - AWS S3 bucket (encrypted)
# - Local backups/ directory (7-day retention)
```

### Restore from Backup

```bash
# Restore latest backup
make restore

# Or restore specific backup
make restore  # Enter backup date when prompted (YYYYMMDD_HHMMSS)
```

---

## 🔒 Security Configuration

### SSL/TLS Certificates

Certificates are automatically issued and renewed by Let's Encrypt via Cert-Manager.

```bash
# View certificates
kubectl get certificates -n openedx

# Manual renewal if needed
kubectl delete certificate openedx-tls -n openedx
# Certificate will be auto-reissued within minutes
```

### Update Database Passwords

```bash
# Edit Kubernetes secret
kubectl edit secret openedx-db-credentials -n openedx

# Values are base64 encoded
# After editing, redeploy pods:
kubectl rollout restart deployment/openedx-lms -n openedx
```

### Configure WAF Rules

```bash
# WAF is configured in AWS Console
# Go to: AWS Console → WAF & Shield → Web ACLs
# 
# Current rules:
# - Rate limiting: 2000 requests per 5 minutes
# - AWS Managed Rules for common attacks
# - Custom rules can be added
```

---

## 🔍 Troubleshooting

### Pods not starting?

```bash
# Check pod events
kubectl describe pod [pod-name] -n openedx

# Check pod logs
kubectl logs [pod-name] -n openedx

# Check for CrashLoopBackOff
kubectl get pods -n openedx
```

### Database connection errors?

```bash
# Test MySQL connection
kubectl run -it --rm mysql-test --image=mysql:8.0 --restart=Never -- \
  mysql -h[RDS-ENDPOINT] -u[username] -p[password]

# Check ConfigMap
kubectl get configmap openedx-config -n openedx -o yaml

# Check Secrets
kubectl get secret openedx-db-credentials -n openedx -o yaml
```

### Ingress not working?

```bash
# Check ingress status
kubectl get ingress -n openedx

# Check NGINX ingress controller
kubectl get pods -n ingress-nginx

# Check Cert-Manager
kubectl get pods -n cert-manager
kubectl describe certificate openedx-tls -n openedx
```

### High CPU/Memory usage?

```bash
# View resource usage
kubectl top nodes
kubectl top pods -n openedx

# Check HPA status
kubectl get hpa -n openedx
kubectl describe hpa openedx-lms -n openedx

# Scale if needed
kubectl scale deployment openedx-lms --replicas=5 -n openedx
```

### DNS not resolving?

```bash
# Test DNS from pod
kubectl exec -it deployment/openedx-lms -n openedx -- nslookup openedx.example.com

# Verify Route53 records
aws route53 list-resource-record-sets --hosted-zone-id [ZONE-ID]

# Or check with external DNS checker
nslookup openedx.example.com
```

---

## 📚 Documentation References

| Document | Purpose |
|----------|---------|
| [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) | Comprehensive deployment & operations guide |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Detailed technical architecture |
| [README.md](README.md) | Project overview and structure |
| [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) | Project completion summary |

---

## 💰 Cost Estimation

### Development Environment
- EKS: $73/month
- RDS (t3.small): $47/month  
- DocumentDB: $55/month
- ElastiCache: $17/month
- OpenSearch: $145/month
- **Total: ~$340/month**

### Production Environment
- EKS + Multi-AZ: $350/month
- RDS (db.r5.large): $1,200/month
- DocumentDB: $200/month
- ElastiCache: $100/month
- OpenSearch: $1,000/month
- **Total: ~$3,300/month**

---

## 🎯 Next Steps

1. **Day 1:** Deploy infrastructure and verify access
2. **Day 2:** Configure authentication providers (Google, Microsoft, etc.)
3. **Day 3:** Customize branding and platform settings
4. **Day 4:** Upload courses and test LMS functionality
5. **Day 5:** Configure backups and test restore procedures

---

## 📞 Support

### Quick Checks

```bash
# Overall cluster health
make status

# Database connectivity
make db-status

# Recent logs
kubectl logs -n openedx -l app=openedx --tail=50 -f
```

### Getting Help

1. Check [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) troubleshooting section
2. Review Kubernetes events: `kubectl get events -n openedx`
3. Check application logs for errors
4. Verify AWS resources in AWS Console

---

## ✨ Tips & Tricks

```bash
# Get all information at once
make status

# Port forward to services
kubectl port-forward svc/openedx-lms 8000:8000 -n openedx

# Execute command in pod
kubectl exec deployment/openedx-lms -n openedx -- manage.py help

# Watch deployment rollout
kubectl rollout status deployment/openedx-lms -n openedx -w

# Get shell in pod
kubectl exec -it deployment/openedx-lms -n openedx -- /bin/bash
```

---

**Ready to deploy? Run `make setup` now!** 🚀
