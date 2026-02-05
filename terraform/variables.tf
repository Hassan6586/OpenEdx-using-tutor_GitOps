# ADDITIONAL VARIABLES REQUIRED FOR CORRECTED FILES
# =============================================================================

# Networking
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_single_nat_gateway" {
  description = "Use single NAT gateway (cheaper for dev)"
  type        = bool
  default     = false  # Set true for dev, false for production
}

# EKS Cluster
variable "cluster_name" {
  description = "Name of the EKS cluster (without suffix)"
  type        = string
  default     = "openedx"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "min_worker_nodes" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "max_worker_nodes" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

variable "desired_worker_nodes" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

# Database Configuration
variable "mysql_db_name" {
  description = "MySQL database name"
  type        = string
  default     = "openedx"
}

variable "mysql_username" {
  description = "MySQL master username"
  type        = string
  default     = "openedx_admin"
}

variable "mongodb_name" {
  description = "MongoDB database name"
  type        = string
  default     = "openedx"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r5.large"
}

variable "rds_backup_retention" {
  description = "Number of days to retain RDS backups"
  type        = number
  default     = 7
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.r5.large"
}

# OpenSearch
variable "elasticsearch_version" {
  description = "OpenSearch version"
  type        = string
  default     = "2.11"
}

# Monitoring
variable "enable_monitoring" {
  description = "Enable monitoring stack"
  type        = bool
  default     = true
}

# Let's Encrypt
variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificates"
  type        = string
}

# Alerts
variable "alert_email" {
  description = "Email for system alerts"
  type        = string
}

# WAF
variable "trusted_ip_addresses" {
  description = "List of trusted IP addresses for WAF"
  type        = list(string)
  default     = []
}
