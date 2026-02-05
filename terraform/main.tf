# OPENEDX ON AWS EKS - INFRASTRUCTURE (CORRECTED)
# =============================================================================
#
# This sets up everything needed to run OpenEdX in production on AWS:
# - VPC across 3 availability zones
# - EKS cluster for Kubernetes
# - RDS Aurora MySQL, DocumentDB, ElastiCache, OpenSearch
# - Security groups, load balancers, storage
# - Monitoring and logging infrastructure
#
# Deploy with: terraform apply
# Takes about 15-20 minutes on first run

# =============================================================================
# LOCAL VALUES AND DATA SOURCES
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# Local computed values
locals {
  # Cluster configuration with unique suffix to avoid conflicts
  cluster_name = "${var.cluster_name}-${random_string.suffix.result}"
  
  # Network configuration
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 10)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  
  # Common tags applied to all resources
  common_tags = {
    Environment = var.environment
    Project     = "OpenEdX-LMS"
    ManagedBy   = "terraform"
    CreatedBy   = "Platform Team"
    Owner       = data.aws_caller_identity.current.user_id
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  }
  
  # Kubernetes subnet tags
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
  
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

# =============================================================================
# VPC CONFIGURATION
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  # NAT for private subnets
  enable_nat_gateway = true
  single_nat_gateway = var.enable_single_nat_gateway

  # Internet Gateway
  create_igw = true

  # Enable DNS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Manage default resources
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${var.cluster_name}-default-nacl" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${var.cluster_name}-default-rt" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${var.cluster_name}-default-sg" }

  # Tag subnets for EKS
  public_subnet_tags  = merge(local.common_tags, local.public_subnet_tags)
  private_subnet_tags = merge(local.common_tags, local.private_subnet_tags)

  tags = local.common_tags
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

resource "aws_security_group" "rds_sg" {
  name        = "${local.cluster_name}-rds-sg"
  description = "Security group for RDS MySQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.retail_app_eks.cluster_security_group_id]
    description     = "MySQL from EKS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-rds-sg" })
}

resource "aws_security_group" "elasticache_sg" {
  name        = "${local.cluster_name}-elasticache-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.retail_app_eks.cluster_security_group_id]
    description     = "Redis from EKS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-elasticache-sg" })
}

resource "aws_security_group" "documentdb_sg" {
  name        = "${local.cluster_name}-documentdb-sg"
  description = "Security group for DocumentDB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [module.retail_app_eks.cluster_security_group_id]
    description     = "DocumentDB from EKS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-documentdb-sg" })
}

resource "aws_security_group" "opensearch_sg" {
  name        = "${local.cluster_name}-opensearch-sg"
  description = "Security group for OpenSearch"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.retail_app_eks.cluster_security_group_id]
    description     = "HTTPS from EKS"
  }

  ingress {
    from_port       = 9200
    to_port         = 9200
    protocol        = "tcp"
    security_groups = [module.retail_app_eks.cluster_security_group_id]
    description     = "OpenSearch HTTP from EKS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-opensearch-sg" })
}

resource "aws_security_group" "efs_sg" {
  name        = "${local.cluster_name}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.retail_app_eks.cluster_security_group_id]
    description     = "NFS from EKS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-efs-sg" })
}

# =============================================================================
# EKS CLUSTER CONFIGURATION
# =============================================================================

module "retail_app_eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  # Cluster access
  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  enable_cluster_creator_admin_permissions = true

  # Network
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # KMS encryption
  create_kms_key                      = true
  kms_key_description                 = "EKS cluster ${local.cluster_name} encryption key"
  kms_key_deletion_window_in_days     = 7
  enable_kms_key_rotation             = true

  # Logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Managed node groups
  eks_managed_node_groups = {
    main = {
      name            = "${local.cluster_name}-node-group"
      use_name_prefix = true
      capacity_type   = "ON_DEMAND"
      disk_size       = 100

      min_size     = var.min_worker_nodes
      max_size     = var.max_worker_nodes
      desired_size = var.desired_worker_nodes

      instance_types = ["t3.large", "t3.xlarge"]

      labels = {
        Environment = var.environment
        Component   = "openedx"
      }

      tags = merge(local.common_tags, {
        "NodeGroup" = "main"
      })
    }

    compute = {
      name            = "${local.cluster_name}-compute-group"
      use_name_prefix = true
      capacity_type   = "ON_DEMAND"
      disk_size       = 100

      min_size     = 1
      max_size     = 5
      desired_size = 2

      instance_types = ["c5.2xlarge"]

      labels = {
        Environment = var.environment
        Component   = "compute"
        Workload    = "heavy"
      }

      taints = [{
        key    = "workload"
        value  = "compute"
        effect = "NoSchedule"
      }]

      tags = merge(local.common_tags, {
        "NodeGroup" = "compute"
      })
    }
  }

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }

    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      most_recent = true
    }
  }

  tags = local.common_tags
}

# =============================================================================
# RANDOM PASSWORDS
# =============================================================================

