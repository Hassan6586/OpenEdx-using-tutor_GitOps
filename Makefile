.PHONY: help init plan apply destroy deploy backup restore monitoring status clean validate docs

# Variables
TERRAFORM_DIR = terraform
SCRIPTS_DIR = scripts
K8S_DIR = k8s
DOCS_DIR = docs
NAMESPACE = openedx
REGION ?= us-east-1
ENVIRONMENT ?= dev

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m # No Color

help:
	@echo ""
	@echo "OpenEdX on AWS EKS - Available Commands"
	@echo ""
	@echo "$(GREEN)Deploy:$(NC)"
	@echo "  make setup              Deploy everything (automated)"
	@echo "  make init               Initialize Terraform"
	@echo "  make plan               See what will be created"
	@echo "  make apply              Create AWS resources"
	@echo "  make destroy            Tear everything down"
	@echo ""
	@echo "$(GREEN)Operations:$(NC)"
	@echo "  make deploy             Deploy OpenEdX app"
	@echo "  make redeploy           Restart pods"
	@echo "  make status             Check what's running"
	@echo "  make logs               View application logs"
	@echo "  make monitoring         Open Grafana dashboard"
	@echo ""
	@echo "$(GREEN)Backup & Recovery:$(NC)"
	@echo "  make backup             Backup databases and K8s"
	@echo "  make restore            Restore from backup"
	@echo ""
	@echo "$(GREEN)Utilities:$(NC)"
	@echo "  make clean              Clean local files"
	@echo "  make validate           Check Terraform syntax"
	@echo ""

# Terraform targets
init:
	@echo "$(BLUE)Initializing Terraform...$(NC)"
	cd $(TERRAFORM_DIR) && terraform init
	@echo "$(GREEN)✓ Terraform initialized$(NC)"

validate:
	@echo "$(BLUE)Validating Terraform configuration...$(NC)"
	cd $(TERRAFORM_DIR) && terraform validate
	@echo "$(GREEN)✓ Configuration is valid$(NC)"

plan:
	@echo "$(BLUE)Planning infrastructure for $(ENVIRONMENT) environment...$(NC)"
	cd $(TERRAFORM_DIR) && terraform plan -out=tfplan-$(ENVIRONMENT) -var="environment=$(ENVIRONMENT)"
	@echo "$(GREEN)✓ Plan created: tfplan-$(ENVIRONMENT)$(NC)"

apply:
	@echo "$(YELLOW)WARNING: This will create/modify AWS resources$(NC)"
	@echo "$(BLUE)Applying infrastructure for $(ENVIRONMENT) environment...$(NC)"
	cd $(TERRAFORM_DIR) && terraform apply tfplan-$(ENVIRONMENT)
	@echo "$(GREEN)✓ Infrastructure applied$(NC)"
	@echo "$(YELLOW)Saving outputs...$(NC)"
	cd $(TERRAFORM_DIR) && terraform output > outputs.json
	@echo "$(GREEN)✓ Outputs saved to outputs.json$(NC)"

destroy:
	@echo "$(RED)WARNING: This will destroy all AWS resources!$(NC)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve
	@echo "$(GREEN)✓ Infrastructure destroyed$(NC)"

# Deployment targets
kubeconfig:
	@echo "$(BLUE)Updating kubeconfig...$(NC)"
	@bash $(SCRIPTS_DIR)/setup-kubeconfig.sh
	@echo "$(GREEN)✓ Kubeconfig updated$(NC)"

deploy:
	@echo "$(BLUE)Deploying OpenEdX application...$(NC)"
	@bash $(SCRIPTS_DIR)/deploy.sh
	@echo "$(GREEN)✓ OpenEdX deployed$(NC)"

redeploy:
	@echo "$(YELLOW)Redeploying OpenEdX pods...$(NC)"
	kubectl rollout restart deployment/openedx-lms deployment/openedx-cms deployment/openedx-worker -n $(NAMESPACE)
	@echo "$(BLUE)Waiting for rollout...$(NC)"
	kubectl rollout status deployment/openedx-lms -n $(NAMESPACE) --timeout=600s
	kubectl rollout status deployment/openedx-cms -n $(NAMESPACE) --timeout=600s
	kubectl rollout status deployment/openedx-worker -n $(NAMESPACE) --timeout=600s
	@echo "$(GREEN)✓ Rollout complete$(NC)"

# Backup and recovery
backup:
	@echo "$(BLUE)Running backup...$(NC)"
	@bash $(SCRIPTS_DIR)/backup.sh
	@echo "$(GREEN)✓ Backup completed$(NC)"

restore:
	@echo "$(RED)WARNING: This will restore from backup!$(NC)"
	@read -p "Enter backup date (YYYYMMDD_HHMMSS): " backup_date && \
	bash $(SCRIPTS_DIR)/restore.sh $$backup_date
	@echo "$(GREEN)✓ Restore completed$(NC)"

# Monitoring and logs
monitoring:
	@echo "$(BLUE)Setting up port forwarding to Grafana...$(NC)"
	@echo "$(YELLOW)Grafana will be available at: http://localhost:3000$(NC)"
	@echo "$(YELLOW)Username: admin$(NC)"
	@echo "$(YELLOW)Password: $(shell kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)$(NC)"
	@echo ""
	kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

