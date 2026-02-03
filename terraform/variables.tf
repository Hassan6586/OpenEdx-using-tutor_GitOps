# =============================================================================
# INPUT VARIABLES - OpenEdX on AWS EKS
# =============================================================================

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "openedx"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "argocd_namespace" {
  description = "Namespace to install ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.0.0"
}

variable "enable_single_nat_gateway" {
  description = "Use single NAT gateway to reduce costs (not recommended for production)"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Enable monitoring stack (Prometheus, Grafana)"
  type        = bool
  default     = true
}

# OpenEdX-specific variables
variable "openedx_domain" {
  description = "Domain name for OpenEdX platform"
  type        = string
  default     = "openedx.example.com"
}

variable "openedx_namespace" {
  description = "Kubernetes namespace for OpenEdX"
  type        = string
  default     = "openedx"
}

# Database variables
variable "mysql_db_name" {
  description = "MySQL database name"
  type        = string
  default     = "openedx"
}

variable "mysql_username" {
  description = "MySQL root username"
  type        = string
  default     = "openedx"
  sensitive   = true
}

variable "mongodb_name" {
  description = "MongoDB database name"
  type        = string
  default     = "openedx"
}

variable "elasticsearch_version" {
  description = "Elasticsearch version"
  type        = string
  default     = "8.10"
}

variable "redis_node_type" {
  description = "Redis cache node type"
  type        = string
  default     = "cache.t3.micro"
}

# RDS and cache configuration
variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 100
}

variable "rds_backup_retention" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 30
}

variable "enable_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = true
}

variable "min_worker_nodes" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3
}

variable "max_worker_nodes" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

variable "desired_worker_nodes" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 5
}
