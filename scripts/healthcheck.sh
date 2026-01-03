#!/bin/bash
# ===========================================
# n8n Health Check Script
# ===========================================
# This script performs comprehensive health checks on all n8n components
#
# Usage: ./healthcheck.sh
# Cron (optional): */15 * * * * /opt/n8n/scripts/healthcheck.sh >> /var/log/n8n-health.log
# ===========================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f /opt/n8n/.env ]; then
    export $(grep -v '^#' /opt/n8n/.env | xargs)
fi

DOMAIN=${DOMAIN:-n8n.example.com}

echo "=== n8n Health Check ==="
echo "Date: $(date)"
echo ""

# ===========================================
# 1. Container Status
# ===========================================
echo "Container Status:"
echo "─────────────────────────────────────"

if command -v docker compose &> /dev/null; then
    docker compose -f /opt/n8n/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
else
    docker ps --filter "name=n8n" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
fi
echo ""

# ===========================================
# 2. n8n Health Endpoint
# ===========================================
echo "n8n Health Endpoint:"
echo "─────────────────────────────────────"

HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" https://${DOMAIN}/healthz 2>/dev/null || echo "000")

if [ "$HEALTH_CHECK" = "200" ]; then
    echo -e "${GREEN}✓${NC} n8n is responding (HTTP 200)"
else
    echo -e "${RED}✗${NC} n8n health check failed (HTTP $HEALTH_CHECK)"
fi
echo ""

# ===========================================
# 3. SSL Certificate Status
# ===========================================
echo "SSL Certificate:"
echo "─────────────────────────────────────"

CERT_INFO=$(echo | openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} SSL Certificate is valid"
    echo "$CERT_INFO" | sed 's/^/  /'
    
    # Check expiry
    EXPIRY_DATE=$(echo "$CERT_INFO" | grep "notAfter" | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
    
    if [ $DAYS_UNTIL_EXPIRY -lt 30 ]; then
        echo -e "  ${YELLOW}⚠${NC} Certificate expires in ${DAYS_UNTIL_EXPIRY} days"
    else
        echo -e "  ${GREEN}✓${NC} Certificate valid for ${DAYS_UNTIL_EXPIRY} days"
    fi
else
    echo -e "${RED}✗${NC} Unable to verify SSL certificate"
fi
echo ""

# ===========================================
# 4. Database Connectivity
# ===========================================
echo "Database Connectivity:"
echo "─────────────────────────────────────"

DB_CHECK=$(docker exec n8n-postgres pg_isready -U ${POSTGRES_USER:-n8n} -d ${POSTGRES_DB:-n8n} 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} PostgreSQL is ready"
    # Get database size
    DB_SIZE=$(docker exec n8n-postgres psql -U ${POSTGRES_USER:-n8n} -d ${POSTGRES_DB:-n8n} -t -c "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB:-n8n}'));" 2>/dev/null | xargs)
    echo "  Database size: ${DB_SIZE}"
else
    echo -e "${RED}✗${NC} PostgreSQL connection failed"
fi
echo ""

# ===========================================
# 5. Redis Connectivity
# ===========================================
echo "Redis Connectivity:"
echo "─────────────────────────────────────"

REDIS_CHECK=$(docker exec n8n-redis redis-cli ping 2>/dev/null)

if [ "$REDIS_CHECK" = "PONG" ]; then
    echo -e "${GREEN}✓${NC} Redis is responding"
    # Get Redis info
    REDIS_USED_MEM=$(docker exec n8n-redis redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
    REDIS_KEYS=$(docker exec n8n-redis redis-cli dbsize 2>/dev/null | cut -d: -f2 | tr -d '\r')
    echo "  Memory used: ${REDIS_USED_MEM}"
    echo "  Keys stored: ${REDIS_KEYS}"
else
    echo -e "${RED}✗${NC} Redis connection failed"
fi
echo ""

# ===========================================
# 6. System Resources
# ===========================================
echo "System Resources:"
echo "─────────────────────────────────────"

# Disk usage
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}')
DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
echo "Disk Usage: ${DISK_USAGE} used, ${DISK_AVAIL} available"

if [ "${DISK_USAGE%?}" -ge 90 ]; then
    echo -e "  ${RED}⚠${NC} WARNING: Disk usage is high!"
elif [ "${DISK_USAGE%?}" -ge 80 ]; then
    echo -e "  ${YELLOW}⚠${NC} CAUTION: Disk usage is above 80%"
fi

# Memory usage
MEM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
MEM_USED=$(free -h | grep Mem | awk '{print $3}')
MEM_PERCENT=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
echo "Memory Usage: ${MEM_USED} / ${MEM_TOTAL} (${MEM_PERCENT}%)"

if [ "$MEM_PERCENT" -ge 90 ]; then
    echo -e "  ${RED}⚠${NC} WARNING: Memory usage is high!"
elif [ "$MEM_PERCENT" -ge 80 ]; then
    echo -e "  ${YELLOW}⚠${NC} CAUTION: Memory usage is above 80%"
fi

# Docker container resource usage
echo ""
echo "Container Resources:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "n8n|traefik|postgres|redis"

echo ""

# ===========================================
# 7. Recent Logs Check
# ===========================================
echo "Recent Error Logs (last hour):"
echo "─────────────────────────────────────"

ERROR_COUNT=$(docker compose -f /opt/n8n/docker-compose.yml logs --since=1h 2>/dev/null | grep -i "error\|fatal\|critical" | wc -l)

if [ "$ERROR_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC} Found ${ERROR_COUNT} error(s) in the last hour"
    echo "  Run: docker compose logs --tail=50 | grep -i error"
else
    echo -e "${GREEN}✓${NC} No errors in the last hour"
fi
echo ""

# ===========================================
# 8. Backup Status
# ===========================================
echo "Backup Status:"
echo "─────────────────────────────────────"

LATEST_BACKUP=$(ls -t /opt/n8n/backups/postgres/*.sql.gz 2>/dev/null | head -1)

if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_AGE=$(find "$LATEST_BACKUP" -mtime +1 2>/dev/null)
    if [ -n "$BACKUP_AGE" ]; then
        echo -e "${YELLOW}⚠${NC} Latest backup is older than 24 hours"
    else
        echo -e "${GREEN}✓${NC} Recent backup found"
    fi
    echo "  Latest: $(basename $LATEST_BACKUP)"
    echo "  Date: $(stat -c %y "$LATEST_BACKUP" 2>/dev/null | cut -d' ' -f1)"
    echo "  Size: $(du -h "$LATEST_BACKUP" | cut -f1)"
else
    echo -e "${RED}✗${NC} No backups found"
fi
echo ""

echo "=== Health Check Complete ==="