logs:
	@echo "$(BLUE)Fetching OpenEdX pod logs...$(NC)"
	@echo "$(YELLOW)LMS Logs:$(NC)"
	kubectl logs -n $(NAMESPACE) -l app=openedx,component=lms --tail=100 -f

logs-cms:
	@echo "$(BLUE)Fetching CMS pod logs...$(NC)"
	kubectl logs -n $(NAMESPACE) -l app=openedx,component=cms --tail=100 -f

logs-worker:
	@echo "$(BLUE)Fetching Worker pod logs...$(NC)"
	kubectl logs -n $(NAMESPACE) -l app=openedx,component=worker --tail=100 -f

# Status checks
status:
	@echo "$(BLUE)========== Cluster Status ==========$(NC)"
	@echo "$(GREEN)Cluster Nodes:$(NC)"
	@kubectl get nodes
	@echo ""
	@echo "$(GREEN)OpenEdX Pods:$(NC)"
	@kubectl get pods -n $(NAMESPACE)
	@echo ""
	@echo "$(GREEN)Services:$(NC)"
	@kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "$(GREEN)Ingress:$(NC)"
	@kubectl get ingress -n $(NAMESPACE)
	@echo ""
	@echo "$(GREEN)HPA Status:$(NC)"
	@kubectl get hpa -n $(NAMESPACE)
	@echo ""
	@echo "$(GREEN)PVC Status:$(NC)"
	@kubectl get pvc -n $(NAMESPACE)
	@echo ""

describe-pod:
	@echo "$(BLUE)Enter pod name to describe:$(NC)"
	@read -p "Pod name: " pod_name && kubectl describe pod $$pod_name -n $(NAMESPACE)

# Database checks
db-status:
	@echo "$(BLUE)Checking database connectivity...$(NC)"
	@echo "$(YELLOW)MySQL Health:$(NC)"
	@kubectl run -it --rm mysql-check --image=mysql:8.0 --restart=Never -- \
		mysql -h$$(kubectl get configmap openedx-config -n $(NAMESPACE) -o jsonpath='{.data.MYSQL_HOST}') \
		-u$$(kubectl get secret openedx-db-credentials -n $(NAMESPACE) -o jsonpath='{.data.mysql_username}' | base64 -d) \
		-p$$(kubectl get secret openedx-db-credentials -n $(NAMESPACE) -o jsonpath='{.data.mysql_password}' | base64 -d) \
		-e "SELECT 'MySQL OK' AS status;"
	@echo "$(YELLOW)Redis Health:$(NC)"
	@kubectl run -it --rm redis-check --image=redis:7.0 --restart=Never -- \
		redis-cli -h $$(kubectl get configmap openedx-config -n $(NAMESPACE) -o jsonpath='{.data.REDIS_HOST}') \
		-a $$(kubectl get secret openedx-db-credentials -n $(NAMESPACE) -o jsonpath='{.data.redis_auth_token}' | base64 -d) \
		PING

# Utility targets
clean:
	@echo "$(BLUE)Cleaning up local files...$(NC)"
	rm -f $(TERRAFORM_DIR)/tfplan-*
	rm -f $(TERRAFORM_DIR)/*.tfstate*
	rm -f $(TERRAFORM_DIR)/outputs.json
	rm -rf backups/
	rm -rf restore/
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

docs:
	@echo "$(BLUE)Opening documentation...$(NC)"
	@if command -v open &> /dev/null; then \
		open $(DOCS_DIR)/DEPLOYMENT_GUIDE.md; \
	elif command -v xdg-open &> /dev/null; then \
		xdg-open $(DOCS_DIR)/DEPLOYMENT_GUIDE.md; \
	else \
		echo "Please open $(DOCS_DIR)/DEPLOYMENT_GUIDE.md manually"; \
	fi

# Advanced operations
scale-lms:
	@echo "$(BLUE)Enter desired number of LMS replicas:$(NC)"
	@read -p "Replicas: " replicas && kubectl scale deployment openedx-lms --replicas=$$replicas -n $(NAMESPACE)

scale-cms:
	@echo "$(BLUE)Enter desired number of CMS replicas:$(NC)"
	@read -p "Replicas: " replicas && kubectl scale deployment openedx-cms --replicas=$$replicas -n $(NAMESPACE)

exec-lms:
	@echo "$(BLUE)Opening shell in LMS pod...$(NC)"
	@kubectl exec -it $$(kubectl get pods -n $(NAMESPACE) -l app=openedx,component=lms -o jsonpath='{.items[0].metadata.name}') -n $(NAMESPACE) -- /bin/bash

# Comprehensive setup
setup: init validate plan apply kubeconfig deploy status
	@echo "$(GREEN)✓ OpenEdX on AWS EKS setup complete!$(NC)"
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Update DNS records to point to LoadBalancer URL"
	@echo "  2. Configure SSL certificates"
	@echo "  3. Run database migrations"
	@echo "  4. Create admin user and configure OpenEdX"

# All-in-one teardown
teardown: destroy clean
	@echo "$(GREEN)✓ Complete teardown finished$(NC)"

.DEFAULT_GOAL := help
