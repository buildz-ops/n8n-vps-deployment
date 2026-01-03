# n8n Automated Deployment Script

Comprehensive automation script for deploying production-ready n8n on VPS with minimal manual intervention.

## Quick Start

```bash
# Download the script
wget https://raw.githubusercontent.com/buildz-ops/n8n-vps-deployment/main/automation/deploy-n8n.sh

# Make it executable
chmod +x deploy-n8n.sh

# Run the script
sudo ./deploy-n8n.sh
```

The script will guide you through the deployment with interactive prompts.

---

## Features

### ✅ Automated

- **Zero Manual Configuration**: Auto-generates all config files
- **Intelligent Detection**: Detects OS, existing installations, resources
- **Smart Defaults**: Production-ready settings out of the box
- **Progress Indicators**: Visual feedback for long operations

### ✅ Production-Ready

- **Queue Mode**: n8n with worker for scalable execution
- **PostgreSQL 16**: Optimized database configuration
- **Redis**: Queue broker with persistence
- **Traefik**: Automatic SSL with Let's Encrypt
- **Security**: UFW firewall, SSH hardening, Fail2ban

### ✅ Idempotent

- **Safe to Re-run**: Detects existing installations
- **Update Mode**: Update containers without data loss
- **Backup Integration**: Automated daily backups
- **Rollback Support**: Preserves configurations

---

## System Requirements

### Minimum Requirements

| Component | Requirement |
|-----------|-------------|
| **OS** | Ubuntu 22.04/24.04/25.10 or Debian 11/12 |
| **RAM** | 8GB minimum, 12GB recommended |
| **Disk** | 20GB minimum, 50GB+ recommended |
| **Architecture** | x86_64 or aarch64 |
| **Ports** | 80, 443 (must be available) |

### Prerequisites

- Root or sudo access
- SSH key authentication configured (recommended)
- Domain name with DNS configured (A record pointing to VPS IP)
- Email address for Let's Encrypt notifications

---

## Usage

### Interactive Installation (Recommended)

```bash
sudo ./deploy-n8n.sh
```

The script will:
1. Detect your system and check requirements
2. Ask for domain name and email
3. Generate secure credentials (displays on screen - save them!)
4. Configure system and install Docker
5. Set up firewall and security
6. Verify DNS configuration
7. Deploy all containers
8. Obtain SSL certificate
9. Run verification tests
10. Display final summary with access URL

**Estimated time**: 5-10 minutes (excluding DNS propagation)

### Non-Interactive Installation

```bash
sudo ./deploy-n8n.sh \
  --domain n8n.example.com \
  --email admin@example.com \
  --timezone Europe/Madrid \
  --yes
```

### Installation with Custom Directory

```bash
sudo ./deploy-n8n.sh \
  --domain n8n.example.com \
  --email admin@example.com \
  --install-dir /var/n8n \
  --yes
```

### Skip Security Hardening

```bash
sudo ./deploy-n8n.sh \
  --domain n8n.example.com \
  --email admin@example.com \
  --skip-security \
  --yes
```

### Dry Run (Preview Changes)

```bash
sudo ./deploy-n8n.sh --dry-run
```

Shows what would be done without making changes.

---

## Management Commands

### Update Installation

Update to latest n8n version:

```bash
sudo ./deploy-n8n.sh --update
```

### Health Check

Run comprehensive health check:

```bash
./deploy-n8n.sh --check-health
```

Checks:
- Container status
- n8n health endpoint
- SSL certificate validity
- Database connectivity
- Redis connectivity
- System resources

### Manual Backup

Trigger immediate backup:

```bash
./deploy-n8n.sh --backup
```

### Uninstall

Complete removal (with confirmation prompts):

```bash
sudo ./deploy-n8n.sh --uninstall
```

**Warning**: This removes all containers, volumes, and data. Backups are preserved.

---

## CLI Options Reference

### Installation Options

| Option | Description | Default |
|--------|-------------|---------|
| `-d, --domain DOMAIN` | Domain for n8n | Interactive prompt |
| `-e, --email EMAIL` | Let's Encrypt email | Interactive prompt |
| `-t, --timezone TZ` | Server timezone | UTC |
| `--install-dir DIR` | Installation path | /opt/n8n |

### Behavior Flags

