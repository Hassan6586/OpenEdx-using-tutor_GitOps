# =============================================================================
# SECURITY GROUPS AND RULES - OpenEdX on AWS EKS
# =============================================================================

# Allow HTTP/HTTPS traffic from internet to load balancer
resource "aws_security_group_rule" "internet_to_lb_http" {
  description       = "Allow HTTP traffic from internet to LoadBalancer"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.retail_app_eks.cluster_security_group_id
}

resource "aws_security_group_rule" "internet_to_lb_https" {
  description       = "Allow HTTPS traffic from internet to LoadBalancer"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.retail_app_eks.cluster_security_group_id
}

# Allow LoadBalancer health checks from AWS
resource "aws_security_group_rule" "health_checks_to_lb" {
  description       = "Allow AWS health checks to LoadBalancer"
  type              = "ingress"
  from_port         = 10254
  to_port           = 10254
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = module.retail_app_eks.cluster_security_group_id
}

# Allow NodePort range for services (if needed)
resource "aws_security_group_rule" "nodeport_access" {
  description       = "Allow NodePort access within VPC"
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = module.retail_app_eks.cluster_security_group_id
}

# =============================================================================
# IAM ROLES AND POLICIES FOR OPENEDX SERVICES
# =============================================================================

# IAM role for service accounts (IRSA)
resource "aws_iam_role" "openedx_service_account" {
  name = "${local.cluster_name}-openedx-sa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(module.retail_app_eks.oidc_provider_arn, "/^(.*provider/)/", "")}"
      }
      Condition = {
        StringEquals = {
          "${replace(module.retail_app_eks.oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:${var.openedx_namespace}:openedx-sa"
        }
      }
    }]
  })

  tags = local.common_tags
}

# Policy for S3 access
resource "aws_iam_role_policy" "openedx_s3_access" {
  name = "${local.cluster_name}-openedx-s3"
  role = aws_iam_role.openedx_service_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.openedx_static.arn,
          "${aws_s3_bucket.openedx_static.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.openedx_backups.arn,
          "${aws_s3_bucket.openedx_backups.arn}/*"
        ]
      }
    ]
  })
}

# Policy for Secrets Manager access
resource "aws_iam_role_policy" "openedx_secrets" {
  name = "${local.cluster_name}-openedx-secrets"
  role = aws_iam_role.openedx_service_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.cluster_name}/*"
    }]
  })
}

# Policy for CloudWatch Logs
resource "aws_iam_role_policy" "openedx_logs" {
  name = "${local.cluster_name}-openedx-logs"
  role = aws_iam_role.openedx_service_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/openedx/*"
    }]
  })
}

# Policy for EBS/EFS access
resource "aws_iam_role_policy" "openedx_ebs_efs" {
  name = "${local.cluster_name}-openedx-ebs-efs"
  role = aws_iam_role.openedx_service_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# AWS SECRETS MANAGER
# =============================================================================

resource "aws_secretsmanager_secret" "openedx_db" {
  name                    = "${local.cluster_name}/database"
  description             = "OpenEdX Database Credentials"
  recovery_window_in_days = 7

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-db-secret" })
}

resource "aws_secretsmanager_secret_version" "openedx_db" {
  secret_id = aws_secretsmanager_secret.openedx_db.id
  secret_string = jsonencode({
    mysql = {
      username = var.mysql_username
      password = random_password.mysql_password.result
      host     = aws_rds_cluster.openedx_mysql.cluster_resource_id
      port     = 3306
      database = var.mysql_db_name
    }
    mongodb = {
      username = "openedx"
      password = random_password.mongodb_password.result
      host     = aws_docdb_cluster.openedx_mongodb.cluster_resource_id
      port     = 27017
      database = var.mongodb_name
    }
    redis = {
      host  = aws_elasticache_cluster.openedx_redis.cache_nodes[0].address
      port  = aws_elasticache_cluster.openedx_redis.port
      token = random_password.redis_auth_token.result
    }
    opensearch = {
      domain   = aws_opensearch_domain.openedx.domain_name
      endpoint = aws_opensearch_domain.openedx.endpoint
    }
  })
}

# =============================================================================
# PARAMETER STORE FOR CONFIGURATION
# =============================================================================

resource "aws_ssm_parameter" "openedx_config" {
  name  = "${local.cluster_name}/config"
  type  = "String"
  value = jsonencode({
    environment = var.environment
    domain      = var.openedx_domain
    region      = var.aws_region
  })

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-config" })
}

# =============================================================================
# KMS KEY FOR ENCRYPTION
# =============================================================================

resource "aws_kms_key" "openedx" {
  description             = "KMS key for OpenEdX encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-kms-key" })
}

resource "aws_kms_alias" "openedx" {
  name          = "alias/${local.cluster_name}-openedx"
  target_key_id = aws_kms_key.openedx.key_id
}

# =============================================================================
# VPC ENDPOINTS FOR AWS SERVICES
# =============================================================================

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids   = module.vpc.private_route_table_ids
  vpc_endpoint_type = "Gateway"

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-s3-endpoint" })
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-secrets-endpoint" })
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-ssm-endpoint" })
}

resource "aws_security_group" "vpce_sg" {
  name   = "${local.cluster_name}-vpce-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
    description = "HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-vpce-sg" })
}
