# =============================================================================
# OUTPUT VALUES - OpenEdX on AWS EKS
# =============================================================================

# =============================================================================
# CLUSTER INFORMATION
# =============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster (with unique suffix)"
  value       = module.retail_app_eks.cluster_name
}

output "cluster_name_base" {
  description = "Base cluster name without suffix"
  value       = var.cluster_name
}

output "cluster_name_suffix" {
  description = "Random suffix added to cluster name"
  value       = random_string.suffix.result
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.retail_app_eks.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.retail_app_eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.retail_app_eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.retail_app_eks.cluster_oidc_issuer_url
}

# =============================================================================
# NETWORK INFORMATION
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC where the cluster is deployed"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

# =============================================================================
# DATABASE INFORMATION
# =============================================================================

output "rds_mysql_endpoint" {
  description = "RDS MySQL cluster endpoint"
  value       = aws_rds_cluster.openedx_mysql.endpoint
}

output "rds_mysql_reader_endpoint" {
  description = "RDS MySQL cluster reader endpoint"
  value       = aws_rds_cluster.openedx_mysql.reader_endpoint
}

output "rds_mysql_port" {
  description = "RDS MySQL cluster port"
  value       = aws_rds_cluster.openedx_mysql.port
}

output "rds_mysql_database" {
  description = "RDS MySQL database name"
  value       = aws_rds_cluster.openedx_mysql.database_name
}

output "documentdb_mongodb_endpoint" {
  description = "DocumentDB cluster endpoint"
  value       = aws_docdb_cluster.openedx_mongodb.endpoint
}

output "documentdb_mongodb_reader_endpoint" {
  description = "DocumentDB cluster reader endpoint"
  value       = aws_docdb_cluster.openedx_mongodb.reader_endpoint
}

output "documentdb_mongodb_port" {
  description = "DocumentDB cluster port"
  value       = aws_docdb_cluster.openedx_mongodb.port
}

output "elasticache_redis_endpoint" {
  description = "ElastiCache Redis cluster endpoint"
  value       = aws_elasticache_cluster.openedx_redis.cache_nodes[0].address
}

output "elasticache_redis_port" {
  description = "ElastiCache Redis cluster port"
  value       = aws_elasticache_cluster.openedx_redis.port
}

output "opensearch_domain_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.openedx.endpoint
}

output "opensearch_kibana_endpoint" {
  description = "OpenSearch Kibana endpoint"
  value       = aws_opensearch_domain.openedx.kibana_endpoint
}

# =============================================================================
# STORAGE INFORMATION
# =============================================================================

output "efs_file_system_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.openedx.id
}

output "s3_static_bucket" {
  description = "S3 bucket for static assets"
  value       = aws_s3_bucket.openedx_static.id
}

output "s3_backup_bucket" {
  description = "S3 bucket for backups"
  value       = aws_s3_bucket.openedx_backups.id
}

# =============================================================================
# CDN AND SECURITY
# =============================================================================

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.openedx_static.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.openedx_static.domain_name
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.openedx.arn
}

# =============================================================================
# SECRETS AND CONFIGURATION
# =============================================================================

output "secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN for database credentials"
  value       = aws_secretsmanager_secret.openedx_db.arn
}

output "ssm_parameter_name" {
  description = "SSM Parameter Store parameter name for OpenEdX config"
  value       = aws_ssm_parameter.openedx_config.name
}

# =============================================================================
# IAM INFORMATION
# =============================================================================

output "openedx_service_account_role_arn" {
  description = "IAM role ARN for OpenEdX service account"
  value       = aws_iam_role.openedx_service_account.arn
}

# =============================================================================
# ACCESS INFORMATION
# =============================================================================

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.retail_app_eks.cluster_name}"
}

output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = var.argocd_namespace
}

output "argocd_server_port_forward" {
  description = "Command to port-forward to ArgoCD server"
  value       = "kubectl port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:443"
}

output "argocd_admin_password" {
  description = "Command to get ArgoCD admin password"
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  sensitive   = true
}

# =============================================================================
# APPLICATION ACCESS
# =============================================================================

output "ingress_nginx_loadbalancer" {
  description = "Command to get the LoadBalancer URL for accessing applications"
  value       = "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "openedx_namespace" {
  description = "Kubernetes namespace for OpenEdX"
  value       = var.openedx_namespace
}

output "openedx_domain" {
  description = "Domain configured for OpenEdX"
  value       = var.openedx_domain
}

# =============================================================================
# SNS TOPICS
# =============================================================================

output "alerts_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.openedx_alerts.arn
}

# =============================================================================
# SUMMARY
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    cluster_name = module.retail_app_eks.cluster_name
    region       = var.aws_region
    environment  = var.environment
    databases = {
      mysql      = aws_rds_cluster.openedx_mysql.endpoint
      mongodb    = aws_docdb_cluster.openedx_mongodb.endpoint
      redis      = aws_elasticache_cluster.openedx_redis.cache_nodes[0].address
      opensearch = aws_opensearch_domain.openedx.endpoint
    }
    storage = {
      efs    = aws_efs_file_system.openedx.id
      s3_cdn = aws_cloudfront_distribution.openedx_static.domain_name
    }
  }
}

output "retail_store_url" {
  description = "Command to get the retail store application URL"
  value       = "echo 'http://'$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
}

# =============================================================================
# USEFUL COMMANDS
# =============================================================================

output "useful_commands" {
  description = "Useful commands for managing the cluster"
  value = {
    get_nodes           = "kubectl get nodes"
    get_pods_all        = "kubectl get pods -A"
    get_retail_store    = "kubectl get pods -n retail-store"
    argocd_apps         = "kubectl get applications -n ${var.argocd_namespace}"
    ingress_status      = "kubectl get ingress -A"
    describe_cluster    = "kubectl cluster-info"
  }
}