| Flag | Description |
|------|-------------|
| `-y, --yes` | Non-interactive mode (auto-accept) |
| `--skip-security` | Skip SSH hardening and Fail2ban |
| `--dry-run` | Preview without executing |
| `--verbose` | Enable debug output |

### Actions

| Action | Description |
|--------|-------------|
| `--update` | Update existing installation |
| `--uninstall` | Remove installation |
| `--backup` | Run backup only |
| `--check-health` | Health check only |
| `-h, --help` | Show usage |

---

## What Gets Installed

### Services

1. **Traefik** (v2.11) - Reverse proxy with automatic SSL
2. **PostgreSQL 16** - Primary database
3. **Redis 7** - Queue broker
4. **n8n** (latest) - Main application (editor/webhooks)
5. **n8n-worker** (latest) - Queue execution worker

### Directory Structure

```
/opt/n8n/
├── docker-compose.yml      # Service orchestration
├── .env                    # Environment variables (chmod 600)
├── traefik/
│   ├── traefik.yml        # Static configuration
│   ├── acme.json          # SSL certificates (chmod 600)
│   ├── config/
│   │   └── dynamic.yml    # Dynamic configuration
│   └── logs/              # Access logs
├── postgres/              # PostgreSQL data (volume)
├── redis/                 # Redis data (volume)
├── n8n-data/              # n8n workflows (volume)
├── backups/
│   ├── postgres/          # Database dumps
│   ├── volumes/           # Volume archives
│   └── config_*.tar.gz    # Configuration backups
└── scripts/
    ├── backup-postgres.sh # PostgreSQL backup
    ├── backup-all.sh      # Complete backup
    └── healthcheck.sh     # Health monitoring
```

### Security Configuration

- **UFW Firewall**: Enabled with ports 22, 80, 443
- **Docker UFW Fix**: Applied to prevent Docker bypassing firewall
- **SSH Hardening** (optional): Key-only auth, no root login
- **Fail2ban**: SSH brute-force protection
- **SSL/TLS**: Automatic Let's Encrypt certificates
- **Security Headers**: HSTS, XSS protection, frame deny

---

## Post-Installation

### First-Time Setup

1. **Access n8n**:
   - Navigate to: `https://your-domain.com`
   - You'll see the n8n setup wizard

2. **Create Admin User**:
   - Fill in the registration form
   - This creates your first owner account

3. **Start Building**:
   - Create your first workflow
   - Test webhooks
   - Configure integrations

### Important Files

**Save these credentials** (shown during installation):
- PostgreSQL password
- n8n encryption key

Both are stored in: `/opt/n8n/.env` (chmod 600)

**⚠️ WARNING**: If you lose the n8n encryption key, you cannot decrypt stored credentials!

### Useful Commands

```bash
# View logs (all services)
docker compose -f /opt/n8n/docker-compose.yml logs -f

# View logs (specific service)
docker compose -f /opt/n8n/docker-compose.yml logs -f n8n

# Check container status
docker compose -f /opt/n8n/docker-compose.yml ps

# Restart services
docker compose -f /opt/n8n/docker-compose.yml restart

# Stop all services
docker compose -f /opt/n8n/docker-compose.yml down

# Start all services
docker compose -f /opt/n8n/docker-compose.yml up -d

# Run health check
/opt/n8n/scripts/healthcheck.sh

# Manual backup
/opt/n8n/scripts/backup-all.sh

# View backup logs
tail -f /var/log/n8n-backup.log
```

---

## Resource Allocation

The script automatically adjusts resource limits based on available RAM:

### 8GB RAM (Minimum)

| Service | Memory Limit |
|---------|--------------|
| PostgreSQL | 2GB |
| Redis | 512MB |
| n8n | 1.5GB |
| n8n-worker | 1.5GB |
| Traefik | 256MB |

### 12GB RAM (Recommended)

| Service | Memory Limit |
|---------|--------------|
| PostgreSQL | 4GB |
| Redis | 1GB |
| n8n | 2GB |
| n8n-worker | 2GB |
| Traefik | 256MB |

### 16GB+ RAM

| Service | Memory Limit |
|---------|--------------|
| PostgreSQL | 6GB |
| Redis | 2GB |
| n8n | 3GB |
| n8n-worker | 3GB |
| Traefik | 256MB |

---

## Backup & Recovery

### Automated Backups

If enabled during installation:
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

### Restore from Backup

