# OpenEdX Deployment on AWS EKS

This guide covers how to deploy and operate OpenEdX on AWS. It's organized by topic, not by step-by-step order, so you can skip around.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Infrastructure Setup](#infrastructure-setup)
- [Database Configuration](#database-configuration)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Network and Security](#network-and-security)
- [Monitoring and Logging](#monitoring-and-logging)
- [Backup and Disaster Recovery](#backup-and-disaster-recovery)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

### How Traffic Flows

1. **WAF** blocks bad requests at the edge
2. **CloudFront** caches static files
3. **NLB** (Network Load Balancer) distributes traffic to Kubernetes
4. **NGINX** ingress controller routes to services
5. **OpenEdX pods** (LMS, CMS, Workers) handle requests
6. **External databases** (RDS, DocumentDB, ElastiCache, OpenSearch) store data

### Key Design Decisions

- **Databases outside Kubernetes** - RDS, DocumentDB, ElastiCache, OpenSearch are all AWS managed services. They handle their own failover and backups.
- **Stateless applications** - LMS and CMS pods are interchangeable. If one dies, others keep serving.
- **Workers separate** - Celery workers process background tasks independently.
- **Storage on EFS** - Uploads and static files go to Elastic File System. Survives pod restarts.
- **OIDC for IRSA** - Pods assume IAM roles instead of using credentials in the container.

│  │  │  - Media files                   │               │   │
│  │  └──────────────────────────────────┘               │   │
│  └──────────────────────────────────────────────────────┘   │
│                         ↓                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         External AWS Managed Services                │   │
│  ├──────────────────────────────────────────────────────┤   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐             │   │
│  │  │ RDS MySQL│ │DocumentDB│ │ElastiCache│            │   │
│  │  │ (Aurora) │ │(MongoDB) │ │ (Redis)  │             │   │
│  │  └──────────┘ └──────────┘ └──────────┘             │   │
│  │  ┌──────────┐ ┌──────────┐                          │   │
│  │  │OpenSearch│ │S3 Buckets│                          │   │
│  │  └──────────┘ └──────────┘                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required Tools
- AWS CLI v2 or higher
- Terraform >= 1.0
- kubectl >= 1.28
- Helm >= 3.10
- Docker (for building custom images)
- Git
- jq (for JSON processing)

### AWS Requirements
- AWS Account with appropriate IAM permissions
- VPC and subnet configuration ready
- Domain name registered and managed in Route53 or external registrar
- SSL certificates (can be auto-generated with Let's Encrypt)

### Sizing Recommendations

**Development Environment:**
- EKS: 3 nodes (t3.large)
- MySQL: db.t3.micro
- MongoDB: db.t3.small
- Redis: cache.t3.micro
- OpenSearch: 1 node (t3.small.search)

**Production Environment:**
- EKS: 5-10 nodes (c5.2xlarge)
- MySQL: db.r5.2xlarge (multi-AZ)
- MongoDB: db.r5.2xlarge (multi-AZ)
- Redis: cache.r6g.xlarge (with replication)
- OpenSearch: 3 nodes (m5.large.search) with dedicated master

## Infrastructure Setup

### Step 1: Clone Repository and Initialize Terraform

```bash
# Clone the repository
git clone <repository-url>
cd openEdx-eks

# Initialize Terraform
cd terraform
terraform init

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
aws_region           = "us-east-1"
cluster_name         = "openedx"
environment          = "prod"
kubernetes_version   = "1.33"
openedx_domain       = "openedx.yourdomain.com"
enable_monitoring    = true
enable_single_nat_gateway = false  # Production
min_worker_nodes     = 3
max_worker_nodes     = 10
desired_worker_nodes = 5
EOF
```

### Step 2: Deploy Infrastructure with Terraform

```bash
# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=tfplan

# Apply configuration
terraform apply tfplan

# Save outputs
terraform output > outputs.json
```

### Step 3: Configure kubectl Access

```bash
# Update kubeconfig
aws eks update-kubeconfig \
    --region $(terraform output -raw aws_region) \
    --name $(terraform output -raw cluster_name)

# Verify cluster access
kubectl get nodes
kubectl get pods -A
```

## Database Configuration

### RDS MySQL (Aurora)

The Terraform configuration creates an Aurora MySQL cluster with:
- Multi-AZ deployment
- Automatic backups (30 days retention)
- Enhanced monitoring
- Automated failover
- Read replicas

**Connection Details:**
```bash
# Retrieve endpoint
MYSQL_HOST=$(terraform output -raw rds_mysql_endpoint)
MYSQL_USER=$(terraform output -raw mysql_username)
MYSQL_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id openedx/database \
    --query 'SecretString' | jq -r '.mysql.password')
```

### DocumentDB (MongoDB Compatible)

DocumentDB provides MongoDB compatibility with:
- Multi-AZ replication
- Point-in-time recovery
- Encryption at rest and in transit

```bash
MONGODB_HOST=$(terraform output -raw documentdb_mongodb_endpoint)
MONGODB_PORT=$(terraform output -raw documentdb_mongodb_port)
```

### ElastiCache Redis

Redis is configured for:
- High availability with multi-AZ
- AUTH token for security
- Encryption at rest and in transit
- CloudWatch monitoring

```bash
REDIS_HOST=$(terraform output -raw elasticache_redis_endpoint)
REDIS_PORT=$(terraform output -raw elasticache_redis_port)
REDIS_TOKEN=$(aws secretsmanager get-secret-value \
    --secret-id openedx/database \
    --query 'SecretString' | jq -r '.redis.token')
```

### OpenSearch (Elasticsearch)

OpenSearch cluster is configured with:
- 3 nodes minimum for production
- Encryption at rest and in transit
- VPC endpoint
- Fine-grained access control

```bash
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_domain_endpoint)
```

## Kubernetes Deployment

### Step 1: Deploy Ingress and Cert-Manager

```bash
cd ../scripts
chmod +x deploy.sh

# Deploy NGINX Ingress Controller
bash deploy.sh

# Or manually:
helm repo add nginx-stable https://helm.nginx.com/stable
helm install nginx-ingress nginx-stable/nginx-ingress \
    --namespace ingress-nginx \
    --create-namespace
```

### Step 2: Install ArgoCD for GitOps

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --set server.service.type=LoadBalancer
```

### Step 3: Deploy OpenEdX with Kubernetes Manifests

```bash
# Create namespace and secrets
kubectl create namespace openedx

# Create database credentials secret
kubectl create secret generic openedx-db-credentials \
    --from-literal=mysql_username=$MYSQL_USER \
    --from-literal=mysql_password=$MYSQL_PASSWORD \
    --from-literal=mongodb_username=openedx \
    --from-literal=mongodb_password=$MONGODB_PASSWORD \
    --from-literal=redis_auth_token=$REDIS_TOKEN \
    -n openedx

# Create ConfigMap
kubectl create configmap openedx-config \
    --from-literal=MYSQL_HOST=$MYSQL_HOST \
    --from-literal=MONGODB_HOST=$MONGODB_HOST \
    --from-literal=REDIS_HOST=$REDIS_HOST \
    --from-literal=OPENSEARCH_HOST=$OPENSEARCH_ENDPOINT \
    -n openedx

# Apply manifests
kubectl apply -f k8s/openedx/openedx-deployment.yaml
kubectl apply -f k8s/openedx/openedx-services.yaml

# Verify deployment
kubectl get pods -n openedx
kubectl get svc -n openedx
```

## Network and Security

### SSL/TLS Configuration

Let's Encrypt certificates are automatically managed through Cert-Manager:

```bash
# Verify certificate issuance
kubectl get certificate -n openedx

# Check certificate details
kubectl describe certificate openedx-tls -n openedx
```

### AWS WAF Rules

WAF is configured with:
- Rate limiting (2000 requests per 5 minutes)
- AWS Managed Rules (Common Rule Set)
- SQL injection and XSS protection
- IP reputation blocking

Monitor WAF:
```bash
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1
```

### CloudFront Distribution

Static assets are served through CloudFront with:
- Edge locations worldwide
- Automatic cache invalidation
- Compression enabled
- Security headers

```bash
# Get CloudFront distribution
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront get-distribution --id $DISTRIBUTION_ID
```

### Network Policies

Network policies restrict traffic:
- Ingress only from NGINX ingress controller
- Egress to databases, Redis, and external services
- Pod-to-pod communication within namespace

## Monitoring and Logging

### Prometheus and Grafana

Monitoring stack includes:
- Prometheus for metrics collection
- Grafana for visualization
- Alert manager for notifications

```bash
# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Default credentials
# Username: admin
# Password: (check from secret)
kubectl get secret -n monitoring prometheus-stack-grafana \
    -o jsonpath='{.data.admin-password}' | base64 -d
```

### Fluentd and OpenSearch

Logs are forwarded to OpenSearch:
- Container logs collected by Fluentd
- Indexed in OpenSearch
- Visualized in Kibana

```bash
# Access Kibana
KIBANA_URL=$(terraform output -raw opensearch_kibana_endpoint)
# Navigate to: https://$KIBANA_URL
```

### CloudWatch Logs

AWS CloudWatch receives logs from:
- EKS Cluster logs (API server, audit, controller manager)
- RDS logs (error, slowquery, general)
- Lambda functions

## Backup and Disaster Recovery

### Automated Backups

Backup strategy includes:
- RDS automated backups (30 days retention)
- DocumentDB continuous backup
- ElastiCache cluster snapshots
- Persistent volume snapshots
- Kubernetes resource exports to S3

```bash
# Run backup script
bash scripts/backup.sh

# Monitor S3 backups
aws s3 ls s3://$(terraform output -raw s3_backup_bucket) --recursive
```

### Disaster Recovery Plan

**RTO (Recovery Time Objective):** 1 hour
**RPO (Recovery Point Objective):** 15 minutes

Recovery steps:
1. Restore RDS cluster from backup
2. Restore MongoDB from point-in-time backup
3. Restore persistent volumes from snapshots
4. Redeploy Kubernetes manifests
5. Verify application connectivity

```bash
# Example RDS restore
aws rds restore-db-cluster-from-snapshot \
    --db-cluster-identifier openedx-restored \
    --snapshot-identifier <snapshot-id> \
    --engine aurora-mysql
```

## Troubleshooting

### Common Issues

#### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n openedx

# Check logs
kubectl logs <pod-name> -n openedx

# Check resource constraints
kubectl describe node
kubectl top nodes
kubectl top pods -n openedx
```

#### Database Connection Issues

```bash
# Test MySQL connectivity
kubectl run mysql-client --image=mysql:8.0 -it --rm --restart=Never \
    -- mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD -e "SELECT VERSION();"

# Test MongoDB connectivity
kubectl run mongodb-client --image=mongo:latest -it --rm --restart=Never \
    -- mongosh "mongodb+srv://openedx:$MONGODB_PASSWORD@$MONGODB_HOST/"

# Test Redis connectivity
kubectl run redis-client --image=redis:latest -it --rm --restart=Never \
    -- redis-cli -h $REDIS_HOST -a $REDIS_TOKEN PING
```

#### Ingress Not Working

```bash
# Check ingress
kubectl get ingress -n openedx
kubectl describe ingress openedx-lms-ingress -n openedx

# Check NGINX controller
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Check cert-manager
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
```

#### HPA Not Scaling

```bash
# Check HPA status
kubectl get hpa -n openedx
kubectl describe hpa openedx-lms-hpa -n openedx

# Check metrics
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/openedx/pods/*/cpu_usage | jq .

# Ensure metrics-server is running
kubectl get deployment metrics-server -n kube-system
```

### Performance Tuning

```bash
# Check node capacity
kubectl describe node

# Monitor resource usage
kubectl top nodes
kubectl top pods -n openedx

# Adjust HPA thresholds if needed
kubectl edit hpa openedx-lms-hpa -n openedx
```

## Maintenance Tasks

### Scaling Operations

```bash
# Scale deployment manually
kubectl scale deployment openedx-lms --replicas=5 -n openedx

# Update node group size
terraform apply -var="desired_worker_nodes=10" -auto-approve

# Update Terraform state
terraform refresh
```

### Updates and Patches

```bash
# Update OpenEdX images
kubectl set image deployment/openedx-lms \
    lms=openedx/lms:v15.0 -n openedx

# Rollback deployment
kubectl rollout undo deployment/openedx-lms -n openedx

# Check rollout history
kubectl rollout history deployment/openedx-lms -n openedx
```

## Support and Additional Resources

- [OpenEdX Documentation](https://edx.readthedocs.io/)
- [Tutor Documentation](https://docs.tutor.overhq.com/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Cost Optimization

To reduce costs:

1. **Development Environment:**
   - Use smaller instance types (t3.medium)
   - Single NAT gateway
   - Reserve less capacity

2. **Spot Instances:**
   - Use EC2 Spot Instances for non-critical workloads
   - Configure node groups with mixed capacity

3. **Reserved Instances:**
   - Purchase 1-3 year reservations for stable workloads
   - Combine on-demand and spot instances

4. **Auto-scaling:**
   - Configure cluster autoscaler
   - Use appropriate scaling policies

5. **Storage:**
   - Use lifecycle policies for S3 and backups
   - Archive old logs to Glacier

## Security Considerations

1. **Network Security:**
   - Enable VPC Flow Logs
   - Use security groups effectively
   - Enable GuardDuty for threat detection

2. **Access Control:**
   - Use IAM roles for service accounts (IRSA)
   - Implement RBAC policies
   - Enable audit logging

3. **Data Protection:**
   - Enable encryption at rest and in transit
   - Use AWS KMS for key management
   - Implement database encryption

4. **Compliance:**
   - Regular security audits
   - Enable CloudTrail for API logging
   - Implement encryption and access controls
