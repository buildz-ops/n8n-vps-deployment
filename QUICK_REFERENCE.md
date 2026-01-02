# n8n Quick Reference Guide

Essential commands and configurations for daily n8n VPS management.

## 📍 Quick Navigation

- [Common Operations](#common-operations)
- [Container Management](#container-management)
- [Monitoring & Logs](#monitoring--logs)
- [Backup & Restore](#backup--restore)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Maintenance](#maintenance)

---

## Common Operations

### Access n8n Web Interface

```
https://n8n.YOUR_DOMAIN.com
```

### Navigate to Project Directory

```bash
cd /opt/n8n
```

### Check Service Status

```bash
docker compose ps
```

### Quick Health Check

```bash
/opt/n8n/scripts/healthcheck.sh
```

---

## Container Management

### Start All Services

```bash
docker compose up -d
```

### Stop All Services

```bash
docker compose down
```

### Restart All Services

```bash
docker compose restart
```

### Restart Specific Service

```bash
# Restart n8n only
docker compose restart n8n

# Restart worker only
docker compose restart n8n-worker

# Restart Traefik (SSL proxy)
docker compose restart traefik

# Restart PostgreSQL
docker compose restart postgres

# Restart Redis
docker compose restart redis
```

### Update to Latest Version

```bash
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Verify update
docker compose ps
docker compose logs --tail=50 n8n
```

### Force Recreate Containers

```bash
docker compose up -d --force-recreate
```

---

## Monitoring & Logs

### View All Logs (Follow Mode)

```bash
docker compose logs -f
```

### View Specific Service Logs

```bash
# n8n main service
docker compose logs -f n8n

# Worker logs
docker compose logs -f n8n-worker

# Traefik (proxy/SSL)
docker compose logs -f traefik

# PostgreSQL
docker compose logs -f postgres

# Redis
docker compose logs -f redis
```

### View Last N Lines

```bash
# Last 100 lines
docker compose logs --tail=100 n8n

# Last 50 lines with timestamps
docker compose logs --tail=50 --timestamps n8n
```

### Search Logs for Errors

```bash
# All error logs
docker compose logs | grep -i error

# Last hour errors
docker compose logs --since=1h | grep -i "error\|fatal"

# n8n errors only
docker compose logs n8n | grep -i error
```

### Real-Time Resource Usage

```bash
# All containers
docker stats

# Specific containers
docker stats n8n n8n-worker n8n-postgres n8n-redis traefik
```

### System Resource Usage

```bash
# Memory
free -h

# Disk space
df -h

# Top processes
htop
```

---

## Backup & Restore

### Run Manual Backup

```bash
# PostgreSQL only
/opt/n8n/scripts/backup-postgres.sh

# Complete backup (database + volumes + configs)
/opt/n8n/scripts/backup-all.sh
```

### List Available Backups

```bash
# PostgreSQL backups
ls -lht /opt/n8n/backups/postgres/

# Volume backups
ls -lht /opt/n8n/backups/volumes/

# Config backups
ls -lht /opt/n8n/backups/config_*.tar.gz
```

### Restore PostgreSQL Database

```bash
# Stop n8n services
docker compose stop n8n n8n-worker

# Restore database (replace with your backup file)
gunzip -c /opt/n8n/backups/postgres/n8n_YYYY-MM-DD_HH-MM-SS.sql.gz | \
    docker exec -i n8n-postgres psql -U n8n -d n8n

# Restart services
docker compose start n8n n8n-worker
```

### Verify Backups

```bash
# Check last backup age
ls -lt /opt/n8n/backups/postgres/*.sql.gz | head -1

# Check backup size
du -sh /opt/n8n/backups/
```

---

## Troubleshooting

### Check Container Health

```bash
docker compose ps
```

Expected: All services show "healthy" or "Up"

### Verify SSL Certificate

```bash
# Check certificate
curl -I https://n8n.YOUR_DOMAIN.com

# Certificate expiry
echo | openssl s_client -connect n8n.YOUR_DOMAIN.com:443 -servername n8n.YOUR_DOMAIN.com 2>/dev/null | openssl x509 -noout -dates
```

### Test n8n Health Endpoint

```bash
curl https://n8n.YOUR_DOMAIN.com/healthz
# Expected: {"status":"ok"}
```

### Test Webhook

```bash
curl -X POST https://n8n.YOUR_DOMAIN.com/webhook/YOUR_PATH \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

### Check Database Connection

```bash
# PostgreSQL status
docker exec -it n8n-postgres pg_isready -U n8n -d n8n

# Connect to database
docker exec -it n8n-postgres psql -U n8n -d n8n

# Inside psql:
# \dt          -- List tables
# \l+          -- List databases with sizes
# \q           -- Quit
```

### Check Redis Connection

```bash
# Test connection
docker exec -it n8n-redis redis-cli ping
# Expected: PONG

# Check queue keys
docker exec -it n8n-redis redis-cli keys "*bull*"

# Check memory usage
docker exec -it n8n-redis redis-cli info memory
```

### View Environment Variables

```bash
# View .env file
cat /opt/n8n/.env

# Check variables in running container
docker compose exec n8n printenv | grep N8N
```

### Reset SSL Certificates

```bash
# Stop Traefik
docker compose stop traefik

# Remove certificate file
rm /opt/n8n/traefik/acme.json

# Recreate with correct permissions
touch /opt/n8n/traefik/acme.json
chmod 600 /opt/n8n/traefik/acme.json

# Start Traefik
docker compose start traefik

# Watch certificate acquisition
docker compose logs -f traefik | grep -i acme
```

### Restart Services in Order

```bash
# Start database first
docker compose restart postgres
sleep 10

# Then Redis
docker compose restart redis
sleep 5

# Then n8n and worker
docker compose restart n8n n8n-worker
```

### Check Port Accessibility

```bash
# Check if ports are listening
sudo ss -tulpn | grep -E ':80|:443'

# Test HTTP redirect
curl -I http://n8n.YOUR_DOMAIN.com

# Test HTTPS
curl -I https://n8n.YOUR_DOMAIN.com
```

---

## Security

### Firewall Status

```bash
# Check UFW status
sudo ufw status verbose

# Check recent blocks
sudo tail -f /var/log/ufw.log
```

### Fail2ban Status

```bash
# Check Fail2ban status
sudo fail2ban-client status

# Check SSH jail
sudo fail2ban-client status sshd

# List banned IPs
sudo fail2ban-client banned
```

### Update System Packages

```bash
sudo apt update && sudo apt upgrade -y
```

### Review Access Logs

```bash
# Traefik access logs (JSON format)
tail -f /opt/n8n/traefik/logs/access.log | jq .

# Filter by status code
tail -f /opt/n8n/traefik/logs/access.log | jq 'select(.DownstreamStatus >= 400)'
```

---

## Maintenance

### Database Maintenance

```bash
# Vacuum and analyze
docker exec -it n8n-postgres psql -U n8n -d n8n -c "VACUUM ANALYZE;"

# Check database size
docker exec -it n8n-postgres psql -U n8n -d n8n -c "\l+"

# Check table sizes
docker exec -it n8n-postgres psql -U n8n -d n8n -c "\dt+"
```

### Clean Up Docker Resources

```bash
# Remove unused images, containers, networks
docker system prune -a

# Show current usage
docker system df

# Remove unused volumes (CAREFUL!)
docker volume prune
```

### Verify Disk Space

```bash
# Overall disk usage
df -h

# Docker directory usage
sudo du -sh /var/lib/docker/

# Backup directory usage
du -sh /opt/n8n/backups/

# Find large files
sudo find /opt/n8n -type f -size +100M -exec ls -lh {} \;
```

### Check Container Logs Size

```bash
# Check log sizes
sudo du -sh /var/lib/docker/containers/*/

# Rotate logs manually
docker compose down
docker compose up -d
```

### Update Docker and Docker Compose

```bash
# Update Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Verify versions
docker --version
docker compose version
```

---

## Configuration Files

### Main Files Location

```
/opt/n8n/
├── docker-compose.yml       # Main orchestration file
├── .env                      # Environment variables (SECRETS)
├── traefik/
│   ├── traefik.yml          # Traefik static config
│   ├── config/
│   │   └── dynamic.yml      # Traefik dynamic config
│   └── acme.json            # SSL certificates (auto-generated)
└── scripts/
    ├── backup-postgres.sh   # Database backup
    ├── backup-all.sh        # Complete backup
    └── healthcheck.sh       # Health check script
```

### Edit Configuration Files

```bash
# Edit environment variables
nano /opt/n8n/.env

# Edit docker-compose.yml
nano /opt/n8n/docker-compose.yml

# Edit Traefik config
nano /opt/n8n/traefik/traefik.yml
```

### Apply Configuration Changes

```bash
# After editing .env or docker-compose.yml
docker compose up -d

# After editing Traefik config
docker compose restart traefik
```

---

## DNS & SSL

### Verify DNS

```bash
# Check DNS resolution
dig n8n.YOUR_DOMAIN.com +short

# Check from multiple DNS servers
dig @8.8.8.8 n8n.YOUR_DOMAIN.com +short
dig @1.1.1.1 n8n.YOUR_DOMAIN.com +short

# Full DNS info
nslookup n8n.YOUR_DOMAIN.com
```

### SSL Certificate Info

```bash
# Certificate details
echo | openssl s_client -connect n8n.YOUR_DOMAIN.com:443 -servername n8n.YOUR_DOMAIN.com 2>/dev/null | openssl x509 -noout -text

# Certificate chain
echo | openssl s_client -connect n8n.YOUR_DOMAIN.com:443 -showcerts 2>/dev/null

# Check expiry
echo | openssl s_client -connect n8n.YOUR_DOMAIN.com:443 -servername n8n.YOUR_DOMAIN.com 2>/dev/null | openssl x509 -noout -dates
```

---

## Useful One-Liners

### Check Everything is Running

```bash
docker compose ps && curl -s https://n8n.YOUR_DOMAIN.com/healthz && echo " - Health OK"
```

### Quick Backup Before Changes

```bash
/opt/n8n/scripts/backup-all.sh && echo "Backup complete - safe to proceed"
```

### Monitor All Services

```bash
watch -n 2 'docker compose ps && echo "" && docker stats --no-stream'
```

### Check for Recent Errors

```bash
docker compose logs --since=1h | grep -i "error\|fatal" | tail -20
```

### Disk Space Alert

```bash
df -h / | awk 'NR==2 {if (substr($5,1,length($5)-1) > 80) print "WARNING: Disk usage is " $5}'
```

---

## Emergency Procedures

### Complete Restart

```bash
cd /opt/n8n
docker compose down
sleep 5
docker compose up -d
```

### Emergency Stop

```bash
docker compose stop
```

### View All Container Details

```bash
docker compose ps -a
docker inspect n8n
```

### Access Container Shell

```bash
# n8n container
docker exec -it n8n /bin/sh

# PostgreSQL container
docker exec -it n8n-postgres /bin/sh

# Redis container
docker exec -it n8n-redis /bin/sh
```

---

## URLs & Ports

| Service | Internal Port | External Port | Protocol |
|---------|---------------|---------------|----------|
| n8n | 5678 | - | HTTP (internal) |
| Traefik | - | 80 | HTTP (redirect) |
| Traefik | - | 443 | HTTPS |
| PostgreSQL | 5432 | - | TCP (internal) |
| Redis | 6379 | - | TCP (internal) |

### Important URLs

- **n8n Interface**: `https://n8n.YOUR_DOMAIN.com`
- **Health Endpoint**: `https://n8n.YOUR_DOMAIN.com/healthz`
- **Webhook Base**: `https://n8n.YOUR_DOMAIN.com/webhook/`

---

## Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN` | Your n8n domain | `n8n.example.com` |
| `POSTGRES_USER` | Database username | `n8n` |
| `POSTGRES_PASSWORD` | Database password | `SECURE_PASSWORD` |
| `POSTGRES_DB` | Database name | `n8n` |
| `N8N_ENCRYPTION_KEY` | n8n credential encryption | `32_char_hex_string` |
| `LETSENCRYPT_EMAIL` | SSL certificate email | `admin@example.com` |
| `TZ` | Timezone | `UTC`, `Europe/Madrid` |

---

## Performance Tuning

### PostgreSQL Connection Count

```bash
# Current connections
docker exec -it n8n-postgres psql -U n8n -d n8n -c "SELECT count(*) FROM pg_stat_activity;"

# Connection details
docker exec -it n8n-postgres psql -U n8n -d n8n -c "SELECT * FROM pg_stat_activity;"
```

### Redis Memory

```bash
# Memory usage
docker exec -it n8n-redis redis-cli info memory | grep used_memory_human

# Max memory setting
docker exec -it n8n-redis redis-cli config get maxmemory
```

### Container Resource Limits

Check `docker-compose.yml` for memory limits:
- PostgreSQL: 4GB
- Redis: 1GB  
- n8n: 2GB
- n8n-worker: 2GB
- Traefik: 256MB

---

## Getting Help

- **n8n Documentation**: https://docs.n8n.io/
- **n8n Community**: https://community.n8n.io/
- **Traefik Docs**: https://doc.traefik.io/traefik/
- **GitHub Issues**: Open an issue in this repository

---

**Remember**: Always backup before making changes! 🛡️
