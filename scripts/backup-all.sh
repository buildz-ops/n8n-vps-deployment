#!/bin/bash
# ===========================================
# Complete n8n Backup Script
# ===========================================
# This script creates comprehensive backups of:
# - PostgreSQL database
# - Docker volumes (n8n data, Redis data)
# - Configuration files
#
# Usage: ./backup-all.sh
# Cron: 0 2 * * * /opt/n8n/scripts/backup-all.sh >> /var/log/n8n-backup.log 2>&1
# ===========================================

set -e

SCRIPT_DIR="/opt/n8n/scripts"
LOG_FILE="/var/log/n8n-backup.log"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_BASE="/opt/n8n/backups"

echo "=== n8n Backup Started: $(date) ===" | tee -a ${LOG_FILE}

# Source environment variables if .env exists
if [ -f /opt/n8n/.env ]; then
    export $(grep -v '^#' /opt/n8n/.env | xargs)
fi

# ===========================================
# 1. Backup PostgreSQL Database
# ===========================================
echo "[$(date)] Backing up PostgreSQL database..." | tee -a ${LOG_FILE}

if [ -x "${SCRIPT_DIR}/backup-postgres.sh" ]; then
    ${SCRIPT_DIR}/backup-postgres.sh 2>&1 | tee -a ${LOG_FILE}
else
    echo "[$(date)] WARNING: PostgreSQL backup script not found or not executable" | tee -a ${LOG_FILE}
fi

# ===========================================
# 2. Backup Docker Volumes
# ===========================================
echo "[$(date)] Backing up Docker volumes..." | tee -a ${LOG_FILE}

VOLUMES_BACKUP="${BACKUP_BASE}/volumes/volumes_${DATE}.tar.gz"
mkdir -p "${BACKUP_BASE}/volumes"

# Create temporary container to access volumes and create backup
docker run --rm \
    -v n8n_n8n_data:/n8n_data:ro \
    -v n8n_redis_data:/redis_data:ro \
    -v ${BACKUP_BASE}/volumes:/backup \
    alpine tar czf /backup/volumes_${DATE}.tar.gz \
    /n8n_data \
    /redis_data \
    2>/dev/null || {
        echo "[$(date)] WARNING: Volume backup failed or volumes don't exist" | tee -a ${LOG_FILE}
    }

if [ -f "${VOLUMES_BACKUP}" ]; then
    echo "[$(date)] Volume backup successful: ${VOLUMES_BACKUP}" | tee -a ${LOG_FILE}
    echo "Size: $(du -h ${VOLUMES_BACKUP} | cut -f1)" | tee -a ${LOG_FILE}
fi

# ===========================================
# 3. Backup Configuration Files
# ===========================================
echo "[$(date)] Backing up configuration files..." | tee -a ${LOG_FILE}

CONFIG_BACKUP="${BACKUP_BASE}/config_${DATE}.tar.gz"

# Backup configuration files (exclude sensitive data, logs, and backups)
tar czf ${CONFIG_BACKUP} \
    --exclude='backups' \
    --exclude='traefik/logs' \
    --exclude='traefik/acme.json' \
    --exclude='.env' \
    -C /opt/n8n \
    docker-compose.yml \
    .env.example \
    traefik/ \
    scripts/ \
    2>/dev/null || {
        echo "[$(date)] WARNING: Configuration backup incomplete" | tee -a ${LOG_FILE}
    }

if [ -f "${CONFIG_BACKUP}" ]; then
    echo "[$(date)] Configuration backup successful: ${CONFIG_BACKUP}" | tee -a ${LOG_FILE}
    echo "Size: $(du -h ${CONFIG_BACKUP} | cut -f1)" | tee -a ${LOG_FILE}
fi

# ===========================================
# 4. Cleanup Old Backups
# ===========================================
echo "[$(date)] Cleaning up old backups..." | tee -a ${LOG_FILE}

# Remove volume backups older than 7 days
find "${BACKUP_BASE}/volumes" -name "*.tar.gz" -type f -mtime +7 -delete 2>/dev/null || true

# Remove config backups older than 7 days
find "${BACKUP_BASE}" -maxdepth 1 -name "config_*.tar.gz" -type f -mtime +7 -delete 2>/dev/null || true

# ===========================================
# 5. Summary
# ===========================================
echo "" | tee -a ${LOG_FILE}
echo "[$(date)] Backup Summary:" | tee -a ${LOG_FILE}
echo "  PostgreSQL backups: $(ls -1 ${BACKUP_BASE}/postgres/*.sql.gz 2>/dev/null | wc -l)" | tee -a ${LOG_FILE}
echo "  Volume backups: $(ls -1 ${BACKUP_BASE}/volumes/*.tar.gz 2>/dev/null | wc -l)" | tee -a ${LOG_FILE}
echo "  Config backups: $(ls -1 ${BACKUP_BASE}/config_*.tar.gz 2>/dev/null | wc -l)" | tee -a ${LOG_FILE}
echo "" | tee -a ${LOG_FILE}
echo "  Total backup size: $(du -sh ${BACKUP_BASE} | cut -f1)" | tee -a ${LOG_FILE}

echo "=== n8n Backup Completed: $(date) ===" | tee -a ${LOG_FILE}
