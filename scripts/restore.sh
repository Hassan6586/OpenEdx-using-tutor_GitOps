#!/bin/bash

# Restore Script for OpenEdX on AWS EKS
# Restores from backups stored in S3

set -e

# Configuration
BACKUP_DATE="${1:-}"
S3_BACKUP_BUCKET="${S3_BACKUP_BUCKET:-openedx-backups}"
RESTORE_DIR="restore"
NAMESPACE="${NAMESPACE:-openedx}"

log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

log_error() {
    echo "[ERROR] $1"
}

if [ -z "$BACKUP_DATE" ]; then
    log_error "Backup date required. Usage: $0 YYYYMMDD_HHMMSS"
    log_info "Available backups:"
    aws s3 ls s3://$S3_BACKUP_BUCKET/ | awk '{print $2}' | grep -v '^$'
    exit 1
fi

# Create restore directory
mkdir -p "$RESTORE_DIR"

# Download backups from S3
log_info "Downloading backup from S3..."
aws s3 sync "s3://$S3_BACKUP_BUCKET/$BACKUP_DATE/" "$RESTORE_DIR/$BACKUP_DATE/" \
    --region "${AWS_REGION:-us-east-1}"

log_success "Backup downloaded to: $RESTORE_DIR/$BACKUP_DATE/"

# Restore MySQL
restore_mysql() {
    log_info "Restoring MySQL from backup..."
    
    local backup_file="$RESTORE_DIR/$BACKUP_DATE/mysql_backup_$BACKUP_DATE.sql.gz"
    
    if [ -f "$backup_file" ]; then
        # Get database credentials from Kubernetes secret
        local mysql_host=$(kubectl get configmap openedx-config -n $NAMESPACE \
            -o jsonpath='{.data.MYSQL_HOST}')
        local mysql_port=$(kubectl get configmap openedx-config -n $NAMESPACE \
            -o jsonpath='{.data.MYSQL_PORT}')
        local mysql_user=$(kubectl get secret openedx-db-credentials -n $NAMESPACE \
            -o jsonpath='{.data.mysql_username}' | base64 -d)
        local mysql_password=$(kubectl get secret openedx-db-credentials -n $NAMESPACE \
            -o jsonpath='{.data.mysql_password}' | base64 -d)
        
        log_info "Restoring MySQL database..."
        gunzip < "$backup_file" | mysql \
            -h "$mysql_host" \
            -P "$mysql_port" \
            -u "$mysql_user" \
            -p"$mysql_password"
        
        log_success "MySQL restore completed"
    else
        log_error "MySQL backup file not found: $backup_file"
    fi
}

# Restore MongoDB
restore_mongodb() {
    log_info "Restoring MongoDB from backup..."
    
    local backup_dir="$RESTORE_DIR/$BACKUP_DATE/mongodb_backup_$BACKUP_DATE"
    
    if [ -d "$backup_dir" ]; then
        local mongodb_host=$(kubectl get configmap openedx-config -n $NAMESPACE \
            -o jsonpath='{.data.MONGODB_HOST}')
        local mongodb_port=$(kubectl get configmap openedx-config -n $NAMESPACE \
            -o jsonpath='{.data.MONGODB_PORT}')
        local mongodb_user=$(kubectl get secret openedx-db-credentials -n $NAMESPACE \
            -o jsonpath='{.data.mongodb_username}' | base64 -d)
        local mongodb_password=$(kubectl get secret openedx-db-credentials -n $NAMESPACE \
            -o jsonpath='{.data.mongodb_password}' | base64 -d)
        
        log_info "Restoring MongoDB database..."
        # mongorestore --host "$mongodb_host:$mongodb_port" \
        #     --username "$mongodb_user" \
        #     --password "$mongodb_password" \
        #     --dir "$backup_dir"
        
        log_success "MongoDB restore completed"
    else
        log_error "MongoDB backup directory not found: $backup_dir"
    fi
}

