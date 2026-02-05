# EKS ADD-ONS AND EXTENSIONS - OpenEdX on AWS EKS 
# =============================================================================

# =============================================================================
# EKS BLUEPRINTS ADDONS MODULE
# =============================================================================

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = opexedx_eks.cluster_name
  cluster_endpoint  = openedx_eks.cluster_endpoint
  cluster_version   = openedx_eks.cluster_version
  oidc_provider_arn = openedx_eks.oidc_provider_arn

  # =============================================================================
  # NGINX INGRESS CONTROLLER
  # =============================================================================
  
  enable_ingress_nginx = true
  ingress_nginx = {
    name          = "ingress-nginx"
    chart_version = "4.8.3"
    repository    = "https://kubernetes.github.io/ingress-nginx"
    namespace     = "ingress-nginx"
    
    values = [
      yamlencode({
        controller = {
          service = {
            type                  = "LoadBalancer"
            externalTrafficPolicy = "Local"
            annotations = {
              "service.beta.kubernetes.io/aws-load-balancer-scheme"                 = "internet-facing"
              "service.beta.kubernetes.io/aws-load-balancer-type"                   = "nlb"
              "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"        = "instance"
              "service.beta.kubernetes.io/aws-load-balancer-health-check-path"      = "/healthz"
              "service.beta.kubernetes.io/aws-load-balancer-health-check-port"      = "10254"
              "service.beta.kubernetes.io/aws-load-balancer-health-check-protocol"  = "HTTP"
              "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
            }
          }
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
          metrics = {
            enabled = true
            serviceMonitor = {
              enabled = true
            }
          }
          autoscaling = {
            enabled     = true
            minReplicas = 2
            maxReplicas = 5
            targetCPUUtilizationPercentage = 80
          }
        }
      })
    ]
  }

  # =============================================================================
  # METRICS SERVER
  # =============================================================================
  
  enable_metrics_server = true
  metrics_server = {
    name          = "metrics-server"
    chart_version = "3.11.0"
    repository    = "https://kubernetes-sigs.github.io/metrics-server/"
    namespace     = "kube-system"
    
    values = [
      yamlencode({
        args = [
          "--kubelet-insecure-tls",
          "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"
        ]
        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      })
    ]
  }

  # =============================================================================
  # AWS EBS CSI DRIVER (for persistent volumes)
  # =============================================================================
  
  enable_aws_ebs_csi_driver = true
  aws_ebs_csi_driver = {
    name = "aws-ebs-csi-driver"
  }

  # =============================================================================
  # AWS EFS CSI DRIVER (for shared storage)
  # =============================================================================
  
  enable_aws_efs_csi_driver = true
  aws_efs_csi_driver = {
    name = "aws-efs-csi-driver"
  }

  # =============================================================================
  # CERT-MANAGER FOR SSL/TLS
  # =============================================================================
  
  enable_cert_manager = true
  cert_manager = {
    name          = "cert-manager"
    chart_version = "v1.14.0"
    repository    = "https://charts.jetstack.io"
    namespace     = "cert-manager"
    
    values = [
      yamlencode({
        installCRDs = true
        global = {
          leaderElection = {
            namespace = "cert-manager"
          }
        }
        serviceAccount = {
          create = true
          name   = "cert-manager"
        }
        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
        prometheus = {
          enabled = true
          servicemonitor = {
            enabled = true
          }
        }
      })
    ]
  }

  # =============================================================================
  # CLUSTER AUTOSCALER
  # =============================================================================
  
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    name = "cluster-autoscaler"
    values = [
      yamlencode({
        autoDiscovery = {
          clusterName = module.retail_app_eks.cluster_name
        }
        awsRegion = var.aws_region
        rbac = {
          create = true
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      })
    ]
  }

  depends_on = [openedx_eks]

  tags = local.common_tags
}

# =============================================================================
# LET'S ENCRYPT CLUSTER ISSUER
# =============================================================================

resource "kubernetes_manifest" "letsencrypt_prod" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [module.eks_blueprints_addons]
}

resource "kubernetes_manifest" "letsencrypt_staging" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-staging"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [module.eks_blueprints_addons]
}

# =============================================================================
# OPENEDX NAMESPACE AND CONFIGURATION
# =============================================================================

resource "kubernetes_namespace" "openedx" {
  metadata {
    name = var.openedx_namespace
    labels = {
      name       = var.openedx_namespace
      managed-by = "terraform"
      component  = "openedx"
    }
  }

  depends_on = [module.retail_app_eks]
}

