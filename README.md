# n8n Production VPS Deployment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-20.10+-blue.svg)](https://www.docker.com/)
[![n8n](https://img.shields.io/badge/n8n-latest-orange.svg)](https://n8n.io/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue.svg)](https://www.postgresql.org/)
[![Traefik](https://img.shields.io/badge/Traefik-v2.11-blue.svg)](https://traefik.io/)

Complete production-ready deployment guide for n8n workflow automation platform on Ubuntu VPS with Docker, PostgreSQL 16, Redis queue mode, and Traefik reverse proxy with automatic SSL certificates.

## 📋 Table of Contents

- [Features](#-features)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Detailed Installation](#-detailed-installation)
  - [1. System Preparation](#1-system-preparation)
  - [2. DNS Configuration](#2-dns-configuration)
  - [3. Directory Structure](#3-directory-structure)
  - [4. Configuration Files](#4-configuration-files)
  - [5. Deployment](#5-deployment)
  - [6. Security Hardening](#6-security-hardening)
  - [7. Backup Configuration](#7-backup-configuration)
- [Resource Allocation](#-resource-allocation)
- [Verification](#-verification)
- [Maintenance](#-maintenance)
- [Troubleshooting](#-troubleshooting)
- [Security Checklist](#-security-checklist)
- [Contributing](#-contributing)
- [License](#-license)

## ✨ Features

- **Queue Mode**: Scalable workflow execution with Redis queue and dedicated workers
- **Automatic SSL**: Let's Encrypt certificates via Traefik with automatic renewal
- **High Performance**: Optimized PostgreSQL configuration for 12GB RAM environments
- **Enterprise Security**: UFW firewall, SSH hardening, Fail2ban integration
- **Automated Backups**: Daily PostgreSQL dumps and volume backups with retention policies
- **Health Monitoring**: Built-in health checks and monitoring scripts
- **Production-Ready**: Docker-based deployment with proper resource limits
- **Zero Downtime**: Live restore and restart policies

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
            ┌─────────────────┐
            │  Traefik Proxy  │ (Port 80/443)
            │  + SSL/TLS      │
            └────────┬────────┘
                     │
                     ▼
         ┌──────────────────────────┐
         │     n8n Main Service     │ (Editor/Webhooks)
         │   + n8n Worker           │ (Queue Execution)
         └──────────┬───────────────┘
                    │
          ┌─────────┴──────────┐
          ▼                    ▼
   ┌──────────────┐    ┌──────────────┐
   │ PostgreSQL 16│    │  Redis 7     │
   │  (Database)  │    │  (Queue)     │
   └──────────────┘    └──────────────┘
```

## 📦 Prerequisites

### System Requirements

- **OS**: Ubuntu 22.04 LTS or 24.04 LTS (or Ubuntu 25.10 for latest features)
- **RAM**: Minimum 8GB, **recommended 12GB**
- **Storage**: Minimum 50GB SSD
- **Network**: Static IP address or reliable dynamic DNS
- **Domain**: A domain name with DNS management access (Cloudflare recommended)

### Required Access

- SSH access with sudo privileges
- Non-root user with Docker permissions
- Domain DNS management (A record creation)

### Software Prerequisites

The installation script will handle these, but you should have:
- Docker Engine 20.10+
- Docker Compose v2.0+
- curl, wget, git

## 🚀 Quick Start

For experienced users, here's the condensed setup:

```bash
# 1. Clone repository
git clone https://github.com/buildz-ops/n8n-vps-deployment.git
cd n8n-vps-deployment

# 2. Configure environment
cp .env.example .env
nano .env  # Edit with your values

# 3. Set up directory structure
sudo mkdir -p /opt/n8n
sudo chown -R $USER:$USER /opt/n8n
cp -r * /opt/n8n/
cd /opt/n8n

# 4. Create required files
touch traefik/acme.json
chmod 600 traefik/acme.json

# 5. Deploy
docker compose up -d

# 6. Verify
docker compose ps
curl -I https://n8n.YOUR_DOMAIN.com/healthz
```

**⚠️ For production deployments, follow the [Detailed Installation](#-detailed-installation) guide below.**

## 📚 Detailed Installation

### 1. System Preparation

#### 1.1 Update System

```bash
sudo apt update && sudo apt upgrade -y
```

#### 1.2 Install Essential Packages

```bash
sudo apt install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    net-tools \
    unzip \
    software-properties-common \
    ca-certificates \
    gnupg \
    lsb-release \
    apache2-utils
```

#### 1.3 Configure Timezone

```bash
# Set your timezone (example: Europe/Madrid, America/New_York, Asia/Tokyo)
sudo timedatectl set-timezone YOUR_TIMEZONE

# Verify
timedatectl
```

#### 1.4 Install Docker

Using the official Docker installation script:

```bash
# Download and run Docker installation script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group
sudo usermod -aG docker $USER

# Apply group changes
newgrp docker

# Verify installation
docker --version
docker compose version
```

#### 1.5 Configure Docker Daemon

Create `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
```

Restart Docker:

```bash
sudo systemctl restart docker
sudo systemctl enable docker
```

### 2. DNS Configuration

#### 2.1 Create DNS A Record

In your DNS provider (Cloudflare recommended):

| Setting | Value |
|---------|-------|
| **Type** | A |
| **Name** | n8n |
| **IPv4 address** | YOUR_VPS_IP |
| **Proxy status** | DNS only (gray cloud) |
| **TTL** | Auto |

**Important**: Keep proxy disabled (gray cloud) initially for Let's Encrypt HTTP challenge.

#### 2.2 Verify DNS Propagation

```bash
# Replace with your actual domain
dig n8n.YOUR_DOMAIN.com +short
# Should return: YOUR_VPS_IP

# Or use nslookup
nslookup n8n.YOUR_DOMAIN.com
```

Wait until DNS propagates (typically 5-15 minutes).

### 3. Directory Structure

#### 3.1 Create Base Directory

```bash
# Create main application directory
sudo mkdir -p /opt/n8n
sudo chown -R $USER:$USER /opt/n8n
cd /opt/n8n
```

#### 3.2 Create Subdirectories

```bash
mkdir -p \
    traefik/config \
    traefik/logs \
    postgres \
    redis \
    n8n-data \
    backups/postgres \
    backups/volumes \
    scripts
```

#### 3.3 Create Required Files

```bash
# Create acme.json for SSL certificates (CRITICAL: Must be 600 permissions)
touch /opt/n8n/traefik/acme.json
chmod 600 /opt/n8n/traefik/acme.json
```

Final structure:

```
/opt/n8n/
├── docker-compose.yml
├── .env
├── traefik/
│   ├── traefik.yml
│   ├── config/
│   │   └── dynamic.yml
│   ├── logs/
│   └── acme.json
├── postgres/
├── redis/
├── n8n-data/
├── backups/
│   ├── postgres/
│   └── volumes/
└── scripts/
    ├── backup-postgres.sh
    ├── backup-all.sh
    └── healthcheck.sh
```

### 4. Configuration Files

#### 4.1 Clone Repository

```bash
git clone https://github.com/YOUR_USERNAME/n8n-vps-deployment.git /tmp/n8n-deploy
cp -r /tmp/n8n-deploy/* /opt/n8n/
cd /opt/n8n
```

#### 4.2 Configure Environment Variables

Copy the example environment file:

```bash
cp .env.example .env
```

Generate secure secrets:

```bash
# Generate PostgreSQL password (32 characters)
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"

# Generate n8n encryption key (32 characters hex)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
echo "N8N_ENCRYPTION_KEY: $N8N_ENCRYPTION_KEY"
```

Edit `.env` file:

```bash
nano .env
```

Replace all placeholder values with your actual configuration:

```bash
# PostgreSQL Configuration
POSTGRES_USER=n8n
POSTGRES_PASSWORD=YOUR_GENERATED_POSTGRES_PASSWORD
POSTGRES_DB=n8n

# n8n Encryption Key (BACKUP THIS SECURELY!)
N8N_ENCRYPTION_KEY=YOUR_GENERATED_ENCRYPTION_KEY

# Domain Configuration
DOMAIN=n8n.YOUR_DOMAIN.com

# Let's Encrypt Email (for SSL certificate notifications)
LETSENCRYPT_EMAIL=your.email@example.com

# Timezone
TZ=YOUR_TIMEZONE
```

**⚠️ CRITICAL**: Backup your `.env` file, especially `N8N_ENCRYPTION_KEY`. If lost, you cannot recover encrypted credentials in n8n.

Secure the environment file:

```bash
chmod 600 .env
```

#### 4.3 Update Traefik Configuration

Edit `traefik/traefik.yml` and replace `your_email@example.com` with your actual email:

```bash
nano traefik/traefik.yml
```

**Critical Configuration Note**: Ensure `N8N_HOST` in `docker-compose.yml` **exactly matches** the Traefik `Host()` rule. Mismatch causes SSL certificate failures.

### 5. Deployment

#### 5.1 Create Docker Network

```bash
docker network create n8n-network
```

#### 5.2 Pull Images

```bash
docker compose pull
```

This downloads:
- Traefik v2.11
- PostgreSQL 16 Alpine
- Redis 7 Alpine
- n8n latest

#### 5.3 Start Services

```bash
docker compose up -d
```

#### 5.4 Monitor Startup

```bash
# Watch all logs
docker compose logs -f

# Watch specific service
docker compose logs -f traefik
docker compose logs -f n8n
```

Press `Ctrl+C` to stop following logs (containers keep running).

#### 5.5 Verify Deployment

```bash
# Check container status (all should show "healthy")
docker compose ps

# Expected output:
# NAME          STATUS
# n8n           Up (healthy)
# n8n-postgres  Up (healthy)
# n8n-redis     Up (healthy)
# n8n-worker    Up
# traefik       Up (healthy)
```

Wait 1-2 minutes for SSL certificate acquisition. Monitor with:

```bash
docker compose logs traefik | grep -i "certificate\|acme"
```

### 6. Security Hardening

#### 6.1 Configure UFW Firewall

```bash
# Install UFW
sudo apt install -y ufw

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow required ports
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp    # HTTP (for Let's Encrypt)
sudo ufw allow 443/tcp   # HTTPS

# Enable rate limiting for SSH
sudo ufw limit ssh/tcp

# Enable firewall
sudo ufw enable

# Verify
sudo ufw status verbose
```

#### 6.2 Fix Docker UFW Bypass

Docker modifies iptables directly, bypassing UFW. Fix this:

```bash
sudo nano /etc/ufw/after.rules
```

Add at the **END** of the file:

```
# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN

-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12

-A DOCKER-USER -j RETURN

-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP

COMMIT
# END UFW AND DOCKER
```

Reload UFW:

```bash
sudo ufw reload
```

#### 6.3 SSH Hardening

Backup current SSH config:

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
```

Edit SSH configuration:

```bash
sudo nano /etc/ssh/sshd_config
```

Key settings to change/verify:

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
```

Test configuration before applying:

```bash
sudo sshd -t
```

If no errors, restart SSH:

```bash
sudo systemctl restart sshd
```

**⚠️ IMPORTANT**: Test new SSH connection in a separate terminal before closing your current session!

#### 6.4 Install Fail2ban

```bash
sudo apt install -y fail2ban

# Create local configuration
sudo nano /etc/fail2ban/jail.local
```

Add:

```ini
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 24h
findtime = 1h
```

Enable and start:

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Verify
sudo fail2ban-client status sshd
```

### 7. Backup Configuration

#### 7.1 Make Scripts Executable

```bash
chmod +x /opt/n8n/scripts/*.sh
```

#### 7.2 Test Backup Scripts

```bash
# Test PostgreSQL backup
/opt/n8n/scripts/backup-postgres.sh

# Test complete backup
/opt/n8n/scripts/backup-all.sh

# Verify backups were created
ls -lh /opt/n8n/backups/postgres/
ls -lh /opt/n8n/backups/
```

#### 7.3 Configure Automated Backups

```bash
crontab -e
```

Add (daily backup at 2 AM):

```cron
0 2 * * * /opt/n8n/scripts/backup-all.sh >> /var/log/n8n-backup.log 2>&1
```

#### 7.4 Backup Restoration

To restore from backup:

```bash
# Stop n8n services
cd /opt/n8n
docker compose stop n8n n8n-worker

# Restore database (replace with your backup file)
gunzip -c /opt/n8n/backups/postgres/n8n_YYYY-MM-DD_HH-MM-SS.sql.gz | \
    docker exec -i n8n-postgres psql -U n8n -d n8n

# Restart services
docker compose start n8n n8n-worker
```

## 💾 Resource Allocation

Optimized configuration for **12GB RAM VPS**:

| Service | Memory Limit | CPU Priority | Purpose |
|---------|--------------|--------------|---------|
| PostgreSQL | 4GB | High | Primary database (shared_buffers=1GB) |
| Redis | 1GB | Medium | Queue broker (maxmemory=512MB) |
| n8n (main) | 2GB | High | Editor UI and webhook handling |
| n8n-worker | 2GB | High | Workflow execution worker |
| Traefik | 256MB | Medium | Reverse proxy and SSL termination |
| **OS/System** | ~2.75GB | - | Operating system and file caching |

### Scaling Guidelines

**8GB RAM Configuration**:
- PostgreSQL: 2GB (shared_buffers=512MB)
- Redis: 512MB (maxmemory=256MB)
- n8n: 1.5GB
- n8n-worker: 1.5GB
- Traefik: 256MB
- OS: ~2.25GB

**16GB+ RAM Configuration**:
- PostgreSQL: 6GB (shared_buffers=2GB)
- Redis: 2GB (maxmemory=1GB)
- n8n: 3GB
- n8n-worker: 3GB
- Traefik: 512MB
- OS: ~1.5GB+

## ✅ Verification

### Access n8n

Open your browser:

```
https://n8n.YOUR_DOMAIN.com
```

You should see the n8n setup wizard. Create your first admin user.

### Verify SSL Certificate

```bash
curl -I https://n8n.YOUR_DOMAIN.com

# Check certificate details
echo | openssl s_client -connect n8n.YOUR_DOMAIN.com:443 -servername n8n.YOUR_DOMAIN.com 2>/dev/null | openssl x509 -noout -dates -issuer
```

### Verify Health Endpoint

```bash
curl https://n8n.YOUR_DOMAIN.com/healthz
# Expected: {"status":"ok"}
```

### Verify Queue Mode

```bash
docker compose logs n8n | grep -i queue
docker compose logs n8n-worker | grep -i ready
```

### Test Webhook

After creating a workflow with webhook trigger:

```bash
curl -X POST https://n8n.YOUR_DOMAIN.com/webhook/YOUR_WEBHOOK_PATH \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

## 🔧 Maintenance

### Update n8n

```bash
cd /opt/n8n

# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Verify
docker compose ps
docker compose logs --tail=50 n8n
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service with timestamps
docker compose logs -f --timestamps n8n

# Last 100 lines
docker compose logs --tail=100 n8n
```

### Monitor Resources

```bash
# Real-time container stats
docker stats

# Specific containers
docker stats n8n n8n-worker n8n-postgres n8n-redis traefik
```

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
# Remove unused resources
docker system prune -a

# Remove only dangling images
docker image prune

# Remove unused volumes (careful!)
docker volume prune
```

### Health Check

Run the built-in health check script:

```bash
/opt/n8n/scripts/healthcheck.sh
```

## 🐛 Troubleshooting

### SSL Certificate Issues

**Problem**: Self-signed certificate or certificate errors

**Solutions**:

```bash
# Check Traefik logs for ACME errors
docker compose logs traefik | grep -i "acme\|certificate\|error"

# Verify acme.json permissions (must be 600)
ls -la /opt/n8n/traefik/acme.json
chmod 600 /opt/n8n/traefik/acme.json

# Verify DNS resolves correctly
dig n8n.YOUR_DOMAIN.com +short

# Check port 80 is accessible (needed for HTTP challenge)
curl -I http://n8n.YOUR_DOMAIN.com

# Reset certificates
rm /opt/n8n/traefik/acme.json
touch /opt/n8n/traefik/acme.json
chmod 600 /opt/n8n/traefik/acme.json
docker compose restart traefik
```

**Critical**: Ensure `N8N_HOST` environment variable matches the domain in Traefik's `Host()` rule. Mismatch prevents SSL certificate acquisition.

### n8n Won't Start

**Problem**: Container keeps restarting

**Solutions**:

```bash
# Check logs
docker compose logs n8n

# Verify database is ready
docker compose logs postgres
docker exec -it n8n-postgres pg_isready -U n8n -d n8n

# Verify encryption key is correct
grep N8N_ENCRYPTION_KEY .env

# Restart in order
docker compose restart postgres
sleep 10
docker compose restart redis
sleep 5
docker compose restart n8n n8n-worker
```

### Worker Not Processing Jobs

**Problem**: Workflows not executing in queue mode

**Solutions**:

```bash
# Check worker logs
docker compose logs n8n-worker

# Verify Redis connectivity
docker exec -it n8n-redis redis-cli ping

# Check queue keys
docker exec -it n8n-redis redis-cli keys "*bull*"

# Verify encryption keys match between n8n and worker
docker compose exec n8n printenv | grep N8N_ENCRYPTION_KEY
docker compose exec n8n-worker printenv | grep N8N_ENCRYPTION_KEY
```

### High Memory Usage

**Problem**: Containers using too much RAM

**Solutions**:

```bash
# Check container memory
docker stats --no-stream

# Reduce PostgreSQL shared_buffers in docker-compose.yml
# Reduce Redis maxmemory in docker-compose.yml

# Enable execution data pruning in n8n
# (via n8n UI: Settings → Workflow → Execution Data)

# Check for OOM kills
dmesg | grep -i oom
```

### Webhooks Not Working

**Problem**: Webhook URLs return errors

**Solutions**:

```bash
# Verify webhook URL configuration
docker compose exec n8n printenv | grep WEBHOOK

# Test webhook directly
curl -X POST https://n8n.YOUR_DOMAIN.com/webhook/test \
  -H "Content-Type: application/json" \
  -d '{"test": true}'

# Check Traefik routing
docker compose logs traefik | grep webhook

# Verify SSL is working
curl -I https://n8n.YOUR_DOMAIN.com
```

### Database Connection Errors

**Problem**: n8n cannot connect to PostgreSQL

**Solutions**:

```bash
# Check PostgreSQL logs
docker compose logs postgres

# Verify database is running
docker compose ps postgres

# Test connection
docker exec -it n8n-postgres psql -U n8n -d n8n -c "SELECT 1;"

# Check network connectivity
docker exec -it n8n ping postgres
```

### Port 80/443 Blocked

**Problem**: Ports not accessible from internet

**Solutions**:

```bash
# Verify UFW allows ports
sudo ufw status verbose

# Check if services are listening
sudo ss -tulpn | grep -E ':80|:443'

# Test external access
curl -I http://YOUR_VPS_IP

# Check cloud provider firewall (OVH Edge, AWS Security Groups, etc.)
# Ensure ports 80 and 443 are allowed in provider's firewall
```

### Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| `ECONNREFUSED` | Database not ready | Wait for PostgreSQL health check, then restart n8n |
| `Invalid encryption key` | Wrong `N8N_ENCRYPTION_KEY` | Restore correct key from backup |
| `Certificate error` | `N8N_HOST` mismatch | Ensure `N8N_HOST` matches Traefik `Host()` rule exactly |
| `Queue not processing` | Redis connection issue | Check Redis connectivity and encryption key |
| `Port already in use` | Port conflict | Check `docker compose ps` and stop conflicting services |

## 🔒 Security Checklist

Before production deployment, verify:

- [ ] Root SSH login disabled
- [ ] Password authentication disabled  
- [ ] SSH key authentication configured
- [ ] UFW firewall enabled (ports 22, 80, 443 only)
- [ ] Docker UFW bypass fix applied
- [ ] Fail2ban installed and active
- [ ] Strong PostgreSQL password generated
- [ ] n8n encryption key backed up securely
- [ ] `.env` file has 600 permissions
- [ ] SSL certificate active and valid (HTTPS working)
- [ ] Automated backups configured and tested
- [ ] Docker log rotation enabled
- [ ] Cloud provider firewall configured (if applicable)
- [ ] DNS records correct (A record pointing to VPS)
- [ ] First n8n admin user created with strong password
- [ ] Test webhook functionality
- [ ] Monitor logs for errors after deployment

## 📖 Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [PostgreSQL Tuning Guide](https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This deployment guide is provided as-is. Always review and understand configurations before deploying to production. Ensure you have proper backups and disaster recovery procedures in place.

## 🙏 Acknowledgments

- [n8n.io](https://n8n.io/) - Amazing workflow automation platform
- [Traefik](https://traefik.io/) - Modern reverse proxy
- [Docker](https://www.docker.com/) - Containerization platform
- Community contributors and testers

---

**Questions or Issues?** Open an issue on [GitHub](https://github.com/YOUR_USERNAME/n8n-vps-deployment/issues).
