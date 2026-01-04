# n8n Production VPS Deployment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-20.10+-blue.svg)](https://www.docker.com/)
[![n8n](https://img.shields.io/badge/n8n-latest-orange.svg)](https://n8n.io/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue.svg)](https://www.postgresql.org/)
[![Traefik](https://img.shields.io/badge/Traefik-2.11-blue.svg)](https://traefik.io/)
[![Automated](https://img.shields.io/badge/Deployment-Automated-green.svg)](./automation/)

Complete production-ready deployment of n8n workflow automation on VPS with Docker, PostgreSQL 16, Redis queue mode, and Traefik reverse proxy with automatic SSL certificates.

---

## 🚀 Quick Start

### Automated Deployment (Recommended)

Deploy n8n in **5 steps** (~10 minutes):

```bash
# 1. Download automation script (use sudo in case you get "permission denied")
wget https://raw.githubusercontent.com/buildz-ops/n8n-vps-deployment/main/automation/deploy-n8n.sh

# 2. Make executable
sudo chmod +x deploy-n8n.sh

# 3. Run deployment
sudo ./deploy-n8n.sh

# 4. Answer 3 questions (domain, email, timezone)
# 5. Access your n8n instance at https://your-domain.com
```

**🎯 The script handles everything**: system updates, Docker installation, firewall setup, SSL certificates, database configuration, and more.

👉 **[View Full Automation Guide](./automation/README.md)**

---

### Manual Deployment

For advanced users who want full control, follow the detailed manual installation below.

---

## 📋 Table of Contents

- [Features](#-features)
- [Architecture](#️-architecture)
- [Deployment Methods](#-deployment-methods)
  - [Automated Deployment](#option-1-automated-deployment--recommended)
  - [Manual Deployment](#option-2-manual-deployment-️)
- [System Requirements](#-system-requirements)
- [Manual Installation Guide](#-manual-installation-guide)
- [Post-Installation](#-post-installation)
- [Backup & Recovery](#-backup--recovery)
- [Maintenance](#-maintenance)
- [Troubleshooting](#-troubleshooting)
- [Security](#-security)
- [Performance Tuning](#-performance-tuning)
- [Contributing](#-contributing)
- [License](#-license)

---

## ✨ Features

### Core Capabilities
- ✅ **Production-Ready**: Enterprise-grade configuration out of the box
- ✅ **Queue Mode**: Scalable workflow execution with dedicated worker
- ✅ **High Performance**: Optimized PostgreSQL and Redis configuration
- ✅ **Auto SSL**: Let's Encrypt certificates via Traefik
- ✅ **Secure**: Multi-layer security (UFW, SSH hardening, Fail2ban)
- ✅ **Monitored**: Health checks and logging built-in
- ✅ **Backed Up**: Automated backup scripts included

### Tech Stack
- **n8n**: Latest version with queue mode
- **PostgreSQL 16**: Primary database with optimized settings
- **Redis 7**: Queue broker for distributed execution
- **Traefik 2.11**: Reverse proxy with automatic SSL
- **Docker Compose**: Container orchestration
- **Ubuntu/Debian**: Supported operating systems

---

## 🏗️ Architecture

```
Internet
    ↓
[Traefik] ←─── SSL/TLS (Let's Encrypt)
    ↓
[n8n Main] ←─── Editor + Webhooks
    ↓
[Redis Queue] ←─── Job distribution
    ↓
[n8n Worker] ←─── Execute workflows
    ↓
[PostgreSQL] ←─── Data persistence
```

**Resource Allocation** (12GB RAM VPS):
- PostgreSQL: 4GB
- Redis: 1GB  
- n8n Main: 2GB
- n8n Worker: 2GB
- Traefik: 256MB
- System: ~2.75GB

---

## 🎯 Deployment Methods

### Option 1: Automated Deployment ⚡ (Recommended)

**Best for**: Most users, quick production deployment, minimal DevOps experience

**Time**: ~10 minutes  
**Manual Steps**: 5

**Features**:
- ✅ One-command deployment
- ✅ Interactive setup wizard
- ✅ Automatic secret generation
- ✅ System preparation & Docker installation
- ✅ Firewall & security hardening
- ✅ DNS verification
- ✅ SSL certificate automation
- ✅ Health checks & verification
- ✅ Backup configuration
- ✅ Comprehensive error handling
- ✅ Idempotent (safe to re-run)

**Supported Systems**:
- Ubuntu 22.04 LTS, 24.04 LTS, 25.10
- Debian 11, 12
- 8GB RAM minimum (12GB recommended)

**Usage**:
```bash
# Interactive mode
sudo ./deploy-n8n.sh

# Non-interactive mode
sudo ./deploy-n8n.sh \
  --domain n8n.example.com \
  --email admin@example.com \
  --timezone Europe/Madrid \
  --yes

# Update existing installation
sudo ./deploy-n8n.sh --update

# Health check
./deploy-n8n.sh --check-health
```

📖 **[Complete Automation Documentation](./automation/README.md)**  
🔧 **[Automation Troubleshooting Guide](./automation/TROUBLESHOOTING.md)**  
✅ **[Verification Report](./automation/VERIFICATION_REPORT.md)** (147/147 checks passed)

---

### Option 2: Manual Deployment 🛠️

**Best for**: Advanced users, custom configurations, learning experience

**Time**: ~30-60 minutes  
**Manual Steps**: 60+

**Features**:
- ✅ Full control over every step
- ✅ Understand each component
- ✅ Customize as needed
- ✅ Educational experience

**Continue to**: [Manual Installation Guide](#manual-installation-guide) below

---

## 💻 System Requirements

### Minimum Requirements

| Component | Requirement |
|-----------|-------------|
| **OS** | Ubuntu 22.04+ or Debian 11+ |
| **RAM** | 8GB minimum, **12GB recommended** |
| **Storage** | 20GB minimum, 50GB+ recommended |
| **CPU** | 2 cores minimum, 4+ recommended |
| **Network** | Static IP, ports 80/443 accessible |

### Prerequisites

- Root or sudo access
- Domain name with DNS configured
- Email address for SSL certificates
- SSH access to server

---

## 📚 Manual Installation Guide

### 1. System Preparation

Update system and install essential packages:

```bash
# Update package lists
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y \
    curl wget git vim htop net-tools unzip \
    software-properties-common ca-certificates \
    gnupg lsb-release apache2-utils

# Set timezone
sudo timedatectl set-timezone Europe/Madrid

# Configure automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 2. Docker Installation

```bash
# Remove old Docker packages
sudo apt remove docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify installation
docker --version
docker compose version
```

### 3. Configure Docker Daemon

```bash
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF

sudo systemctl restart docker
sudo systemctl enable docker
```

### 4. DNS Configuration

Create an A record in your DNS provider:

| Setting | Value |
|---------|-------|
| **Type** | A |
| **Name** | n8n (or your subdomain) |
| **Value** | YOUR_VPS_IP |
| **TTL** | Auto or 300 |

**Important**: Set to DNS only (no proxy) initially for Let's Encrypt validation.

Verify DNS propagation:
```bash
dig +short n8n.example.com
# Should return: YOUR_VPS_IP
```

### 5. Create Directory Structure

```bash
# Create main directory
sudo mkdir -p /opt/n8n
sudo chown -R $USER:$USER /opt/n8n
cd /opt/n8n

# Create subdirectories
mkdir -p \
    traefik/config \
    traefik/logs \
    postgres \
    redis \
    n8n-data \
    backups/postgres \
    backups/volumes \
    scripts

# Create acme.json with correct permissions
touch traefik/acme.json
chmod 600 traefik/acme.json
```

### 6. Generate Secrets

```bash
# Generate PostgreSQL password (32 characters)
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
echo "PostgreSQL Password: $POSTGRES_PASSWORD"

# Generate n8n encryption key (32 characters hex)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
echo "n8n Encryption Key: $N8N_ENCRYPTION_KEY"

# ⚠️ SAVE THESE CREDENTIALS SECURELY!
```

### 7. Create Environment File

```bash
cat > /opt/n8n/.env <<EOF
# PostgreSQL Configuration
POSTGRES_USER=n8n
POSTGRES_PASSWORD=YOUR_POSTGRES_PASSWORD_HERE
POSTGRES_DB=n8n

# n8n Encryption Key
N8N_ENCRYPTION_KEY=YOUR_ENCRYPTION_KEY_HERE

# Domain Configuration
DOMAIN=n8n.example.com

# Let's Encrypt Email
LETSENCRYPT_EMAIL=your.email@example.com

# Timezone
TZ=Europe/Madrid
EOF

# Set secure permissions
chmod 600 /opt/n8n/.env
```

**Replace**:
- `YOUR_POSTGRES_PASSWORD_HERE` with generated password
- `YOUR_ENCRYPTION_KEY_HERE` with generated key
- `n8n.example.com` with your domain
- `your.email@example.com` with your email

### 8. Download Configuration Files

Download the repository files:

```bash
cd /opt/n8n

# Download docker-compose.yml
wget https://raw.githubusercontent.com/buildz-ops/n8n-vps-deployment/main/docker-compose.yml

# Download Traefik configuration
wget -P traefik/ https://raw.githubusercontent.com/buildz-ops/n8n-vps-deployment/main/traefik/traefik.yml
wget -P traefik/config/ https://raw.githubusercontent.com/buildz-ops/n8n-vps-deployment/main/traefik/config/dynamic.yml

# Download backup scripts
wget -P scripts/ https://raw.githubusercontent.com/buildz-ops/n8n-vps-deployment/main/scripts/backup-postgres.sh
wget -P scripts/ https://raw.githubusercontent.com/buildz-ops/n8n-vps-deployment/main/scripts/backup-all.sh
wget -P scripts/ https://raw.githubusercontent.com/buildz-ops/n8n-vps-deployment/main/scripts/healthcheck.sh

# Make scripts executable
chmod +x scripts/*.sh
```

**Update Traefik email**:
```bash
# Edit traefik.yml
nano traefik/traefik.yml
# Change: email: your.email@example.com
```

### 9. Firewall Configuration

```bash
# Install UFW
sudo apt install -y ufw

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow required ports
sudo ufw allow OpenSSH
sudo ufw limit ssh/tcp comment 'Rate limit SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# Apply Docker UFW bypass fix
sudo nano /etc/ufw/after.rules
# Add the Docker UFW fix from repository documentation

# Enable firewall
sudo ufw enable
sudo ufw status verbose
```

### 10. Deploy Containers

```bash
cd /opt/n8n

# Create Docker network
docker network create n8n-network

# Pull images
docker compose pull

# Start services
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

### 11. Verify Deployment

```bash
# Wait for SSL certificate (1-2 minutes)
docker compose logs -f traefik | grep -i acme

# Check all containers are healthy
docker compose ps

# Test HTTPS access
curl -I https://n8n.example.com

# Check SSL certificate
echo | openssl s_client -connect n8n.example.com:443 -servername n8n.example.com 2>/dev/null | openssl x509 -noout -dates
```

### 12. Configure Automated Backups

```bash
# Add to crontab
crontab -e

# Add this line (daily backup at 2 AM):
0 2 * * * /opt/n8n/scripts/backup-all.sh >> /var/log/n8n-backup.log 2>&1

# Test backup
/opt/n8n/scripts/backup-postgres.sh
```

---

## 🎉 Post-Installation

### First-Time Setup

1. **Access n8n**: Navigate to `https://your-domain.com`
2. **Create Admin User**: Fill in the registration form
3. **Start Building**: Create your first workflow!

### Important Files

**Credentials** (saved in `/opt/n8n/.env`):
- PostgreSQL password
- n8n encryption key

⚠️ **Backup these credentials** securely! Loss of encryption key = cannot decrypt stored credentials.

### Useful Commands

```bash
# View logs (all services)
docker compose -f /opt/n8n/docker-compose.yml logs -f

# View logs (specific service)
docker compose -f /opt/n8n/docker-compose.yml logs -f n8n

# Check status
docker compose -f /opt/n8n/docker-compose.yml ps

# Restart services
docker compose -f /opt/n8n/docker-compose.yml restart

# Health check
/opt/n8n/scripts/healthcheck.sh

# Manual backup
/opt/n8n/scripts/backup-all.sh
```

📖 **[View Complete Quick Reference](./QUICK_REFERENCE.md)**

---

## 💾 Backup & Recovery

### Automated Backups

If configured (cron job):
- **Schedule**: Daily at 2 AM
- **Retention**: 7 days
- **Location**: `/opt/n8n/backups/`
- **Includes**: PostgreSQL database, Docker volumes, configuration files

### Manual Backup

```bash
/opt/n8n/scripts/backup-all.sh
```

Creates:
- `backups/postgres/n8n_YYYY-MM-DD_HH-MM-SS.sql.gz`
- `backups/volumes/volumes_YYYY-MM-DD_HH-MM-SS.tar.gz`
- `backups/config_YYYY-MM-DD_HH-MM-SS.tar.gz`

### Restore Database

```bash
# Stop n8n services
cd /opt/n8n
docker compose stop n8n n8n-worker

# Restore database
gunzip -c backups/postgres/n8n_YYYY-MM-DD_HH-MM-SS.sql.gz | \
    docker exec -i n8n-postgres psql -U n8n -d n8n

# Restart services
docker compose start n8n n8n-worker
```

---

## 🔧 Maintenance

### Update to Latest Version

**Automated** (if using automation script):
```bash
sudo ./deploy-n8n.sh --update
```

**Manual**:
```bash
cd /opt/n8n

# Pull latest images
docker compose pull

# Recreate containers
docker compose up -d

# Verify
docker compose ps
```

### Clean Up Unused Resources

```bash
# Remove unused images
docker image prune -a

# Remove unused volumes (careful!)
docker volume prune

# Complete cleanup
docker system prune -a
```

### PostgreSQL Maintenance

```bash
# Vacuum and analyze
docker exec -it n8n-postgres psql -U n8n -d n8n -c "VACUUM ANALYZE;"

# Check database size
docker exec -it n8n-postgres psql -U n8n -d n8n -c "\l+"
```

---

## 🔍 Troubleshooting

### Common Issues

#### SSL Certificate Not Working

**Check Traefik logs**:
```bash
docker compose logs traefik | grep -i acme
```

**Common causes**:
- Port 80 blocked (check UFW and cloud provider firewall)
- DNS not configured or not propagated
- Cloudflare proxy enabled (should be DNS only initially)
- `acme.json` permissions incorrect (must be 600)

**Solution**:
```bash
# Check acme.json permissions
ls -la traefik/acme.json
chmod 600 traefik/acme.json

# Reset certificates
rm traefik/acme.json
touch traefik/acme.json
chmod 600 traefik/acme.json
docker compose restart traefik
```

#### n8n Won't Start

**Check logs**:
```bash
docker compose logs n8n
```

**Common causes**:
- Database not ready
- Wrong encryption key
- Port conflict

**Solution**:
```bash
# Restart in order
docker compose restart postgres
sleep 10
docker compose restart redis
sleep 5
docker compose restart n8n n8n-worker
```

#### High Memory Usage

**Check stats**:
```bash
docker stats
```

**Solution**: Adjust resource limits in `docker-compose.yml` based on available RAM.

### Getting Help

- 📖 **Automated Deployment**: See [automation/TROUBLESHOOTING.md](./automation/TROUBLESHOOTING.md)
- 📖 **Quick Reference**: See [QUICK_REFERENCE.md](./QUICK_REFERENCE.md)
- 🐛 **Report Issues**: [GitHub Issues](https://github.com/buildz-ops/n8n-vps-deployment/issues)
- 💬 **n8n Community**: [n8n Community Forum](https://community.n8n.io/)

---

## 🔒 Security

### What's Configured

✅ UFW firewall (ports 22, 80, 443 only)  
✅ Docker UFW bypass fix  
✅ SSL/TLS with Let's Encrypt  
✅ Security headers (HSTS, XSS, etc.)  
✅ Fail2ban for SSH protection  
✅ Secure file permissions (.env = 600)  
✅ Auto-generated strong credentials  

### Security Checklist

- [ ] Root SSH login disabled
- [ ] Password authentication disabled
- [ ] SSH keys configured
- [ ] UFW firewall enabled
- [ ] Fail2ban installed and running
- [ ] Strong PostgreSQL password
- [ ] n8n encryption key backed up
- [ ] `.env` file permissions = 600
- [ ] SSL certificate active
- [ ] Automated backups configured
- [ ] Docker log rotation enabled

### Recommended Actions

- Keep SSH keys secure
- Enable 2FA for n8n admin account
- Regularly update containers
- Monitor backup logs
- Review access logs periodically
- Keep encryption key backed up off-server

---

## ⚡ Performance Tuning

### Resource Allocation

The configuration is optimized for a 12GB RAM VPS. Adjust for your system:

**8GB RAM** (Minimum):
```yaml
postgres: memory: 2G
redis: memory: 512M
n8n: memory: 1536M
n8n-worker: memory: 1536M
```

**16GB+ RAM** (High Performance):
```yaml
postgres: memory: 6G
redis: memory: 2G
n8n: memory: 3G
n8n-worker: memory: 3G
```

### PostgreSQL Tuning

Adjust in `docker-compose.yml`:
```yaml
command:
  - "shared_buffers=1024MB"        # 25% of RAM
  - "effective_cache_size=3072MB"  # 50-75% of RAM
  - "work_mem=4MB"                 # Adjust based on queries
```

### Add More Workers

For high-volume workflows:
```yaml
# In docker-compose.yml, duplicate n8n-worker service:
n8n-worker-2:
  image: n8nio/n8n:latest
  container_name: n8n-worker-2
  # ... same config as n8n-worker
```

---

## 🤝 Contributing

Contributions welcome! Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

### Ways to Contribute

- 🐛 Report bugs
- 💡 Suggest features
- 📝 Improve documentation
- 🔧 Submit pull requests
- ⭐ Star the repository

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

---

## 🙏 Acknowledgments

- [n8n](https://n8n.io/) - Workflow automation platform
- [Traefik](https://traefik.io/) - Reverse proxy and SSL automation
- [PostgreSQL](https://www.postgresql.org/) - Database
- [Redis](https://redis.io/) - Queue broker
- [Docker](https://www.docker.com/) - Containerization

---

## 📞 Support

- 📖 **Documentation**: This README and linked guides
- 🐛 **Issues**: [GitHub Issues](https://github.com/buildz-ops/n8n-vps-deployment/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/buildz-ops/n8n-vps-deployment/discussions)
- 🌐 **n8n Community**: [n8n Community Forum](https://community.n8n.io/)

---

**Made with ❤️ for the n8n community**

**Deployment Methods**: [Automated](./automation/) (5 steps) | [Manual](#manual-installation-guide) (full control)
