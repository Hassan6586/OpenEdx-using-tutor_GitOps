# =============================================================================
# ARGOCD DEPLOYMENT - GitOps Pipeline
# =============================================================================

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = var.argocd_namespace

  create_namespace = true

  values = [
    yamlencode({
      global = {
        domain = var.openedx_domain
      }

      configs = {
        cm = {
          url = "https://argocd.${var.openedx_domain}"
          "accounts.admin.passwordChangeRequired" = "false"
          "application.instanceLabelKey" = "argocd.argoproj.io/instance"
        }
        secret = {
          argocdServerAdmins = ["admin"]
        }
      }

      controller = {
        replicas = 1
        resources = {
          requests = {
            cpu    = "100m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1024Mi"
          }
        }
      }

      server = {
        replicas = 2
        autoscaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 5
        }
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
        service = {
          type = "LoadBalancer"
        }
      }

      repoServer = {
        replicas = 2
        autoscaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 5
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      applicationSet = {
        replicas = 1
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      notifications = {
        enabled = true
        metrics = {
          enabled = true
        }
      }

      redis = {
        enabled = true
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
      }

      dex = {
        enabled = true
      }
    })
  ]

  depends_on = [openedx.cluster_id]

  tags = local.common_tags
}

# ArgoCD Ingress for HTTPS access
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-ingress"
    namespace = var.argocd_namespace
    annotations = {
      "cert-manager.io/cluster-issuer"                   = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/ssl-redirect"         = "true"
      "nginx.ingress.kubernetes.io/backend-protocol"     = "HTTPS"
      "nginx.ingress.kubernetes.io/proxy-body-size"      = "100m"
    }
  }

  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = ["argocd.${var.openedx_domain}"]
      secret_name = "argocd-tls"
    }

    rule {
      host = "argocd.${var.openedx_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 443
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_manifest.letsencrypt_issuer]
}

# =============================================================================
# PROMETHEUS AND GRAFANA STACK
# =============================================================================

resource "random_password" "grafana_password" {
  length  = 32
  special = true
}

resource "helm_release" "prometheus_stack" {
  count      = var.enable_monitoring ? 1 : 0
  name       = "prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.7.1"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          replicas = 2
          resources = {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1024Mi"
            }
          }
          retention = "15d"
          externalLabels = {
            cluster = local.cluster_name
            region  = var.aws_region
          }
        }
      }

      grafana = {
        enabled = true
        replicas = 2
        adminPassword = random_password.grafana_password.result
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          replicas = 2
        }
      }

      kubeStateMetrics = {
        enabled = true
      }

      nodeExporter = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]

  tags = local.common_tags
}

# =============================================================================
# FLUENTD FOR LOG FORWARDING
# =============================================================================

resource "helm_release" "fluentd" {
  count      = var.enable_monitoring ? 1 : 0
  name       = "fluentd"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluentd"
  version    = "0.20.9"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    yamlencode({
      image = {
        repository = "fluent/fluentd-kubernetes-daemonset"
        tag        = "v1-debian-opensearch"
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
      tolerations = [
        {
          operator = "Exists"
        }
      ]
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]

  tags = local.common_tags
}
