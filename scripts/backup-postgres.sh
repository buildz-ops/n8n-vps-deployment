#!/bin/bash
# ===========================================
# PostgreSQL Backup Script for n8n
# ===========================================
# This script creates compressed backups of the n8n PostgreSQL database
# with automatic retention management
#
# Usage: ./backup-postgres.sh
# Cron: 0 2 * * * /opt/n8n/scripts/backup-postgres.sh
# ===========================================

set -e

# Configuration
CONTAINER_NAME="n8n-postgres"
BACKUP_DIR="/opt/n8n/backups/postgres"
POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
RETENTION_DAYS=7
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/${POSTGRES_DB}_${DATE}.sql.gz"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Start backup
echo "[$(date)] Starting backup of ${POSTGRES_DB}..."

# Create compressed backup
if docker exec -t ${CONTAINER_NAME} pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} | gzip > "${BACKUP_FILE}"; then
    # Verify backup was created and is not empty
    if [ -f "${BACKUP_FILE}" ] && [ -s "${BACKUP_FILE}" ]; then
        echo "[$(date)] Backup successful: ${BACKUP_FILE}"
        echo "Size: $(du -h ${BACKUP_FILE} | cut -f1)"
    else
        echo "[$(date)] ERROR: Backup failed - file is empty or doesn't exist!"
        exit 1
    fi
else
    echo "[$(date)] ERROR: Backup command failed!"
    exit 1
fi

# Remove old backups (older than RETENTION_DAYS)
echo "[$(date)] Removing backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "*.sql.gz" -type f -mtime +${RETENTION_DAYS} -delete

# List recent backups
echo "[$(date)] Recent backups:"
ls -lht "${BACKUP_DIR}"/*.sql.gz 2>/dev/null | head -5 || echo "No backups found"

echo "[$(date)] Backup completed successfully!"