resource "random_password" "mysql_password" {
  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "mongodb_password" {
  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "redis_auth_token" {
  length  = 64
  special = false  # Redis auth tokens work better without special chars
}

# =============================================================================
# DB SUBNET GROUP
# =============================================================================

resource "aws_db_subnet_group" "openedx" {
  name       = "${local.cluster_name}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-db-subnet" })
}

# =============================================================================
# RDS MySQL Cluster (Aurora)
# =============================================================================

resource "aws_rds_cluster" "openedx_mysql" {
  cluster_identifier      = "${local.cluster_name}-mysql"
  engine                  = "aurora-mysql"
  engine_version          = "8.0.mysql_aurora.3.04.0"
  availability_zones      = local.azs
  database_name           = var.mysql_db_name
  master_username         = var.mysql_username
  master_password         = random_password.mysql_password.result
  db_subnet_group_name    = aws_db_subnet_group.openedx.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]

  backup_retention_period      = var.rds_backup_retention
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "mon:04:00-mon:05:00"
  
  skip_final_snapshot       = var.environment == "dev" ? true : false
  final_snapshot_identifier = var.environment == "dev" ? null : "${local.cluster_name}-mysql-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  
  storage_encrypted = true
  kms_key_id        = module.retail_app_eks.kms_key_arn

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-mysql" })
}

resource "aws_rds_cluster_instance" "openedx_mysql" {
  count              = 2
  identifier         = "${local.cluster_name}-mysql-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.openedx_mysql.id
  instance_class     = var.rds_instance_class
  engine             = aws_rds_cluster.openedx_mysql.engine
  engine_version     = aws_rds_cluster.openedx_mysql.engine_version

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
  
  performance_insights_enabled    = true
  performance_insights_kms_key_id = module.retail_app_eks.kms_key_arn

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-mysql-instance-${count.index + 1}" })
}

# RDS monitoring role
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.cluster_name}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# =============================================================================
# DocumentDB Cluster (MongoDB Compatible)
# =============================================================================

resource "aws_docdb_subnet_group" "openedx" {
  name       = "${local.cluster_name}-docdb-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-docdb-subnet" })
}

resource "aws_docdb_cluster" "openedx_mongodb" {
  cluster_identifier      = "${local.cluster_name}-mongodb"
  master_username         = "openedx"
  master_password         = random_password.mongodb_password.result
  db_subnet_group_name    = aws_docdb_subnet_group.openedx.name
  vpc_security_group_ids  = [aws_security_group.documentdb_sg.id]
  
  backup_retention_period = var.rds_backup_retention
  preferred_backup_window = "03:00-04:00"
  preferred_maintenance_window = "mon:04:00-mon:05:00"
  
  skip_final_snapshot       = var.environment == "dev" ? true : false
  final_snapshot_identifier = var.environment == "dev" ? null : "${local.cluster_name}-mongodb-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  enabled_cloudwatch_logs_exports = ["audit", "profiler"]
  
  storage_encrypted = true
  kms_key_id        = module.retail_app_eks.kms_key_arn

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-mongodb" })
}

resource "aws_docdb_cluster_instance" "openedx_mongodb" {
  count              = 2
  identifier         = "${local.cluster_name}-mongodb-${count.index + 1}"
  cluster_identifier = aws_docdb_cluster.openedx_mongodb.id
  instance_class     = "db.t3.medium"

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-mongodb-instance-${count.index + 1}" })
}

# =============================================================================
# ElastiCache Redis (CORRECTED - Replication Group for HA)
# =============================================================================

resource "aws_elasticache_subnet_group" "openedx" {
  name       = "${local.cluster_name}-redis-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-redis-subnet" })
}

# CORRECTED: Using Replication Group instead of Cluster for HA
resource "aws_elasticache_replication_group" "openedx_redis" {
  replication_group_id       = "${local.cluster_name}-redis"
  replication_group_description = "Redis for OpenEdX"
  
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.redis_node_type
  num_cache_clusters   = 2  # 1 primary + 1 replica
  port                 = 6379
  parameter_group_name = "default.redis7"
  
  subnet_group_name    = aws_elasticache_subnet_group.openedx.name
  security_group_ids   = [aws_security_group.elasticache_sg.id]

  # Enable automatic failover for HA
  automatic_failover_enabled = true
  multi_az_enabled          = true
  
  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth_token.result
  
  # Maintenance
  apply_immediately   = var.environment == "dev" ? true : false
  maintenance_window  = "sun:03:00-sun:04:00"
  snapshot_window     = "02:00-03:00"
  snapshot_retention_limit = var.environment == "production" ? 7 : 1

  # Logging
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }
  
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-redis" })
}

resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name              = "/aws/elasticache/${local.cluster_name}-redis-slow-log"
  retention_in_days = 7

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-redis-slow-log" })
}

resource "aws_cloudwatch_log_group" "redis_engine_log" {
  name              = "/aws/elasticache/${local.cluster_name}-redis-engine-log"
  retention_in_days = 7

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-redis-engine-log" })
}

# =============================================================================
# OpenSearch (Elasticsearch)
# =============================================================================