#### Restore PostgreSQL Database

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

#### Restore Complete System

```bash
# Stop all services
cd /opt/n8n
docker compose down

# Restore volumes
tar -xzf backups/volumes/volumes_YYYY-MM-DD_HH-MM-SS.tar.gz -C /

# Restore configuration
tar -xzf backups/config_YYYY-MM-DD_HH-MM-SS.tar.gz -C /opt/n8n

# Start services
docker compose up -d
```

---

## Logs

### Deployment Logs

- **Main log**: `/var/log/n8n-deploy.log`
- **Error log**: `/var/log/n8n-deploy-error.log`
- **Backup log**: `/var/log/n8n-backup.log`

### Application Logs

```bash
# All services
docker compose -f /opt/n8n/docker-compose.yml logs -f

# Specific service
docker compose -f /opt/n8n/docker-compose.yml logs -f n8n
docker compose -f /opt/n8n/docker-compose.yml logs -f traefik
docker compose -f /opt/n8n/docker-compose.yml logs -f postgres

# Last 100 lines
docker compose -f /opt/n8n/docker-compose.yml logs --tail=100 n8n

# Traefik access logs
tail -f /opt/n8n/traefik/logs/access.log | jq .
```

---

## Troubleshooting

See [TROUBLESHOOTING_AUTOMATION.md](./TROUBLESHOOTING_AUTOMATION.md) for detailed troubleshooting guide.

Common issues:
- DNS not configured
- Ports already in use
- SSL certificate fails
- Containers not starting
- Memory issues

---

## Security Considerations

### What the Script Secures

✅ Firewall configured (UFW)
✅ Docker firewall bypass fix applied
✅ SSL/TLS with Let's Encrypt
✅ Security headers (HSTS, XSS, etc.)
✅ Fail2ban for SSH protection
✅ SSH hardening (optional)
✅ Secure file permissions (.env, acme.json)

### What You Should Do

- Keep SSH keys secure
- Enable 2FA for n8n admin account
- Regularly update containers (`--update`)
- Monitor backup logs
- Review access logs periodically
- Keep the encryption key backed up

### External Security

The script configures UFW on the server. If your VPS provider has additional firewalls:
- **OVH**: Configure Edge Network Firewall
- **Hetzner**: Configure Cloud Firewall
- **AWS**: Configure Security Groups
- **DigitalOcean**: Configure Cloud Firewalls

Ensure ports 80 and 443 are allowed at the provider level.

---

## Updating n8n

### Update to Latest Version

```bash
sudo ./deploy-n8n.sh --update
```

This will:
1. Pull latest Docker images
2. Recreate containers with new versions
3. Preserve all data and configurations
4. Verify services are healthy

### Rollback

If update causes issues:

```bash
cd /opt/n8n

# Stop services
docker compose down

# Pull specific version
# Edit docker-compose.yml and change: image: n8nio/n8n:latest
# to: image: n8nio/n8n:1.X.X

# Restart with specific version
docker compose up -d
```

---

## Compatibility

### Tested Platforms

✅ Ubuntu 22.04 LTS (Jammy)
✅ Ubuntu 24.04 LTS (Noble)
✅ Ubuntu 25.10 (Oracular)
✅ Debian 11 (Bullseye)
✅ Debian 12 (Bookworm)

### VPS Providers

✅ OVH
✅ Hetzner
✅ DigitalOcean
✅ Linode
✅ Vultr
✅ AWS EC2
✅ Google Cloud
✅ Any provider with Ubuntu/Debian

---

## Support

### Getting Help

1. Check [TROUBLESHOOTING_AUTOMATION.md](./TROUBLESHOOTING_AUTOMATION.md)
2. Review deployment logs: `/var/log/n8n-deploy.log`
3. Check container logs: `docker compose logs`
4. Run health check: `./deploy-n8n.sh --check-health`

### Reporting Issues

When reporting issues, include:
- OS version: `lsb_release -a`
- RAM: `free -h`
- Disk: `df -h`
- Deployment log: `/var/log/n8n-deploy.log`
- Error log: `/var/log/n8n-deploy-error.log`
- Container status: `docker compose ps`

---

## License

MIT License - See LICENSE file

---

## Credits

Automation script for the [n8n VPS Deployment](https://github.com/buildz-ops/n8n-vps-deployment) project.
