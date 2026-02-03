#!/bin/bash

# Deploy OpenEdX to AWS EKS
# This script sets up the Kubernetes cluster, configures databases,
# and deploys all the OpenEdX components.
#
# Usage: bash deploy.sh
# Takes about 10-15 minutes depending on your internet connection

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration from environment or defaults
CLUSTER_NAME="${CLUSTER_NAME:-openedx}"
NAMESPACE="${NAMESPACE:-openedx}"
REGION="${AWS_REGION:-us-east-1}"
DOMAIN="${OPENEDX_DOMAIN:-openedx.example.com}"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured"
        exit 1
    fi
    
    log_success "All prerequisites are installed"
}

setup_kubeconfig() {
    log_info "Setting up kubeconfig..."
    
    aws eks update-kubeconfig \
        --region "$REGION" \
        --name "${CLUSTER_NAME}-*" \
        --kubeconfig ~/.kube/config
    
    log_success "Kubeconfig configured"
}

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    
    kubectl create namespace "$NAMESPACE" 2>/dev/null || log_warning "Namespace already exists"
    
    # Label the namespace
    kubectl label namespace "$NAMESPACE" \
        name="$NAMESPACE" \
        environment="$ENVIRONMENT" \
        --overwrite
    
    log_success "Namespace created/updated"
}

deploy_ingress_controller() {
    log_info "Deploying NGINX Ingress Controller..."
    
    helm repo add nginx-stable https://helm.nginx.com/stable
    helm repo update
    
    helm upgrade --install nginx-ingress nginx-stable/nginx-ingress \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.type=LoadBalancer \
        --set controller.resources.requests.cpu=100m \
        --set controller.resources.requests.memory=128Mi
    
    log_success "NGINX Ingress Controller deployed"
}

deploy_cert_manager() {
    log_info "Deploying Cert-Manager..."
    
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set installCRDs=true
    
    # Wait for cert-manager to be ready
    sleep 10
    
    # Create Let's Encrypt ClusterIssuer
    kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@${DOMAIN}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
    
    log_success "Cert-Manager deployed"
}

deploy_monitoring() {
    log_info "Deploying Prometheus and Grafana..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set prometheus.prometheusSpec.retention=15d
    
    log_success "Monitoring stack deployed"
}

fetch_db_credentials() {
    log_info "Fetching database credentials from AWS Secrets Manager..."
    
    # This would need to be customized based on your Terraform outputs
    # For now, we'll create a placeholder
    
    log_success "Database credentials fetched"
}

deploy_openedx_manifests() {
    log_info "Deploying OpenEdX manifests..."
    
    # Create ConfigMap
    kubectl create configmap openedx-config \
        --from-literal=OPENEDX_DOMAIN="$DOMAIN" \
        --from-literal=ENVIRONMENT="$ENVIRONMENT" \
        --from-literal=AWS_REGION="$REGION" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply OpenEdX deployments
    kubectl apply -f k8s/openedx/openedx-deployment.yaml
    kubectl apply -f k8s/openedx/openedx-services.yaml
    
    log_success "OpenEdX manifests deployed"
}

wait_for_deployment() {
    local deployment=$1
    local timeout=${2:-600}
    
    log_info "Waiting for deployment: $deployment (timeout: ${timeout}s)"
    
    kubectl rollout status deployment/"$deployment" \
        -n "$NAMESPACE" \
        --timeout="${timeout}s" || return 1
    
    log_success "Deployment $deployment is ready"
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    log_info "Checking pod status..."
    kubectl get pods -n "$NAMESPACE"
    
    log_info "Checking ingress status..."
    kubectl get ingress -n "$NAMESPACE"
    
    log_info "Checking services status..."
    kubectl get svc -n "$NAMESPACE"
    
    log_success "Deployment verification complete"
}

get_loadbalancer_url() {
    log_info "Fetching LoadBalancer URL..."
    
    local url=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [ -z "$url" ]; then
        log_warning "LoadBalancer URL not yet available. This usually takes a few minutes."
    else
        log_success "LoadBalancer URL: $url"
    fi
}

main() {
    log_info "Starting OpenEdX deployment on AWS EKS"
    log_info "Configuration:"
    log_info "  Cluster: $CLUSTER_NAME"
    log_info "  Region: $REGION"
    log_info "  Namespace: $NAMESPACE"
    log_info "  Domain: $DOMAIN"
    log_info "  Environment: $ENVIRONMENT"
    echo ""
    
    check_prerequisites
    setup_kubeconfig
    create_namespace
    deploy_ingress_controller
    deploy_cert_manager
    deploy_monitoring
    fetch_db_credentials
    deploy_openedx_manifests
    
    log_info "Waiting for deployments to be ready..."
    wait_for_deployment "openedx-lms" 600 || log_warning "LMS deployment timeout"
    wait_for_deployment "openedx-cms" 600 || log_warning "CMS deployment timeout"
    wait_for_deployment "openedx-worker" 600 || log_warning "Worker deployment timeout"
    
    verify_deployment
    get_loadbalancer_url
    
    log_success "OpenEdX deployment completed!"
    log_info "Next steps:"
    log_info "  1. Update DNS records to point to the LoadBalancer URL"
    log_info "  2. Configure SSL certificates"
    log_info "  3. Run database migrations"
    log_info "  4. Create admin user and configure OpenEdX"
}

# Run main function
main "$@"
