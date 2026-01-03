# Troubleshooting - n8n Automated Deployment

Common issues and solutions for the automated deployment script.

---

## Table of Contents

1. [Pre-Flight Check Failures](#pre-flight-check-failures)
2. [Docker Installation Issues](#docker-installation-issues)
3. [DNS Configuration Problems](#dns-configuration-problems)
4. [SSL Certificate Failures](#ssl-certificate-failures)
5. [Container Startup Issues](#container-startup-issues)
6. [Port Conflicts](#port-conflicts)
7. [Memory/Resource Issues](#memoryresource-issues)
8. [Firewall Problems](#firewall-problems)
9. [Update/Upgrade Issues](#updateupgrade-issues)
10. [Recovery Procedures](#recovery-procedures)

---

## Pre-Flight Check Failures

### Error: "Unsupported OS"

**Problem**: Script doesn't recognize your operating system.

**Solution**:
```bash
# Check your OS
cat /etc/os-release

# Supported: Ubuntu 22.04, 24.04, 25.10; Debian 11, 12
# If your OS is different, you may need to modify the script
# or use the manual installation method
```

### Error: "Insufficient RAM"

**Problem**: Less than 8GB RAM detected.

**Solution**:
- **Upgrade VPS**: Recommended for production
- **Continue anyway** (not recommended):
  - Script will use reduced memory limits
  - Performance will be degraded
  - May experience OOM (Out of Memory) kills

**Check RAM**:
```bash
free -h
# Look at "total" in the Mem row
```

### Error: "Insufficient disk space"

**Problem**: Less than 20GB available.

**Solution**:
```bash
# Check disk usage
df -h /

# Clean up space
sudo apt-get clean
sudo apt-get autoremove
docker system prune -a  # If Docker is installed

# Increase disk size at VPS provider
```

### Error: "Cannot detect VPS IP"

**Problem**: Script can't determine public IP address.

**Workaround**:
Manually determine your IP:
```bash
curl -4 ifconfig.me
# Or
curl -4 icanhazip.com

# Then set it manually in the script or provide via CLI
# (requires script modification for manual IP input)
```

---

## Docker Installation Issues

### Error: "GPG key download failed"

**Problem**: Cannot reach Docker's package repository.

**Cause**: Network issues or DNS problems.

**Solution**:
```bash
# Test connectivity
ping -c 3 download.docker.com

# Try alternative DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf.d/google.conf
sudo systemctl restart systemd-resolved

# Retry script
sudo ./deploy-n8n.sh
```

### Error: "Docker installation failed"

**Problem**: Errors during `apt-get install docker-ce`.

**Solution 1** - Use Docker's convenience script:
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

**Solution 2** - Manual installation:
```bash
# Remove old packages
sudo apt-get remove docker docker-engine docker.io containerd runc

# Install from official repository (follow Docker docs)
# Then re-run the deployment script
```

### Error: "permission denied" when running Docker

**Problem**: User not in docker group.

**Solution**:
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login, or:
newgrp docker

# Test
docker run hello-world
```

---

## DNS Configuration Problems

### Warning: "Domain does not resolve"

**Problem**: DNS A record not created or not propagated.

**Solution**:
1. **Verify A record exists**:
   ```bash
   dig +short n8n.example.com
   # Should return your VPS IP
   ```

2. **Check DNS provider**:
   - Log into your DNS provider (Cloudflare, Namecheap, etc.)
   - Verify A record: `n8n` → `YOUR_VPS_IP`
   - TTL: Auto or 300 seconds

3. **Wait for propagation**:
   - Typically: 1-15 minutes
   - Maximum: 24-48 hours (rare)

4. **Test from multiple locations**:
   ```bash
   # Test with different DNS servers
   dig @8.8.8.8 n8n.example.com
   dig @1.1.1.1 n8n.example.com
   ```

5. **Continue anyway** (not recommended):
   - Script offers to continue without DNS
   - SSL certificate will fail
   - You can fix DNS later and restart Traefik

### Warning: "DNS mismatch" (wrong IP)

**Problem**: Domain resolves but to wrong IP address.

**Cause**:
- Old A record not updated
- Multiple A records exist
- Cloudflare proxy enabled (orange cloud)

**Solution**:
```bash
# Check current resolution
dig +short n8n.example.com

# Expected: YOUR_VPS_IP
# If different:
# 1. Update A record in DNS provider
# 2. If using Cloudflare: Disable proxy (gray cloud) initially
# 3. Wait for propagation
# 4. Re-run script
```

---

## SSL Certificate Failures

### Error: "SSL certificate acquisition failed"

**Common Causes**:

#### 1. Port 80 Blocked

**Symptoms**:
```
HTTP challenge failed
Cannot reach domain on port 80
```

**Solution**:
```bash
# Check if port 80 is reachable
curl -I http://n8n.example.com

# Check UFW
sudo ufw status
# Should show: 80/tcp ALLOW

# Check if something is using port 80
sudo ss -tulpn | grep :80

# Check cloud provider firewall
# OVH: Edge Network Firewall
# AWS: Security Groups
# DigitalOcean: Cloud Firewalls
# Ensure port 80 is allowed
```

#### 2. Cloudflare Proxy Enabled

**Symptoms**:
```
SSL works but shows Cloudflare certificate instead of Let's Encrypt
```

**Solution**:
- Log into Cloudflare
- Go to DNS settings
- Click orange cloud → gray cloud (DNS only)
- Wait a few minutes
- Restart Traefik:
  ```bash
  docker compose -f /opt/n8n/docker-compose.yml restart traefik
  ```

#### 3. Rate Limit Exceeded

**Symptoms**:
```
too many certificates already issued for exact set of domains
```

**Cause**: Let's Encrypt rate limits (5 certificates per domain per week).

**Solution**:
- **Wait**: 1 week for rate limit to reset
- **Use staging** (testing):
  ```bash
  # Edit /opt/n8n/traefik/traefik.yml
  # Change:
  caServer: https://acme-staging-v02.api.letsencrypt.org/directory
  # This uses staging environment (not real certs but no rate limit)
  ```

#### 4. acme.json Permission Issues

**Symptoms**:
```
Error saving ACME account
Permission denied
```

**Solution**:
```bash
# Fix permissions
chmod 600 /opt/n8n/traefik/acme.json
chown $USER:$USER /opt/n8n/traefik/acme.json

# Restart Traefik
docker compose -f /opt/n8n/docker-compose.yml restart traefik
```

#### 5. N8N_HOST Mismatch

**Symptoms**:
```
Certificate obtained but doesn't match domain
SSL still showing errors
```

**Critical Configuration**:
```bash
# Verify .env file
cat /opt/n8n/.env | grep DOMAIN
# Output: DOMAIN=n8n.example.com

# Verify docker-compose.yml Traefik label
grep "Host(" /opt/n8n/docker-compose.yml
# Output should have: Host(`${DOMAIN}`)

# Verify n8n environment
grep "N8N_HOST" /opt/n8n/docker-compose.yml
# Output should have: N8N_HOST=${DOMAIN}

# These MUST match exactly!
```

### Reset SSL Certificates

If all else fails, reset and try again:

```bash
cd /opt/n8n

# Stop Traefik
docker compose stop traefik

# Remove certificate storage
rm traefik/acme.json
touch traefik/acme.json
chmod 600 traefik/acme.json

# Start Traefik (will request new certificates)
docker compose start traefik

# Monitor logs
docker compose logs -f traefik
```

---

## Container Startup Issues

### Error: "Container keeps restarting"

**Check logs**:
```bash
cd /opt/n8n

# Check which container is restarting
docker compose ps

# View logs
docker compose logs [container_name]
# Examples: n8n, postgres, redis, traefik, n8n-worker
```

#### PostgreSQL Issues

**Symptoms**:
```
postgres   | FATAL: password authentication failed
postgres   | FATAL: database "n8n" does not exist
```

**Solution**:
```bash
# Check .env file
cat /opt/n8n/.env | grep POSTGRES

# Verify values match in docker-compose.yml

# If database was corrupted:
docker compose down
docker volume rm n8n_postgres_data
docker compose up -d
# WARNING: This deletes all data!
```

#### Redis Issues

**Symptoms**:
```
redis    | Error opening configuration file
redis    | MISCONF Redis is configured to save RDB snapshots
```

**Solution**:
```bash
# Check Redis logs
docker compose logs redis

# Reset Redis data
docker compose stop redis
docker volume rm n8n_redis_data
docker compose start redis
```

#### n8n Issues

**Symptoms**:
```
n8n | Error: Cannot connect to database
n8n | Error: Invalid encryption key
n8n | Error: Redis connection failed
```

**Solutions**:
```bash
# Database connection issue
# Wait for PostgreSQL to be healthy
docker compose logs postgres

# Encryption key issue
# Verify N8N_ENCRYPTION_KEY in .env is correct
# Must be exactly 32 characters hex

# Redis connection issue
docker compose logs redis
# Ensure Redis is healthy before starting n8n
```

### Error: "Healthcheck failed"

**Problem**: Container is running but unhealthy.

**Solution**:
```bash
# Check health status
docker compose ps

# View health check logs
docker inspect [container_name] | jq '.[].State.Health'

# Common fixes:

# n8n health check:
curl http://localhost:5678/healthz
# Should return: {"status":"ok"}

# PostgreSQL health check:
docker exec n8n-postgres pg_isready -U n8n -d n8n

# Redis health check:
docker exec n8n-redis redis-cli ping
# Should return: PONG
```

---

## Port Conflicts

### Error: "Port 80 already in use"

**Check what's using the port**:
```bash
sudo ss -tulpn | grep :80
```

**Common culprits**:
- Apache2
- Nginx
- Another Traefik/reverse proxy

**Solution**:
```bash
# Option 1: Stop conflicting service
sudo systemctl stop apache2
sudo systemctl disable apache2  # Prevent auto-start

# Option 2: Remove conflicting service
sudo apt-get remove apache2

# Then restart deployment
docker compose up -d
```

### Error: "Port 443 already in use"

Same as port 80 - usually the same service.

### Error: "Port 5432 already in use"

**Problem**: PostgreSQL already running on host.

**Solution**:
```bash
# Check
sudo ss -tulpn | grep :5432

# Stop host PostgreSQL
sudo systemctl stop postgresql

# Or use different port in docker-compose.yml
# ports:
#   - "5433:5432"  # Map to different host port
```

---

## Memory/Resource Issues

### Error: "Out of memory" / "Container killed"

**Check logs**:
```bash
# System memory
free -h

# Docker stats
docker stats

# System logs for OOM killer
dmesg | grep -i oom
journalctl -k | grep -i "out of memory"
```

**Solutions**:

#### 1. Increase Swap

```bash
# Check current swap
swapon --show

# Create 2GB swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### 2. Reduce Resource Limits

Edit `/opt/n8n/docker-compose.yml`:

```yaml
# Reduce memory limits for 8GB RAM systems
postgres:
  deploy:
    resources:
      limits:
        memory: 2G  # Instead of 4G

redis:
  deploy:
    resources:
      limits:
        memory: 512M  # Instead of 1G

n8n:
  deploy:
    resources:
        limits:
          memory: 1536M  # Instead of 2G

n8n-worker:
  deploy:
    resources:
      limits:
        memory: 1536M  # Instead of 2G
```

Then:
```bash
docker compose up -d
```

#### 3. Disable n8n Worker (Temporary)

If very low on memory:

```bash
# Edit docker-compose.yml, comment out n8n-worker service
# Then:
docker compose up -d

# WARNING: This disables queue mode!
# Workflows will run in main process only
```

### Error: "No space left on device"

**Check disk usage**:
```bash
df -h /

# Docker disk usage
docker system df
```

**Solutions**:
```bash
# Clean Docker
docker system prune -a --volumes
# WARNING: Removes unused containers, images, volumes

# Clean apt cache
sudo apt-get clean
sudo apt-get autoremove

# Check large files
sudo du -h / | sort -rh | head -20

# Increase disk at VPS provider
```

---

## Firewall Problems

### Error: "Cannot reach n8n from browser"

**Check UFW**:
```bash
sudo ufw status verbose

# Should show:
# 80/tcp ALLOW
# 443/tcp ALLOW
```

**If not allowed**:
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

### Error: "Docker containers can't access internet"

**Cause**: Docker UFW bypass not applied.

**Solution**:
```bash
# Verify fix is applied
grep "BEGIN UFW AND DOCKER" /etc/ufw/after.rules

# If not found, add it:
sudo nano /etc/ufw/after.rules
# Add the UFW Docker bypass fix (see script)

# Reload UFW
sudo ufw reload

# Restart Docker
sudo systemctl restart docker

# Restart containers
docker compose -f /opt/n8n/docker-compose.yml restart
```

### Cloud Provider Firewall

**OVH Edge Network Firewall**:
- Ensure ports 80, 443 allowed
- Log into OVH control panel
- Network → Firewall → Configure

**Hetzner Cloud Firewall**:
- Check firewall rules in Hetzner Cloud Console
- Allow inbound 80, 443

**AWS Security Groups**:
- Inbound rules: 80 (HTTP), 443 (HTTPS)

**DigitalOcean Cloud Firewalls**:
- Inbound rules: HTTP, HTTPS

---

## Update/Upgrade Issues

### Error: "Update failed - containers won't start"

**Rollback**:
```bash
cd /opt/n8n

# Stop services
docker compose down

# Edit docker-compose.yml
# Change image: n8nio/n8n:latest
# To: image: n8nio/n8n:PREVIOUS_VERSION

# Restart
docker compose up -d
```

### Error: "Database migration failed"

**Symptoms**:
```
n8n | ERROR: Migration failed
n8n | Database version mismatch
```

**Solution**:
```bash
# Restore database from backup
cd /opt/n8n

# Stop services
docker compose stop n8n n8n-worker

# Restore most recent backup
gunzip -c backups/postgres/n8n_YYYY-MM-DD_HH-MM-SS.sql.gz | \
    docker exec -i n8n-postgres psql -U n8n -d n8n

# Restart
docker compose start n8n n8n-worker

# If issue persists, use previous n8n version
```

---

## Recovery Procedures

### Complete System Reset

If everything is broken:

```bash
cd /opt/n8n

# 1. Backup current state
./scripts/backup-all.sh

# 2. Stop and remove everything
docker compose down -v

# 3. Remove installation
cd /
sudo rm -rf /opt/n8n

# 4. Re-run deployment script
sudo ./deploy-n8n.sh

# 5. Restore data from backup (if needed)
```

### Restore from Backup

See [README_AUTOMATION.md](./README_AUTOMATION.md#restore-from-backup) for detailed restore procedures.

### Recover Lost Encryption Key

**Problem**: You lost the N8N_ENCRYPTION_KEY.

**Bad News**: Cannot decrypt stored credentials without it.

**Options**:
1. **Find it**: Check `/opt/n8n/.env` on server
2. **Backup**: Check any backups you made
3. **Last resort**: Start fresh (lose encrypted credentials)

```bash
# Generate new encryption key
openssl rand -hex 16

# Update .env
sed -i 's/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=YOUR_NEW_KEY/' /opt/n8n/.env

# Restart n8n
docker compose -f /opt/n8n/docker-compose.yml restart n8n n8n-worker

# WARNING: You'll need to re-enter all credentials in workflows
```

---

## Getting More Help

### Collect Diagnostic Information

```bash
#!/bin/bash
# diagnostic.sh - Collect system info for troubleshooting

echo "=== System Information ==="
lsb_release -a
uname -a
free -h
df -h /

echo ""
echo "=== Docker Information ==="
docker --version
docker compose version
docker ps -a

echo ""
echo "=== Container Logs ==="
docker compose -f /opt/n8n/docker-compose.yml logs --tail=50

echo ""
echo "=== UFW Status ==="
sudo ufw status verbose

echo ""
echo "=== DNS Resolution ==="
DOMAIN=$(grep DOMAIN /opt/n8n/.env | cut -d= -f2)
dig +short $DOMAIN

echo ""
echo "=== Recent Errors ==="
grep ERROR /var/log/n8n-deploy.log | tail -20
```

### Log Locations

- **Deployment**: `/var/log/n8n-deploy.log`
- **Errors**: `/var/log/n8n-deploy-error.log`
- **Backups**: `/var/log/n8n-backup.log`
- **Container logs**: `docker compose logs`
- **Traefik access**: `/opt/n8n/traefik/logs/access.log`

### Useful Debug Commands

```bash
# Check all container health
docker compose -f /opt/n8n/docker-compose.yml ps

# View resource usage
docker stats

# Check network
docker network ls
docker network inspect n8n-network

# Check volumes
docker volume ls
docker volume inspect n8n_postgres_data

# Test connectivity
curl -I https://YOUR_DOMAIN
curl -I http://YOUR_DOMAIN

# Check SSL certificate
echo | openssl s_client -connect YOUR_DOMAIN:443 | openssl x509 -noout -text

# Monitor logs live
docker compose -f /opt/n8n/docker-compose.yml logs -f

# Check system resources
htop
iostat
```

---

## Common Error Messages

| Error Message | Likely Cause | Solution |
|---------------|--------------|----------|
| `permission denied` | Not running with sudo | Use `sudo` |
| `port already in use` | Service on port 80/443 | Stop conflicting service |
| `no such image` | Image not pulled | Run `docker compose pull` |
| `network not found` | Network deleted | `docker network create n8n-network` |
| `volume not found` | Volume deleted | Data lost, need restore |
| `unhealthy` | Service not ready | Check logs, wait longer |
| `connection refused` | Service not started | Check if container running |
| `certificate expired` | Let's Encrypt renewal failed | Delete acme.json, restart Traefik |
| `ECONNREFUSED` | Can't reach service | Check network, firewall |
| `ENOTFOUND` | DNS issue | Check domain configuration |

---

## Prevention Best Practices

1. **Regular Backups**: Verify `/var/log/n8n-backup.log`
2. **Monitor Logs**: Check for errors weekly
3. **Update Regularly**: `sudo ./deploy-n8n.sh --update`
4. **Test Restores**: Verify backups can be restored
5. **Document Changes**: Keep notes of custom configurations
6. **Monitor Resources**: Use `htop`, `docker stats`
7. **Keep Encryption Key**: Store securely off-server
8. **SSL Monitoring**: Check expiry dates

---

## Still Stuck?

1. Review this guide thoroughly
2. Check `/var/log/n8n-deploy.log`
3. Search n8n documentation
4. Ask in n8n community forum
5. Create GitHub issue with:
   - OS version
   - RAM/Disk info
   - Full error log
   - Steps to reproduce
