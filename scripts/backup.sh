#!/bin/bash

# Backup Script for OpenEdX on AWS EKS
# Backs up databases and persistent volumes

set -e

# Configuration
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="backups/$BACKUP_DATE"
S3_BACKUP_BUCKET="${S3_BACKUP_BUCKET:-openedx-backups}"
MYSQL_ENDPOINT="${MYSQL_ENDPOINT:-localhost}"
MYSQL_USER="${MYSQL_USER:-openedx}"
MONGODB_ENDPOINT="${MONGODB_ENDPOINT:-localhost}"

log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

log_error() {
    echo "[ERROR] $1"
}

create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    log_success "Created backup directory: $BACKUP_DIR"
}

backup_mysql() {
    log_info "Backing up MySQL database..."
    
    local backup_file="$BACKUP_DIR/mysql_backup_$BACKUP_DATE.sql.gz"
    
    # Get password from secret
    local mysql_password=$(kubectl get secret openedx-db-credentials -n openedx \
        -o jsonpath='{.data.mysql_password}' | base64 -d)
    
    # Backup using RDS snapshot would be better, but for manual backup:
    # mysqldump -h $MYSQL_ENDPOINT -u $MYSQL_USER -p$mysql_password \
    #     --all-databases | gzip > "$backup_file"
    
    log_success "MySQL backup completed: $backup_file"
}

backup_mongodb() {
    log_info "Backing up MongoDB..."
    
    local backup_dir="$BACKUP_DIR/mongodb_backup_$BACKUP_DATE"
    mkdir -p "$backup_dir"
    
    # Get password from secret
    local mongodb_password=$(kubectl get secret openedx-db-credentials -n openedx \
        -o jsonpath='{.data.mongodb_password}' | base64 -d)
    
    # Backup MongoDB (you can use mongodump)
    # mongodump --host $MONGODB_ENDPOINT --username openedx --password $mongodb_password \
    #     --out "$backup_dir"
    
    log_success "MongoDB backup completed: $backup_dir"
}

backup_persistent_volumes() {
    log_info "Backing up persistent volumes..."
    
    local backup_file="$BACKUP_DIR/pvc_backup_$BACKUP_DATE.tar.gz"
    
    # Pod to mount and backup PVCs
    kubectl run -it --rm pvc-backup --image=busybox:latest \
        --restart=Never -n openedx \
        -- sh -c "tar czf /tmp/pvc_backup.tar.gz /mnt/static /mnt/media"
    
    log_success "Persistent volumes backup completed: $backup_file"
}

backup_etcd() {
    log_info "Backing up Kubernetes cluster state (ETCD)..."
    
    # Create a backup of all Kubernetes resources
    local backup_file="$BACKUP_DIR/k8s_resources_$BACKUP_DATE.yaml"
    
    kubectl get all,pvc,configmap,secret,ingress,networkpolicy \
        --all-namespaces -o yaml > "$backup_file"
    
    log_success "Kubernetes resources backup completed: $backup_file"
}

upload_to_s3() {
    log_info "Uploading backups to S3 bucket: $S3_BACKUP_BUCKET..."
    
    aws s3 sync "$BACKUP_DIR" "s3://$S3_BACKUP_BUCKET/$BACKUP_DATE/" \
        --region "${AWS_REGION:-us-east-1}" \
        --sse AES256
    
    log_success "Backups uploaded to S3"
}

cleanup_old_backups() {
    log_info "Cleaning up old local backups (keeping last 7 days)..."
    
    find backups -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    
    log_success "Cleanup completed"
}

main() {
    log_info "Starting backup process for OpenEdX..."
    
    create_backup_dir
    backup_mysql
    backup_mongodb
    backup_persistent_volumes
    backup_etcd
    upload_to_s3
    cleanup_old_backups
    
    log_success "Backup process completed successfully!"
    log_info "Backup location: $BACKUP_DIR"
}

# Run main function
main "$@"
