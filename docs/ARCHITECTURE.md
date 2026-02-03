# OpenEdX on AWS EKS - Architecture Documentation

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                AWS CLOUD REGION                              │
│                                  (us-east-1)                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    SECURITY LAYER                                    │   │
│  ├──────────────────────────────────────────────────────────────────────┤   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │  AWS WAF (Web Application Firewall)                            │ │   │
│  │ │  - Rate limiting (2000 req/5min)                               │ │   │
│  │ │  - AWS Managed Rules (Common Rule Set)                         │ │   │
│  │ │  - SQL Injection & XSS protection                              │ │   │
│  │ │  - IP Reputation blocking                                       │ │   │
│  │ └─────────────────────────────────────────────────────────────────┘ │   │
│  │                             ↓                                         │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │  AWS CloudFront (CDN)                                          │ │   │
│  │ │  - Edge locations worldwide                                     │ │   │
│  │ │  - Static asset caching                                         │ │   │
│  │ │  - Automatic compression                                        │ │   │
│  │ │  - DDoS protection                                              │ │   │
│  │ └─────────────────────────────────────────────────────────────────┘ │   │
│  │                             ↓                                         │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │  AWS Network Load Balancer (NLB)                               │ │   │
│  │ │  - High performance                                             │ │   │
│  │ │  - Ultra-low latency                                            │ │   │
│  │ │  - Connection-based load balancing                              │ │   │
│  │ └─────────────────────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                   ↓                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    APPLICATION LAYER                                 │   │
│  ├──────────────────────────────────────────────────────────────────────┤   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │  AWS EKS Kubernetes Cluster                                    │ │   │
│  │  │  - 3 AZs for high availability                                  │ │   │
│  │  │  - VPC: 10.0.0.0/16                                             │ │   │
│  │  ├─────────────────────────────────────────────────────────────────┤ │   │
│  │  │                                                                 │ │   │
│  │  │  ┌──────────────────────────────────────────────────────────┐ │ │   │
│  │  │  │  ingress-nginx namespace                               │ │ │   │
│  │  │  │  ┌──────────────────────────────────────────────────┐ │ │ │   │
│  │  │  │  │  NGINX Ingress Controller (x2 replicas)         │ │ │ │   │
│  │  │  │  │  - HTTP/2 enabled                                │ │ │ │   │
│  │  │  │  │  - SSL/TLS termination                            │ │ │ │   │
│  │  │  │  │  - Rate limiting & WAF                            │ │ │ │   │
│  │  │  │  │  - Gzip compression                                │ │ │ │   │
│  │  │  │  └──────────────────────────────────────────────────┘ │ │ │   │
│  │  │  └──────────────────────────────────────────────────────────┘ │ │   │
│  │  │                            ↓                                    │ │   │
│  │  │  ┌──────────────────────────────────────────────────────────┐ │ │   │
│  │  │  │  cert-manager namespace                               │ │ │   │
│  │  │  │  ┌──────────────────────────────────────────────────┐ │ │ │   │
│  │  │  │  │  Cert-Manager                                    │ │ │ │   │
│  │  │  │  │  - Let's Encrypt automation                       │ │ │ │   │
│  │  │  │  │  - Certificate renewal                            │ │ │ │   │
│  │  │  │  │  - TLS certificate management                     │ │ │ │   │
│  │  │  │  └──────────────────────────────────────────────────┘ │ │ │   │
│  │  │  └──────────────────────────────────────────────────────────┘ │ │   │
│  │  │                            ↓                                    │ │   │
│  │  │  ┌──────────────────────────────────────────────────────────┐ │ │   │
│  │  │  │  openedx namespace                                     │ │ │   │
│  │  │  ├──────────────────────────────────────────────────────────┤ │ │   │
│  │  │  │                                                          │ │ │   │
│  │  │  │  ┌──────────────────┐ ┌──────────────────┐             │ │ │   │
│  │  │  │  │  OpenEdX LMS     │ │  OpenEdX CMS     │             │ │ │   │
│  │  │  │  │  (3 replicas)    │ │  (2 replicas)    │             │ │ │   │
│  │  │  │  │  - Horizontal    │ │  - Horizontal    │             │ │ │   │
│  │  │  │  │    Pod Autoscaler│ │    Pod Autoscaler│             │ │ │   │
│  │  │  │  │  - Readiness     │ │  - Readiness     │             │ │ │   │
│  │  │  │  │    Probe          │ │    Probe          │             │ │ │   │
│  │  │  │  │  - Liveness      │ │  - Liveness      │             │ │ │   │
│  │  │  │  │    Probe          │ │    Probe          │             │ │ │   │
│  │  │  │  └──────────────────┘ └──────────────────┘             │ │ │   │
│  │  │  │                                                          │ │ │   │
│  │  │  │  ┌──────────────────┐                                  │ │ │   │
│  │  │  │  │  Worker Pods     │                                  │ │ │   │
│  │  │  │  │  (3 replicas)    │                                  │ │ │   │
│  │  │  │  │  - Celery tasks  │                                  │ │ │   │
│  │  │  │  │  - Batch jobs    │                                  │ │ │   │
│  │  │  │  └──────────────────┘                                  │ │ │   │
│  │  │  │                                                          │ │ │   │
│  │  │  │  ┌──────────────────────────────────────────────────┐ │ │ │   │
│  │  │  │  │  Persistent Volumes (EFS)                       │ │ │ │   │
│  │  │  │  │  ┌────────────────┐ ┌────────────────┐         │ │ │ │   │
│  │  │  │  │  │ Static Files   │ │  Media Files   │         │ │ │ │   │
│  │  │  │  │  │ (50GB)         │ │  (100GB)       │         │ │ │ │   │
│  │  │  │  │  └────────────────┘ └────────────────┘         │ │ │ │   │
│  │  │  │  └──────────────────────────────────────────────────┘ │ │ │   │
│  │  │  └──────────────────────────────────────────────────────────┘ │ │   │
│  │  │                            ↓                                    │ │   │
│  │  │  ┌──────────────────────────────────────────────────────────┐ │ │   │
│  │  │  │  monitoring namespace                                  │ │ │   │
│  │  │  │  ┌──────────────────────────────────────────────────┐ │ │ │   │
│  │  │  │  │  Prometheus + Grafana + Fluentd                 │ │ │ │   │
│  │  │  │  │  - Metrics collection                            │ │ │ │   │
│  │  │  │  │  - Visualization dashboards                      │ │ │ │   │
│  │  │  │  │  - Log aggregation                               │ │ │ │   │
│  │  │  │  │  - Alerting                                       │ │ │ │   │
│  │  │  │  └──────────────────────────────────────────────────┘ │ │ │   │
│  │  │  └──────────────────────────────────────────────────────────┘ │ │   │
│  │  │                            ↓                                    │ │   │
│  │  │  ┌──────────────────────────────────────────────────────────┐ │ │   │
│  │  │  │  argocd namespace                                      │ │ │   │
│  │  │  │  ┌──────────────────────────────────────────────────┐ │ │ │   │
│  │  │  │  │  ArgoCD (GitOps)                                │ │ │ │   │
│  │  │  │  │  - Continuous deployment                         │ │ │ │   │
│  │  │  │  │  - Application sync                              │ │ │ │   │
│  │  │  │  │  - Rollback capability                           │ │ │ │   │
│  │  │  │  └──────────────────────────────────────────────────┘ │ │ │   │
│  │  │  └──────────────────────────────────────────────────────────┘ │ │   │
│  │  │                                                                 │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                   ↓                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    DATA LAYER (Managed Services)                     │   │
│  ├──────────────────────────────────────────────────────────────────────┤   │
│  │                                                                       │   │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐        │   │
│  │  │  RDS Aurora    │  │  DocumentDB    │  │  ElastiCache   │        │   │
│  │  │  MySQL         │  │  (MongoDB)     │  │  (Redis)       │        │   │
│  │  │                │  │                │  │                │        │   │
│  │  │ • Multi-AZ     │  │ • Multi-AZ     │  │ • Multi-AZ     │        │   │
│  │  │ • Automated    │  │ • Point-in-time│  │ • AUTH enabled │        │   │
│  │  │   backup       │  │   recovery     │  │ • Encryption   │        │   │
│  │  │ • Encryption   │  │ • Encryption   │  │ • Persistence  │        │   │
│  │  │ • Read replicas│  │ • Replication  │  │                │        │   │
│  │  └────────────────┘  └────────────────┘  └────────────────┘        │   │
│  │                                                                       │   │
│  │  ┌────────────────┐  ┌────────────────┐                            │   │
│  │  │  OpenSearch    │  │  S3 Buckets    │                            │   │
│  │  │  (Elasticsearch)│  │                │                            │   │
│  │  │                │  │ • Static assets│                            │   │
│  │  │ • 3 nodes      │  │ • Backups      │                            │   │
│  │  │ • Encryption   │  │ • Media files  │                            │   │
│  │  │ • Kibana       │  │ • Versioning   │                            │   │
│  │  │ • Fine-grained │  │ • Lifecycle    │                            │   │
│  │  │   access       │  │                │                            │   │
│  │  └────────────────┘  └────────────────┘                            │   │
│  │                                                                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────┐
│  Users                                                    │
│  (Global Access via CloudFront)                          │
└─────────────────────┬──────────────────────────────────┘
                      │ HTTPS
                      ↓
        ┌─────────────────────────────┐
        │  AWS WAF + CloudFront       │
        │  (DDoS Protection & Caching)│
        └──────────┬──────────────────┘
                   │ HTTP/2 + TLS
                   ↓
        ┌─────────────────────────────┐
        │  Network Load Balancer      │
        │  (High Performance Routing) │
        └──────────┬──────────────────┘
                   │ Layer 4
                   ↓
        ┌─────────────────────────────┐
        │  NGINX Ingress Controller   │
        │  (L7 Routing & SSL/TLS Term)│
        └──────────┬──────────────────┘
                   │ Routing
        ┌──────────┴──────────────────────┐
        │                                  │
        ↓ HTTP/1.1                        ↓ HTTP/1.1
   ┌─────────────┐                   ┌─────────────┐
   │ OpenEdX LMS │                   │ OpenEdX CMS │
   │ Containers  │                   │ Containers  │
   └─────────────┘                   └─────────────┘
        │                                  │
        └──────────┬───────────────────────┘
                   │ Connection Pooling
        ┌──────────┴──────────────────┐
        │                              │
        ↓ TCP                         ↓ TCP
   ┌──────────────┐            ┌──────────────┐
   │ RDS Aurora   │            │ DocumentDB   │
   │ (MySQL)      │            │ (MongoDB)    │
   └──────────────┘            └──────────────┘
        
        ↓ TCP                   ↓ TCP
   ┌──────────────┐       ┌──────────────┐
   │ ElastiCache  │       │ OpenSearch   │
   │ (Redis)      │       │ (Elasticsearch)
   └──────────────┘       └──────────────┘

