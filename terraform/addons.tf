# =============================================================================
# EKS ADD-ONS AND EXTENSIONS - OpenEdX on AWS EKS
# =============================================================================

# =============================================================================
# NGINX INGRESS CONTROLLER
# =============================================================================

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.0"
  namespace  = "ingress-nginx"

  create_namespace = true

  values = [
    yamlencode({
      controller = {
        service = {
          type               = "LoadBalancer"
          externalTrafficPolicy = "Local"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
          }
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
        autoscaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 10
          targetCPUUtilizationPercentage = 80
          targetMemoryUtilizationPercentage = 80
        }
        config = {
          "use-forwarded-headers" = "true"
          "compute-full-forwarded-for" = "true"
          "use-proxy-protocol" = "true"
          "enable-modsecurity" = "true"
          "enable-owasp-core-rules" = "true"
          "http2-max-field-size" = "16k"
          "http2-max-header-size" = "16k"
          "client-max-body-size" = "100m"
          "keepalive-timeout" = "120"
          "worker-processes" = "auto"
        }
        metrics = {
          enabled = true
          service = {
            namespace = "ingress-nginx"
          }
        }
        livenessProbe = {
          httpGet = {
            path   = "/healthz"
            port   = 10254
            scheme = "HTTP"
          }
          initialDelaySeconds = 10
          periodSeconds       = 10
        }
        readinessProbe = {
          httpGet = {
            path   = "/healthz"
            port   = 10254
            scheme = "HTTP"
          }
          initialDelaySeconds = 5
          periodSeconds       = 5
        }
      }
      tcp = {}
      udp = {}
    })
  ]

  depends_on = [module.retail_app_eks.cluster_id]

  tags = local.common_tags
}

# =============================================================================
# CERT-MANAGER FOR SSL/TLS
# =============================================================================

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.13.2"
  namespace  = "cert-manager"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }

  values = [
    yamlencode({
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
    })
  ]

  depends_on = [module.retail_app_eks.cluster_id]

  tags = local.common_tags
}

# Let's Encrypt ClusterIssuer
resource "kubernetes_manifest" "letsencrypt_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = "admin@${var.openedx_domain}"
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

  depends_on = [helm_release.cert_manager]
}

# =============================================================================
# METRICS SERVER
# =============================================================================

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.11.0"
  namespace  = "kube-system"

  values = [
    yamlencode({
      args = [
        "--kubelet-insecure-tls",
        "--kubelet-preferred-address-types=InternalIP"
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

  depends_on = [module.retail_app_eks.cluster_id]

  tags = local.common_tags
}

# =============================================================================
# OPENEDX NAMESPACE AND CONFIGURATION
# =============================================================================

resource "kubernetes_namespace" "openedx" {
  metadata {
    name = var.openedx_namespace
  }

  depends_on = [module.retail_app_eks.cluster_id]
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

  depends_on = [kubernetes_namespace.openedx]
}

# ConfigMap for OpenEdX environment variables
resource "kubernetes_config_map" "openedx_config" {
  metadata {
    name      = "openedx-config"
    namespace = kubernetes_namespace.openedx.metadata[0].name
  }

  data = {
    OPENEDX_DOMAIN    = var.openedx_domain
    ENVIRONMENT       = var.environment
    AWS_REGION        = var.aws_region
    CLUSTER_NAME      = local.cluster_name
    MYSQL_HOST        = aws_rds_cluster.openedx_mysql.endpoint
    MYSQL_PORT        = tostring(aws_rds_cluster.openedx_mysql.port)
    MYSQL_DATABASE    = var.mysql_db_name
    MONGODB_HOST      = aws_docdb_cluster.openedx_mongodb.endpoint
    MONGODB_PORT      = tostring(aws_docdb_cluster.openedx_mongodb.port)
    MONGODB_DATABASE  = var.mongodb_name
    REDIS_HOST        = aws_elasticache_cluster.openedx_redis.cache_nodes[0].address
    REDIS_PORT        = tostring(aws_elasticache_cluster.openedx_redis.port)
    OPENSEARCH_HOST   = aws_opensearch_domain.openedx.endpoint
    S3_STATIC_BUCKET  = aws_s3_bucket.openedx_static.id
    S3_BACKUP_BUCKET  = aws_s3_bucket.openedx_backups.id
    EFS_ID            = aws_efs_file_system.openedx.id
  }

  depends_on = [kubernetes_namespace.openedx]
}

# Secret for database credentials
resource "kubernetes_secret" "openedx_db_credentials" {
  metadata {
    name      = "openedx-db-credentials"
    namespace = kubernetes_namespace.openedx.metadata[0].name
  }

  type = "Opaque"

  data = {
    mysql_username    = base64encode(var.mysql_username)
    mysql_password    = base64encode(random_password.mysql_password.result)
    mongodb_username  = base64encode("openedx")
    mongodb_password  = base64encode(random_password.mongodb_password.result)
    redis_auth_token  = base64encode(random_password.redis_auth_token.result)
  }

  depends_on = [kubernetes_namespace.openedx]
}

# =============================================================================
# MONITORING NAMESPACE
# =============================================================================

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }

  depends_on = [module.retail_app_eks.cluster_id]
}
      {
        name  = "controller.resources.limits.cpu"
        value = "200m"
      },
      {
        name  = "controller.resources.limits.memory"
        value = "256Mi"
      }
    ]
    
    # AWS Load Balancer specific annotations
    set_sensitive = [
      {
        name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
        value = "internet-facing"
      },
      {
        name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
        value = "nlb"
      },
      {
        name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type"
        value = "instance"
      },
      {
        name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-health-check-path"
        value = "/healthz"
      },
      {
        name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-health-check-port"
        value = "10254"
      },
      {
        name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-health-check-protocol"
        value = "HTTP"
      }
    ]
  }

  # =============================================================================
  # OPTIONAL: MONITORING STACK
  # =============================================================================
  # Uncomment below to enable monitoring (increases costs)
  
  # enable_kube_prometheus_stack = var.enable_monitoring
  # kube_prometheus_stack = {
  #   most_recent = true
  #   namespace   = "monitoring"
  # }

  # =============================================================================
  # OPTIONAL: AWS LOAD BALANCER CONTROLLER
  # =============================================================================
  # enable_aws_load_balancer_controller = true
  # aws_load_balancer_controller = {
  #   most_recent = true
  #   namespace   = "kube-system"
  # }

  depends_on = [module.openedx]
}