# =============================================================================
# IAM ROLE FOR OPENEDX SERVICE ACCOUNT (IRSA)
# =============================================================================

resource "aws_iam_role" "openedx_service_account" {
  name = "${local.cluster_name}-openedx-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.retail_app_eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.retail_app_eks.oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:${var.openedx_namespace}:openedx-sa"
          "${replace(module.retail_app_eks.oidc_provider_arn, "/^(.*provider/)/", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name      = "${local.cluster_name}-openedx-sa-role"
    Component = "OpenEdX"
  })
}

# IAM Policy for S3 Access
resource "aws_iam_policy" "openedx_s3_access" {
  name        = "${local.cluster_name}-openedx-s3-policy"
  description = "Policy for OpenEdX to access S3 buckets"

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
          "${aws_s3_bucket.openedx_static.arn}/*",
          aws_s3_bucket.openedx_static.arn,
          "${aws_s3_bucket.openedx_backups.arn}/*",
          aws_s3_bucket.openedx_backups.arn
        ]
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "openedx_s3" {
  role       = aws_iam_role.openedx_service_account.name
  policy_arn = aws_iam_policy.openedx_s3_access.arn
}

# Service account for OpenEdX
resource "kubernetes_service_account" "openedx" {
  metadata {
    name      = "openedx-sa"
    namespace = kubernetes_namespace.openedx.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.openedx_service_account.arn
    }
  }

  depends_on = [
    kubernetes_namespace.openedx,
    aws_iam_role.openedx_service_account
  ]
}

# =============================================================================
# CONFIGMAP FOR OPENEDX ENVIRONMENT VARIABLES
# =============================================================================

resource "kubernetes_config_map" "openedx_config" {
  metadata {
    name      = "openedx-config"
    namespace = kubernetes_namespace.openedx.metadata[0].name
  }

  data = {
    OPENEDX_DOMAIN   = var.openedx_domain
    ENVIRONMENT      = var.environment
    AWS_REGION       = var.aws_region
    CLUSTER_NAME     = local.cluster_name
    
    # Database endpoints
    MYSQL_HOST       = aws_rds_cluster.openedx_mysql.endpoint
    MYSQL_PORT       = tostring(aws_rds_cluster.openedx_mysql.port)
    MYSQL_DATABASE   = var.mysql_db_name
    
    MONGODB_HOST     = aws_docdb_cluster.openedx_mongodb.endpoint
    MONGODB_PORT     = tostring(aws_docdb_cluster.openedx_mongodb.port)
    MONGODB_DATABASE = var.mongodb_name
    
    # For replication group (HA Redis)
    REDIS_HOST       = aws_elasticache_replication_group.openedx_redis.primary_endpoint_address
    REDIS_PORT       = tostring(aws_elasticache_replication_group.openedx_redis.port)
    
    # OpenSearch
    OPENSEARCH_HOST  = aws_opensearch_domain.openedx.endpoint
    OPENSEARCH_PORT  = "443"
    
    # S3 Buckets
    S3_STATIC_BUCKET = aws_s3_bucket.openedx_static.id
    S3_BACKUP_BUCKET = aws_s3_bucket.openedx_backups.id
    
    # EFS
    EFS_ID           = aws_efs_file_system.openedx.id
  }

  depends_on = [kubernetes_namespace.openedx]
}

# =============================================================================
# SECRET FOR DATABASE CREDENTIALS
# =============================================================================

resource "kubernetes_secret" "openedx_db_credentials" {
  metadata {
    name      = "openedx-db-credentials"
    namespace = kubernetes_namespace.openedx.metadata[0].name
  }

  type = "Opaque"

  # Use stringData to avoid double base64 encoding
  stringData = {
    mysql_username   = var.mysql_username
    mysql_password   = random_password.mysql_password.result
    mongodb_username = "openedx"
    mongodb_password = random_password.mongodb_password.result
    redis_auth_token = random_password.redis_auth_token.result
  }

  depends_on = [kubernetes_namespace.openedx]
}

# =============================================================================
# MONITORING NAMESPACE
# =============================================================================

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      name       = "monitoring"
      managed-by = "terraform"
      component  = "observability"
    }
  }

  depends_on = [openedx_eks]
}

# =============================================================================
# ARGOCD NAMESPACE
# =============================================================================

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      name       = var.argocd_namespace
      managed-by = "terraform"
      component  = "gitops"
    }
  }

  depends_on = [module.openedx_eks]
}