Asynchronous Workflows:

   ┌─────────────┐
   │ Celery Beat │
   │ (Scheduler) │
   └────┬────────┘
        │ Enqueue
        ↓
   ┌──────────────┐
   │ Redis Queue  │
   └────┬─────────┘
        │ Consume
        ↓
   ┌──────────────┐
   │ Worker Pods  │
   │ (Celery)     │
   └────┬─────────┘
        │ Results
        ↓
   ┌──────────────┐
   │ Redis Backend│
   │ (Result Store)
   └──────────────┘
```

## High Availability Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                      AWS REGION (us-east-1)                        │
│                                                                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Availability   │  │  Availability   │  │  Availability   │  │
│  │     Zone 1      │  │     Zone 2      │  │     Zone 3      │  │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────────┤  │
│  │                 │  │                 │  │                 │  │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │
│  │ │  EKS Node   │ │  │ │  EKS Node   │ │  │ │  EKS Node   │ │  │
│  │ │ (c5.2xl)    │ │  │ │ (c5.2xl)    │ │  │ │ (c5.2xl)    │ │  │
│  │ └──────┬──────┘ │  │ └──────┬──────┘ │  │ └──────┬──────┘ │  │
│  │        │        │  │        │        │  │        │        │  │
│  │ ┌──────▼──────┐ │  │ ┌──────▼──────┐ │  │ ┌──────▼──────┐ │  │
│  │ │  Pod LMS    │ │  │ │  Pod LMS    │ │  │ │  Pod LMS    │ │  │
│  │ │  Pod CMS    │ │  │ │  Pod CMS    │ │  │ │  Pod CMS    │ │  │
│  │ │  Pod Worker │ │  │ │  Pod Worker │ │  │ │  Pod Worker │ │  │
│  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │  │
│  │                 │  │                 │  │                 │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│                                                                    │
│                     Database Replication                          │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │                                                           │    │
│  │ RDS Primary (AZ1)  →  RDS Replica (AZ2)  →  Replica(AZ3)│    │
│  │ (Auto Failover)                                          │    │
│  │                                                           │    │
│  │ DocumentDB Primary (AZ1,2,3) - Multi-AZ Replication     │    │
│  │                                                           │    │
│  │ Redis Cluster                                            │    │
│  │ (Master in AZ1, Replica in AZ2, Backup in AZ3)          │    │
│  │                                                           │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                    │
└───────────────────────────────────────────────────────────────────┘

Failover Scenarios:

1. Node Failure:
   - Kubernetes automatically reschedules pods to healthy nodes
   - HPA can trigger scaling if needed
   - Application remains available

2. AZ Failure:
   - RDS: Automatic failover to replica in another AZ (< 2 minutes)
   - DocumentDB: Automatic failover within cluster
   - EKS: Pods redistribute across remaining AZs
   - No data loss guaranteed

3. Database Failure:
   - RDS: Automatic recovery or failover
   - DocumentDB: Automatic failover to replica
   - Redis: Replication provides recovery options
   - Backups enable restore within RPO

4. Complete Region Failure:
   - Requires disaster recovery procedure
   - RTO: 1 hour, RPO: 15 minutes
   - See disaster recovery section in documentation
```

## Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    VPC: 10.0.0.0/16                         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Internet Gateway (IGW)                       │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↑                                   │
│                          │ (Inbound HTTPS from internet)   │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Public SN 1 │  │  Public SN 2 │  │  Public SN 3 │     │
│  │ 10.0.0.0/24  │  │ 10.0.1.0/24  │  │ 10.0.2.0/24  │     │
│  ├──────────────┤  ├──────────────┤  ├──────────────┤     │
│  │ NLB          │  │              │  │              │     │
│  │ NAT GW       │  │              │  │              │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│        ↓                                                     │
│        │ Private Route Table                               │
│        │                                                    │
│  ┌─────▼──────────┐ ┌──────────────┐ ┌──────────────┐     │
│  │ Private SN 1   │ │ Private SN 2 │ │ Private SN 3 │     │
│  │ 10.0.10.0/24   │ │10.0.11.0/24  │ │10.0.12.0/24  │     │
│  ├────────────────┤ ├──────────────┤ ├──────────────┤     │
│  │ EKS Node 1     │ │ EKS Node 2   │ │ EKS Node 3   │     │
│  │ EKS Control    │ │              │ │              │     │
│  │ Plane (Managed)│ │              │ │              │     │
│  ├────────────────┤ ├──────────────┤ ├──────────────┤     │
│  │ RDS Subnet     │ │ RDS Subnet   │ │ RDS Subnet   │     │
│  │ (Secure)       │ │ (Secure)     │ │ (Secure)     │     │
│  └────────────────┘ └──────────────┘ └──────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘

Security Groups:
- EKS Cluster SG: Allows traffic from NLB, inter-node communication
- RDS SG: Allows inbound on 3306 from EKS SG only
- DocumentDB SG: Allows inbound on 27017 from EKS SG only
- ElastiCache SG: Allows inbound on 6379 from EKS SG only
- OpenSearch SG: Allows inbound on 9200,443 from EKS SG only
- EFS SG: Allows inbound on 2049 (NFS) from EKS SG only

VPC Endpoints (to reduce NAT costs):
- S3 Gateway Endpoint: Direct access to S3
- Secrets Manager Interface Endpoint: Direct access to secrets
- Systems Manager Interface Endpoint: Direct access to Parameter Store
```

## Security Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    SECURITY LAYERS                           │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│ 1. PERIMETER SECURITY                                        │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ AWS WAF - Web Application Firewall                  │  │
│    │ - Rate limiting (2000 req/5min per IP)              │  │
│    │ - AWS Managed Rules (Common Rule Set)               │  │
│    │ - Custom rules for API protection                   │  │
│    │ - IP reputation blocking                            │  │
│    │ - Geo-blocking (optional)                           │  │
│    └─────────────────────────────────────────────────────┘  │
│                          ↓                                    │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ DDoS Protection (AWS Shield Standard/Advanced)       │  │
│    │ - Network layer protection                          │  │
│    │ - Application layer protection                      │  │
│    └─────────────────────────────────────────────────────┘  │
│                                                               │
│ 2. TRANSPORT SECURITY                                        │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ TLS 1.2+ Encryption                                │  │
│    │ - Certificate management (Cert-Manager)            │  │
│    │ - Automatic renewal (Let's Encrypt)                │  │
│    │ - HTTP/2 support                                   │  │
│    │ - HSTS headers enforced                            │  │
│    └─────────────────────────────────────────────────────┘  │
│                                                               │
│ 3. NETWORK SECURITY                                          │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ Security Groups & NACLs                            │  │
│    │ - Least privilege access                           │  │
│    │ - VPC segmentation                                 │  │
│    │ - Micro-segmentation with NetworkPolicies          │  │
│    │                                                     │  │
│    │ VPC Endpoints                                      │  │
│    │ - S3, Secrets Manager, Systems Manager             │  │
│    │ - No internet exposure for sensitive calls          │  │
│    └─────────────────────────────────────────────────────┘  │
│                                                               │
│ 4. ACCESS CONTROL                                            │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ IAM & IRSA                                          │  │
│    │ - Service Account to IAM role binding               │  │
│    │ - Fine-grained permissions per workload             │  │
│    │ - No long-lived credentials in containers           │  │
│    │                                                     │  │
│    │ Kubernetes RBAC                                    │  │
│    │ - Role and RoleBinding management                  │  │
│    │ - Namespace isolation                              │  │
│    │ - Pod Security Policies (restricted)               │  │
│    └─────────────────────────────────────────────────────┘  │
│                                                               │
│ 5. DATA PROTECTION                                           │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ Encryption at Rest                                 │  │
│    │ - KMS encryption for EBS volumes                   │  │
│    │ - RDS encryption enabled                           │  │
│    │ - DocumentDB encryption enabled                    │  │
│    │ - S3 encryption (AES-256)                          │  │
│    │                                                     │  │
│    │ Encryption in Transit                              │  │
│    │ - TLS 1.2+ for all inter-service communication     │  │
│    │ - Database connection encryption                   │  │
│    │ - Redis AUTH token + encryption                    │  │
│    └─────────────────────────────────────────────────────┘  │
│                                                               │
│ 6. SECRETS MANAGEMENT                                        │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ AWS Secrets Manager                                │  │
│    │ - Database credentials                             │  │
│    │ - API keys                                         │  │
│    │ - Automatic rotation enabled                       │  │
│    │                                                     │  │
│    │ Kubernetes Secrets                                 │  │
│    │ - etcd encryption with KMS                         │  │
│    │ - RBAC-controlled access                           │  │
│    └─────────────────────────────────────────────────────┘  │
│                                                               │
│ 7. MONITORING & AUDITING                                     │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ CloudTrail - API auditing                          │  │
│    │ - All AWS API calls logged                         │  │
│    │ - Compliance and forensics                         │  │
│    │                                                     │  │
│    │ EKS Control Plane Logs                             │  │
│    │ - API server logs                                  │  │
│    │ - Audit events                                     │  │
│    │ - Controller manager, scheduler logs               │  │
│    │                                                     │  │
│    │ GuardDuty - Threat detection                       │  │
│    │ - Abnormal behavior detection                      │  │
│    │ - Compromised instance identification              │  │
│    └─────────────────────────────────────────────────────┘  │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

## Deployment Pipeline Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Developer Workflow                                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│ 1. Git Repository                                       │
│    ↓ Push to main branch                               │
│                                                          │
│ 2. GitHub Actions / CI Pipeline                        │
│    ├─ Test code                                        │
│    ├─ Build Docker image                               │
│    ├─ Scan for vulnerabilities                         │
│    ├─ Push to ECR                                      │
│    └─ Create release                                   │
│    ↓                                                    │
│                                                          │
│ 3. ArgoCD GitOps                                       │
│    ├─ Monitor Git repository                           │
│    ├─ Sync Kubernetes manifests                        │
│    ├─ Progressive deployment (Canary/Blue-Green)       │
│    ├─ Automated rollback on failure                    │
│    └─ Audit trail of all deployments                  │
│    ↓                                                    │
│                                                          │
│ 4. Kubernetes Cluster                                  │
│    ├─ Rolling update of OpenEdX pods                   │
│    ├─ Health checks during deployment                  │
│    ├─ Pod disruption budgets respected                 │
│    └─ Zero-downtime deployments                        │
│    ↓                                                    │
│                                                          │
│ 5. Production Application                              │
│    ├─ Updated OpenEdX version running                  │
│    ├─ Monitoring alerts enabled                        │
│    └─ Logs captured for analysis                       │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Cost Optimization Strategies

1. **Compute:**
   - Use spot instances for non-critical workloads (30-70% savings)
   - Reserve capacity with Reserved Instances (20-40% savings)
   - Right-size instance types based on actual usage
   - Use Graviton instances for better price/performance

2. **Storage:**
   - S3 Lifecycle policies for automatic archival (30% savings)
   - Use S3 Intelligent-Tiering for variable access patterns
   - EFS bursting for variable workloads
   - Compress backups before storing

3. **Data Transfer:**
   - CloudFront for static assets (50-80% reduction)
   - VPC endpoints for AWS service access (no data transfer costs)
   - S3 transfer acceleration only when needed
   - Regional deployment to minimize data transfer

4. **Databases:**
   - Aurora auto-scaling read replicas
   - DocumentDB on-demand pricing for variable workloads
   - ElastiCache reserved instances for predictable workloads
   - OpenSearch reserved capacity

5. **Networking:**
   - Single NAT gateway in dev/staging (accept availability trade-off)
   - Enable S3 Gateway Endpoint (0 cost vs NAT charges)
   - Use private endpoints for AWS services
   - Optimize inter-AZ traffic patterns

---

**Last Updated:** February 2026
**Architecture Version:** 2.0 (Production Ready)