resource "aws_opensearch_domain" "openedx" {
  domain_name    = "${local.cluster_name}-search"
  engine_version = "OpenSearch_${var.elasticsearch_version}"
  
  cluster_config {
    instance_type          = "t3.small.search"
    instance_count         = 3
    dedicated_master_enabled = false
    zone_awareness_enabled   = true
    
    zone_awareness_config {
      availability_zone_count = 3
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 30
    volume_type = "gp3"
    iops        = 3000
    throughput  = 125
  }

  vpc_options {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.opensearch_sg.id]
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  node_to_node_encryption {
    enabled = true
  }

  encryption_at_rest {
    enabled    = true
    kms_key_id = module.retail_app_eks.kms_key_arn
  }

  # CORRECTED: Simplified access policy
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "*"
      }
      Action   = "es:*"
      Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${local.cluster_name}-search/*"
      Condition = {
        IpAddress = {
          "aws:SourceIp" = module.vpc.vpc_cidr_block
        }
      }
    }]
  })

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_log.arn
    log_type                 = "ES_APPLICATION_LOGS"
    enabled                  = true
  }

  depends_on = [
    aws_cloudwatch_log_resource_policy.opensearch,
    aws_cloudwatch_log_group.opensearch_log
  ]

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-opensearch" })
}

resource "aws_cloudwatch_log_group" "opensearch_log" {
  name              = "/aws/opensearch/${local.cluster_name}"
  retention_in_days = 7

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-opensearch-logs" })
}

resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  policy_name = "${local.cluster_name}-opensearch-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "es.amazonaws.com"
      }
      Action = [
        "logs:PutLogEvents",
        "logs:CreateLogStream"
      ]
      Resource = "${aws_cloudwatch_log_group.opensearch_log.arn}:*"
    }]
  })
}

# =============================================================================
# EFS (Elastic File System) for Persistent Storage
# =============================================================================

resource "aws_efs_file_system" "openedx" {
  creation_token   = "${local.cluster_name}-efs"
  encrypted        = true
  kms_key_id       = module.retail_app_eks.kms_key_arn
  throughput_mode  = "bursting"
  performance_mode = "generalPurpose"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-efs" })
}

resource "aws_efs_mount_target" "openedx" {
  for_each = toset(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.openedx.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_sg.id]
}

# =============================================================================
# S3 Buckets for Static Content and Backups
# =============================================================================

resource "aws_s3_bucket" "openedx_static" {
  bucket = "${local.cluster_name}-static-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-static-bucket" })
}

resource "aws_s3_bucket_versioning" "openedx_static" {
  bucket = aws_s3_bucket.openedx_static.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "openedx_static" {
  bucket = aws_s3_bucket.openedx_static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "openedx_static" {
  bucket = aws_s3_bucket.openedx_static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "openedx_backups" {
  bucket = "${local.cluster_name}-backups-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-backup-bucket" })
}

resource "aws_s3_bucket_versioning" "openedx_backups" {
  bucket = aws_s3_bucket.openedx_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "openedx_backups" {
  bucket = aws_s3_bucket.openedx_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "openedx_backups" {
  bucket = aws_s3_bucket.openedx_backups.id

  rule {
    id     = "archive-old-backups"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# =============================================================================
# WAF (Web Application Firewall) - CORRECTED for CloudFront
# =============================================================================

# Provider for CloudFront WAF (must be us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_wafv2_ip_set" "trusted_ips" {
  provider = aws.us_east_1
  
  name               = "${local.cluster_name}-trusted-ips"
  description        = "Trusted IPs for OpenEdX"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.trusted_ip_addresses  # Add your IPs

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-trusted-ips" })
}

resource "aws_wafv2_web_acl" "openedx" {
  provider = aws.us_east_1
  
  name  = "${local.cluster_name}-waf-acl"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitRule"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.cluster_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.cluster_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.cluster_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-waf" })
}

# =============================================================================
# CloudFront Distribution for Static Assets
# =============================================================================

resource "aws_cloudfront_origin_access_identity" "openedx" {
  comment = "OAI for ${local.cluster_name}"
}

resource "aws_cloudfront_distribution" "openedx_static" {
  origin {
    domain_name = aws_s3_bucket.openedx_static.bucket_regional_domain_name
    origin_id   = "S3Origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.openedx.cloudfront_access_identity_path
    }
  }

  enabled             = true
  default_root_object = "index.html"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  web_acl_id = aws_wafv2_web_acl.openedx.arn

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-cloudfront" })
}

# S3 Bucket policy for CloudFront
resource "aws_s3_bucket_policy" "openedx_static" {
  bucket = aws_s3_bucket.openedx_static.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontAccess"
      Effect = "Allow"
      Principal = {
        AWS = aws_cloudfront_origin_access_identity.openedx.iam_arn
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.openedx_static.arn}/*"
    }]
  })
}

# =============================================================================
# SNS Topics for Alerts
# =============================================================================

resource "aws_sns_topic" "openedx_alerts" {
  name              = "${local.cluster_name}-alerts"
  kms_master_key_id = module.retail_app_eks.kms_key_arn

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-alerts" })
}

resource "aws_sns_topic_subscription" "openedx_alerts_email" {
  topic_arn = aws_sns_topic.openedx_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