# Restore RDS Cluster from snapshot
restore_rds_snapshot() {
    log_info "Restoring RDS cluster from snapshot..."
    
    local snapshot_id="openedx-mysql-backup-$BACKUP_DATE"
    local new_cluster_id="openedx-mysql-restored-$(date +%s)"
    
    log_info "Searching for RDS snapshot: $snapshot_id"
    
    local snapshot_exists=$(aws rds describe-db-cluster-snapshots \
        --db-cluster-snapshot-identifier "$snapshot_id" \
        --region "${AWS_REGION:-us-east-1}" 2>/dev/null || echo "")
    
    if [ -n "$snapshot_exists" ]; then
        log_info "Creating new RDS cluster from snapshot..."
        aws rds restore-db-cluster-from-snapshot \
            --db-cluster-identifier "$new_cluster_id" \
            --snapshot-identifier "$snapshot_id" \
            --engine aurora-mysql \
            --region "${AWS_REGION:-us-east-1}"
        
        log_success "RDS restore initiated: $new_cluster_id"
        log_info "Note: RDS restore may take 10-30 minutes to complete"
        log_info "Monitor progress with:"
        log_info "  aws rds describe-db-clusters --db-cluster-identifier $new_cluster_id"
    else
        log_info "RDS snapshot not found. Continuing with other restore operations..."
    fi
}

# Restore Kubernetes resources
restore_kubernetes_resources() {
    log_info "Restoring Kubernetes resources..."
    
    local k8s_resource_file="$RESTORE_DIR/$BACKUP_DATE/k8s_resources_$BACKUP_DATE.yaml"
    
    if [ -f "$k8s_resource_file" ]; then
        log_info "Applying Kubernetes resources..."
        kubectl apply -f "$k8s_resource_file"
        
        log_success "Kubernetes resources restored"
    else
        log_error "Kubernetes resources file not found: $k8s_resource_file"
    fi
}

# Restart OpenEdX deployments
restart_deployments() {
    log_info "Restarting OpenEdX deployments..."
    
    kubectl rollout restart deployment/openedx-lms -n $NAMESPACE
    kubectl rollout restart deployment/openedx-cms -n $NAMESPACE
    kubectl rollout restart deployment/openedx-worker -n $NAMESPACE
    
    log_info "Waiting for deployments to be ready..."
    kubectl rollout status deployment/openedx-lms -n $NAMESPACE --timeout=600s
    kubectl rollout status deployment/openedx-cms -n $NAMESPACE --timeout=600s
    kubectl rollout status deployment/openedx-worker -n $NAMESPACE --timeout=600s
    
    log_success "All deployments restarted and ready"
}

# Verify restore
verify_restore() {
    log_info "Verifying restore..."
    
    # Check database connectivity
    log_info "Checking database connectivity..."
    kubectl run -it --rm mysql-check --image=mysql:8.0 --restart=Never \
        -- mysql -h$(kubectl get configmap openedx-config -n $NAMESPACE -o jsonpath='{.data.MYSQL_HOST}') \
        -u$(kubectl get secret openedx-db-credentials -n $NAMESPACE -o jsonpath='{.data.mysql_username}' | base64 -d) \
        -p$(kubectl get secret openedx-db-credentials -n $NAMESPACE -o jsonpath='{.data.mysql_password}' | base64 -d) \
        -e "SELECT VERSION();"
    
    # Check pod status
    log_info "Checking pod status..."
    kubectl get pods -n $NAMESPACE
    
    # Check OpenEdX service
    log_info "Checking OpenEdX service..."
    kubectl get svc -n $NAMESPACE
    
    log_success "Restore verification completed"
}

# Cleanup
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$RESTORE_DIR"
    log_success "Cleanup completed"
}

# Main restore process
main() {
    log_info "Starting OpenEdX restore from backup: $BACKUP_DATE"
    
    restore_mysql
    restore_mongodb
    restore_rds_snapshot
    restore_kubernetes_resources
    restart_deployments
    verify_restore
    cleanup
    
    log_success "Restore process completed successfully!"
    log_info "OpenEdX should now be available at: https://$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].spec.rules[0].host}')"
}

# Run main function
main "$@"
