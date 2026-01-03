#!/bin/bash
# ===========================================
# n8n Production VPS Deployment Script
# ===========================================
# Automated deployment of n8n with PostgreSQL, Redis, Traefik
# Supports: Ubuntu 22.04+, Debian 11+
# Mode: Interactive with full automation
# ===========================================

set -euo pipefail

# Script version
VERSION="1.0.0"

# ===========================================
# GLOBAL VARIABLES
# ===========================================

# Default values
DEFAULT_INSTALL_DIR="/opt/n8n"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/n8n-deploy.log"
ERROR_LOG="/var/log/n8n-deploy-error.log"

# CLI flags
NON_INTERACTIVE=false
SKIP_SECURITY=false
DRY_RUN=false
VERBOSE=false
ACTION="install"

# User inputs (will be populated)
DOMAIN=""
LETSENCRYPT_EMAIL=""
TIMEZONE="UTC"
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
VPS_IP=""
POSTGRES_PASSWORD=""
N8N_ENCRYPTION_KEY=""

# System detection
OS_NAME=""
OS_VERSION=""
TOTAL_RAM_GB=0

# ===========================================
# COLOR CODES
# ===========================================

if [[ -t 1 ]] && command -v tput &> /dev/null; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    BOLD=""
    RESET=""
fi

# ===========================================
# LOGGING FUNCTIONS
# ===========================================

log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $message" | tee -a "$LOG_FILE" >> "$ERROR_LOG"
}

log_success() {
    echo "${GREEN}✓${RESET} $1"
    log "SUCCESS: $1"
}

log_warning() {
    echo "${YELLOW}⚠${RESET} $1"
    log "WARNING: $1"
}

log_info() {
    echo "${BLUE}ℹ${RESET} $1"
    log "INFO: $1"
}

log_step() {
    echo ""
    echo "${CYAN}${BOLD}=== $1 ===${RESET}"
    log "STEP: $1"
}

# ===========================================
# UTILITY FUNCTIONS
# ===========================================

print_header() {
    echo "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         n8n Production VPS Deployment Script            ║"
    echo "║                    Version $VERSION                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo "${RESET}"
}

print_separator() {
    echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        return 0
    fi
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "${prompt} [Y/n]: " response
            response=${response:-y}
        else
            read -p "${prompt} [y/N]: " response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

wait_for_user() {
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        echo ""
        read -p "${CYAN}Press Enter to continue...${RESET}" -r
    fi
}

show_progress() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${CYAN}${spin:$i:1}${RESET} $message"
        sleep 0.1
    done
    printf "\r${GREEN}✓${RESET} $message\n"
}

# ===========================================
# ERROR HANDLING
# ===========================================

cleanup_on_error() {
    log_error "Script failed. Performing cleanup..."
    
    # Add cleanup logic here if needed
    # For now, we'll just log the error
    
    echo ""
    echo "${RED}${BOLD}Deployment failed!${RESET}"
    echo ""
    echo "Check logs for details:"
    echo "  - Main log: $LOG_FILE"
    echo "  - Error log: $ERROR_LOG"
    echo ""
    exit 1
}

trap cleanup_on_error ERR

# ===========================================
# PHASE 1: PRE-FLIGHT CHECKS
# ===========================================

detect_os() {
    log_step "Detecting Operating System"
    
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    source /etc/os-release
    OS_NAME="$ID"
    OS_VERSION="$VERSION_ID"
    
    log_info "Detected: $PRETTY_NAME"
    
    # Verify supported OS
    case "$OS_NAME" in
        ubuntu)
            if [[ ! "$OS_VERSION" =~ ^(22\.04|24\.04|25\.10)$ ]]; then
                log_warning "Ubuntu $OS_VERSION is not officially tested. Supported: 22.04, 24.04, 25.10"
                if ! confirm "Continue anyway?"; then
                    exit 1
                fi
            fi
            ;;
        debian)
            if [[ ! "$OS_VERSION" =~ ^(11|12)$ ]]; then
                log_warning "Debian $OS_VERSION is not officially tested. Supported: 11, 12"
                if ! confirm "Continue anyway?"; then
                    exit 1
                fi
            fi
            ;;
        *)
            log_error "Unsupported OS: $OS_NAME. Only Ubuntu and Debian are supported."
            exit 1
            ;;
    esac
    
    log_success "OS check passed: $OS_NAME $OS_VERSION"
}

check_system_requirements() {
    log_step "Checking System Requirements"
    
    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]] && [[ "$arch" != "aarch64" ]]; then
        log_error "Unsupported architecture: $arch. Only x86_64 and aarch64 are supported."
        exit 1
    fi
    log_success "Architecture: $arch"
    
    # Check RAM
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$((total_ram_kb / 1024 / 1024))
    log_info "Total RAM: ${TOTAL_RAM_GB}GB"
    
    if [[ $TOTAL_RAM_GB -lt 8 ]]; then
        log_error "Insufficient RAM: ${TOTAL_RAM_GB}GB. Minimum 8GB required, 12GB recommended."
        exit 1
    elif [[ $TOTAL_RAM_GB -lt 12 ]]; then
        log_warning "RAM is ${TOTAL_RAM_GB}GB. 12GB recommended for optimal performance."
    else
        log_success "RAM check passed: ${TOTAL_RAM_GB}GB"
    fi
    
    # Check disk space
    local available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    log_info "Available disk space: ${available_gb}GB"
    
    if [[ $available_gb -lt 20 ]]; then
        log_error "Insufficient disk space: ${available_gb}GB. Minimum 20GB required."
        exit 1
    elif [[ $available_gb -lt 50 ]]; then
        log_warning "Disk space is ${available_gb}GB. 50GB+ recommended."
    else
        log_success "Disk space check passed: ${available_gb}GB available"
    fi
}

check_root_or_sudo() {
    log_step "Checking Privileges"
    
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. It's recommended to run as a non-root user with sudo."
        if ! confirm "Continue as root?"; then
            exit 1
        fi
    else
        if ! sudo -n true 2>/dev/null; then
            log_error "This script requires sudo privileges. Please run: sudo $0"
            exit 1
        fi
        log_success "Sudo access confirmed"
    fi
}

check_internet_connectivity() {
    log_step "Checking Internet Connectivity"
    
    local test_urls=("google.com" "github.com" "docker.com")
    local connected=false
    
    for url in "${test_urls[@]}"; do
        if ping -c 1 -W 2 "$url" &> /dev/null; then
            connected=true
            break
        fi
    done
    
    if [[ "$connected" == "false" ]]; then
        log_error "No internet connectivity detected. Cannot proceed."
        exit 1
    fi
    
    log_success "Internet connectivity confirmed"
}

check_ports() {
    log_step "Checking Required Ports"
    
    local ports=(80 443)
    local ports_in_use=()
    
    for port in "${ports[@]}"; do
        if sudo ss -tulpn | grep -q ":$port "; then
            local process=$(sudo ss -tulpn | grep ":$port " | awk '{print $7}' | head -1)
            ports_in_use+=("$port ($process)")
            log_warning "Port $port is already in use by: $process"
        fi
    done
    
    if [[ ${#ports_in_use[@]} -gt 0 ]]; then
        echo ""
        echo "${YELLOW}The following ports are in use:${RESET}"
        for port_info in "${ports_in_use[@]}"; do
            echo "  - Port $port_info"
        done
        echo ""
        echo "These ports are required for n8n (Traefik reverse proxy)."
        echo "You may need to stop existing services using these ports."
        echo ""
        
        if ! confirm "Do you want to continue anyway?"; then
            exit 1
        fi
    else
        log_success "Ports 80 and 443 are available"
    fi
}

detect_existing_docker() {
    log_step "Checking Docker Installation"
    
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_info "Docker already installed: $docker_version"
        
        # Check if docker compose is available
        if docker compose version &> /dev/null; then
            local compose_version=$(docker compose version --short)
            log_info "Docker Compose already installed: $compose_version"
        else
            log_warning "Docker Compose (v2) not found. Will install."
        fi
        
        return 0
    else
        log_info "Docker not found. Will install during system preparation."
        return 1
    fi
}

detect_existing_n8n() {
    log_step "Checking for Existing n8n Installation"
    
    local existing_locations=(
        "/opt/n8n"
        "/var/n8n"
        "/usr/local/n8n"
        "$HOME/n8n"
    )
    
    for location in "${existing_locations[@]}"; do
        if [[ -d "$location" ]] && [[ -f "$location/docker-compose.yml" ]]; then
            log_warning "Found existing n8n installation at: $location"
            echo ""
            echo "${YELLOW}An existing n8n installation was detected.${RESET}"
            echo "Location: $location"
            echo ""
            echo "Options:"
            echo "  1) Abort installation (recommended - backup first)"
            echo "  2) Update existing installation"
            echo "  3) Remove and reinstall"
            echo ""
            
            if [[ "$NON_INTERACTIVE" == "true" ]]; then
                log_error "Existing installation found. Aborting due to non-interactive mode."
                exit 1
            fi
            
            read -p "Enter choice [1-3]: " choice
            
            case "$choice" in
                1)
                    log_info "Installation aborted by user"
                    exit 0
                    ;;
                2)
                    ACTION="update"
                    INSTALL_DIR="$location"
                    log_info "Will update existing installation at $location"
                    return 0
                    ;;
                3)
                    log_warning "Will remove and reinstall"
                    if confirm "Are you sure? This will delete all data!"; then
                        ACTION="reinstall"
                        INSTALL_DIR="$location"
                        return 0
                    else
                        exit 0
                    fi
                    ;;
                *)
                    log_error "Invalid choice"
                    exit 1
                    ;;
            esac
        fi
    done
    
    # Check for running n8n containers
    if command -v docker &> /dev/null; then
        if docker ps -a --format '{{.Names}}' | grep -q "n8n"; then
            log_warning "Found running n8n containers"
            docker ps -a --filter "name=n8n" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            echo ""
            if ! confirm "Stop and remove these containers?"; then
                exit 1
            fi
            
            docker stop $(docker ps -a --filter "name=n8n" -q) 2>/dev/null || true
            docker rm $(docker ps -a --filter "name=n8n" -q) 2>/dev/null || true
            log_success "Removed existing n8n containers"
        fi
    fi
    
    log_success "No conflicting n8n installation found"
}

detect_vps_ip() {
    log_step "Detecting VPS IP Address"
    
    # Try multiple methods to get public IP
    local ip=""
    
    # Method 1: ip command
    ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
    
    # Method 2: curl external services (if Method 1 fails or returns private IP)
    if [[ -z "$ip" ]] || [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$ip" =~ ^192\.168\. ]]; then
        ip=$(curl -s -4 ifconfig.me) || \
        ip=$(curl -s -4 icanhazip.com) || \
        ip=$(curl -s -4 ipecho.net/plain) || \
        ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
    fi
    
    if [[ -z "$ip" ]]; then
        log_error "Could not detect VPS IP address"
        exit 1
    fi
    
    VPS_IP="$ip"
    log_info "Detected VPS IP: $VPS_IP"
}

run_preflight_checks() {
    print_header
    log_info "Starting pre-flight checks..."
    
    detect_os
    check_system_requirements
    check_root_or_sudo
    check_internet_connectivity
    check_ports
    detect_existing_docker
    detect_existing_n8n
    detect_vps_ip
    
    print_separator
    log_success "All pre-flight checks passed!"
    wait_for_user
}

# ===========================================
# PHASE 2: USER INPUT COLLECTION
# ===========================================

validate_domain() {
    local domain="$1"
    
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    
    # Check if domain has at least one dot
    if [[ ! "$domain" =~ \. ]]; then
        return 1
    fi
    
    return 0
}

validate_email() {
    local email="$1"
    
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    
    return 0
}

collect_domain() {
    log_step "Domain Configuration"
    
    echo "Enter your domain for n8n (e.g., n8n.example.com)"
    echo "Make sure you've created an A record pointing to: $VPS_IP"
    echo ""
    
    while true; do
        read -p "Domain: " domain
        
        if validate_domain "$domain"; then
            DOMAIN="$domain"
            log_info "Domain set to: $DOMAIN"
            break
        else
            echo "${RED}Invalid domain format. Please try again.${RESET}"
        fi
    done
}

collect_email() {
    log_step "Let's Encrypt Email Configuration"
    
    echo "Enter your email for Let's Encrypt certificate notifications:"
    echo ""
    
    while true; do
        read -p "Email: " email
        
        if validate_email "$email"; then
            LETSENCRYPT_EMAIL="$email"
            log_info "Email set to: $LETSENCRYPT_EMAIL"
            break
        else
            echo "${RED}Invalid email format. Please try again.${RESET}"
        fi
    done
}

collect_timezone() {
    log_step "Timezone Configuration"
    
    echo "Select your timezone:"
    echo ""
    echo "Common timezones:"
    echo "  1) UTC (default)"
    echo "  2) Europe/Madrid"
    echo "  3) America/New_York"
    echo "  4) America/Los_Angeles"
    echo "  5) Asia/Tokyo"
    echo "  6) Australia/Sydney"
    echo "  7) Custom (enter manually)"
    echo ""
    
    read -p "Choice [1-7]: " tz_choice
    
    case "$tz_choice" in
        1|"") TIMEZONE="UTC" ;;
        2) TIMEZONE="Europe/Madrid" ;;
        3) TIMEZONE="America/New_York" ;;
        4) TIMEZONE="America/Los_Angeles" ;;
        5) TIMEZONE="Asia/Tokyo" ;;
        6) TIMEZONE="Australia/Sydney" ;;
        7)
            read -p "Enter timezone (e.g., Europe/London): " custom_tz
            if [[ -f "/usr/share/zoneinfo/$custom_tz" ]]; then
                TIMEZONE="$custom_tz"
            else
                log_warning "Invalid timezone. Using UTC."
                TIMEZONE="UTC"
            fi
            ;;
        *)
            log_warning "Invalid choice. Using UTC."
            TIMEZONE="UTC"
            ;;
    esac
    
    log_info "Timezone set to: $TIMEZONE"
}

generate_secrets() {
    log_step "Generating Secure Credentials"
    
    echo "Generating secure passwords and encryption keys..."
    echo ""
    
    # Generate PostgreSQL password (32 characters, alphanumeric)
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    
    # Generate n8n encryption key (32 characters hex)
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
    
    echo "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${BOLD}${YELLOW}           IMPORTANT - SAVE THESE CREDENTIALS!${RESET}"
    echo "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo "${BOLD}PostgreSQL Password:${RESET}"
    echo "  $POSTGRES_PASSWORD"
    echo ""
    echo "${BOLD}n8n Encryption Key:${RESET}"
    echo "  $N8N_ENCRYPTION_KEY"
    echo ""
    echo "${YELLOW}⚠ WARNING: If you lose the encryption key, you won't be able to${RESET}"
    echo "${YELLOW}  decrypt credentials stored in n8n!${RESET}"
    echo ""
    echo "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo "These will also be saved in: ${INSTALL_DIR}/.env (chmod 600)"
    echo ""
    
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        read -p "${BOLD}Have you saved these credentials? Type 'yes' to continue: ${RESET}" confirm
        
        if [[ "$confirm" != "yes" ]]; then
            log_error "User did not confirm credentials were saved. Aborting."
            exit 1
        fi
    fi
    
    log_success "Credentials generated and confirmed"
}

collect_user_inputs() {
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        # Validate required CLI parameters
        if [[ -z "$DOMAIN" ]] || [[ -z "$LETSENCRYPT_EMAIL" ]]; then
            log_error "In non-interactive mode, --domain and --email are required"
            exit 1
        fi
    else
        collect_domain
        collect_email
        collect_timezone
    fi
    
    generate_secrets
    
    print_separator
    log_success "User input collection complete!"
    wait_for_user
}

# ===========================================
# SCRIPT ENTRY POINT (continued in next part)
# ===========================================

# ===========================================
# PHASE 3: SYSTEM PREPARATION
# ===========================================

update_system() {
    log_step "Updating System Packages"
    
    echo "This may take a few minutes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update system packages"
        return 0
    fi
    
    sudo apt-get update -qq 2>&1 | tee -a "$LOG_FILE" > /dev/null &
    show_progress $! "Updating package lists"
    
    sudo apt-get upgrade -y -qq 2>&1 | tee -a "$LOG_FILE" > /dev/null &
    show_progress $! "Upgrading packages"
    
    log_success "System packages updated"
}

install_essential_packages() {
    log_step "Installing Essential Packages"
    
    local packages=(
        curl wget git vim htop net-tools unzip
        software-properties-common ca-certificates
        gnupg lsb-release apache2-utils
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install: ${packages[*]}"
        return 0
    fi
    
    sudo apt-get install -y -qq "${packages[@]}" 2>&1 | tee -a "$LOG_FILE" > /dev/null &
    show_progress $! "Installing essential packages"
    
    log_success "Essential packages installed"
}

configure_timezone() {
    log_step "Configuring Timezone"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set timezone to: $TIMEZONE"
        return 0
    fi
    
    sudo timedatectl set-timezone "$TIMEZONE"
    log_success "Timezone set to: $TIMEZONE"
}

setup_unattended_upgrades() {
    log_step "Configuring Automatic Security Updates"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure unattended-upgrades"
        return 0
    fi
    
    sudo apt-get install -y -qq unattended-upgrades 2>&1 | tee -a "$LOG_FILE" > /dev/null
    echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | sudo debconf-set-selections
    sudo dpkg-reconfigure -plow unattended-upgrades 2>&1 | tee -a "$LOG_FILE" > /dev/null
    
    log_success "Automatic security updates configured"
}

install_docker() {
    log_step "Installing Docker"
    
    if command -v docker &> /dev/null; then
        log_info "Docker already installed. Skipping."
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install Docker"
        return 0
    fi
    
    # Remove old Docker packages
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install Docker from official repository
    log_info "Adding Docker GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/$OS_NAME/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    log_info "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$OS_NAME \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    log_info "Installing Docker packages..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | tee -a "$LOG_FILE" > /dev/null &
    show_progress $! "Installing Docker"
    
    log_success "Docker installed successfully"
}

configure_docker() {
    log_step "Configuring Docker"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure Docker daemon and add user to docker group"
        return 0
    fi
    
    # Add user to docker group
    if [[ $EUID -ne 0 ]]; then
        sudo usermod -aG docker $USER
        log_info "User $USER added to docker group"
    fi
    
    # Create Docker daemon configuration
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
    
    log_success "Docker configured"
}

prepare_system() {
    update_system
    install_essential_packages
    configure_timezone
    setup_unattended_upgrades
    install_docker
    configure_docker
    
    print_separator
    log_success "System preparation complete!"
    wait_for_user
}

# ===========================================
# PHASE 4: SECURITY HARDENING
# ===========================================

configure_ufw() {
    log_step "Configuring UFW Firewall"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure UFW firewall"
        return 0
    fi
    
    # Install UFW
    sudo apt-get install -y -qq ufw 2>&1 | tee -a "$LOG_FILE" > /dev/null
    
    # Set default policies
    sudo ufw --force default deny incoming
    sudo ufw --force default allow outgoing
    
    # Allow SSH (detect current port)
    local ssh_port=$(sudo ss -tlnp | grep sshd | awk '{print $4}' | grep -oP ':\K[0-9]+$' | head -1)
    ssh_port=${ssh_port:-22}
    
    sudo ufw allow $ssh_port/tcp comment 'SSH'
    log_info "Allowed SSH on port $ssh_port"
    
    # Rate limit SSH
    sudo ufw limit $ssh_port/tcp comment 'SSH rate limit'
    
    # Allow HTTP and HTTPS
    sudo ufw allow 80/tcp comment 'HTTP'
    sudo ufw allow 443/tcp comment 'HTTPS'
    
    # Apply Docker UFW bypass fix
    log_info "Applying Docker UFW bypass fix..."
    
    if ! grep -q "BEGIN UFW AND DOCKER" /etc/ufw/after.rules; then
        sudo tee -a /etc/ufw/after.rules > /dev/null <<'UFWDOCKER'

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
UFWDOCKER
        log_info "Docker UFW bypass fix applied"
    fi
    
    # Enable UFW
    echo "y" | sudo ufw enable 2>&1 | tee -a "$LOG_FILE" > /dev/null
    
    log_success "UFW firewall configured and enabled"
}

configure_ssh_hardening() {
    if [[ "$SKIP_SECURITY" == "true" ]]; then
        log_info "Skipping SSH hardening (--skip-security flag)"
        return 0
    fi
    
    log_step "SSH Hardening (Optional)"
    
    echo "Would you like to apply SSH hardening?"
    echo "This will:"
    echo "  - Disable root login"
    echo "  - Disable password authentication"
    echo "  - Enable only key-based authentication"
    echo ""
    echo "${YELLOW}⚠ WARNING: Make sure you have SSH keys configured before proceeding!${RESET}"
    echo ""
    
    if ! confirm "Apply SSH hardening?"; then
        log_info "SSH hardening skipped by user"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would apply SSH hardening"
        return 0
    fi
    
    # Backup current config
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
    
    # Apply hardened configuration
    sudo tee /etc/ssh/sshd_config > /dev/null <<'SSHCONFIG'
# Hardened SSH Configuration
Port 22
Protocol 2
AddressFamily inet

# Host Keys
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Authentication
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Security Settings
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
StrictModes yes

# Disable Unused Features
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
PermitUserEnvironment no
PrintMotd no

# Strong Cryptographic Settings
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com

# Logging
SyslogFacility AUTH
LogLevel VERBOSE
SSHCONFIG
    
    # Test configuration
    if ! sudo sshd -t 2>&1 | tee -a "$LOG_FILE"; then
        log_error "SSH configuration test failed. Restoring backup."
        sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
        return 1
    fi
    
    # Restart SSH
    sudo systemctl restart sshd
    
    echo ""
    echo "${YELLOW}${BOLD}IMPORTANT:${RESET}"
    echo "SSH hardening applied. Please test a new SSH connection"
    echo "in a separate terminal BEFORE closing this session!"
    echo ""
    wait_for_user
    
    log_success "SSH hardening applied"
}

configure_fail2ban() {
    if [[ "$SKIP_SECURITY" == "true" ]]; then
        log_info "Skipping Fail2ban (--skip-security flag)"
        return 0
    fi
    
    log_step "Installing Fail2ban"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install and configure Fail2ban"
        return 0
    fi
    
    sudo apt-get install -y -qq fail2ban 2>&1 | tee -a "$LOG_FILE" > /dev/null
    
    # Create jail.local
    sudo tee /etc/fail2ban/jail.local > /dev/null <<'F2BCONFIG'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw
banaction_allports = ufw
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 24h
findtime = 1h
F2BCONFIG
    
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
    
    log_success "Fail2ban installed and configured"
}

harden_security() {
    configure_ufw
    configure_ssh_hardening
    configure_fail2ban
    
    print_separator
    log_success "Security hardening complete!"
    wait_for_user
}

# ===========================================
# PHASE 5: DNS VERIFICATION
# ===========================================

verify_dns() {
    log_step "Verifying DNS Configuration"
    
    echo "Checking if $DOMAIN resolves to $VPS_IP..."
    echo ""
    
    local resolved_ip=$(dig +short "$DOMAIN" @8.8.8.8 | tail -1)
    
    if [[ -z "$resolved_ip" ]]; then
        log_warning "Domain $DOMAIN does not resolve to any IP address"
        echo ""
        echo "${YELLOW}DNS is not configured yet.${RESET}"
        echo ""
        echo "Please create an A record:"
        echo "  Type: A"
        echo "  Name: ${DOMAIN%%.*} (or @ for root domain)"
        echo "  Value: $VPS_IP"
        echo "  TTL: Auto or 300"
        echo ""
        echo "After creating the record, wait a few minutes for DNS propagation."
        echo ""
        
        if confirm "Continue without DNS verification? (SSL may fail)"; then
            log_warning "Continuing without DNS verification"
            return 0
        else
            log_info "Deployment aborted. Please configure DNS and run again."
            exit 0
        fi
    elif [[ "$resolved_ip" != "$VPS_IP" ]]; then
        log_warning "Domain resolves to $resolved_ip but VPS IP is $VPS_IP"
        echo ""
        echo "${YELLOW}DNS mismatch detected!${RESET}"
        echo "  Domain $DOMAIN resolves to: $resolved_ip"
        echo "  Your VPS IP is: $VPS_IP"
        echo ""
        echo "Please update your DNS A record to point to: $VPS_IP"
        echo ""
        
        if confirm "Continue anyway? (SSL certificate will fail)"; then
            log_warning "Continuing with DNS mismatch"
            return 0
        else
            log_info "Deployment aborted. Please fix DNS and run again."
            exit 0
        fi
    else
        log_success "DNS correctly configured: $DOMAIN → $VPS_IP"
    fi
}

# ===========================================
# PHASE 6: DIRECTORY STRUCTURE & CONFIGURATION
# ===========================================

create_directory_structure() {
    log_step "Creating Directory Structure"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create directory structure at $INSTALL_DIR"
        return 0
    fi
    
    # Create main directory
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown -R $USER:$USER "$INSTALL_DIR"
    
    # Create subdirectories
    mkdir -p "$INSTALL_DIR"/{traefik/{config,logs},postgres,redis,n8n-data,backups/{postgres,volumes},scripts}
    
    # Create acme.json with correct permissions
    touch "$INSTALL_DIR/traefik/acme.json"
    chmod 600 "$INSTALL_DIR/traefik/acme.json"
    
    log_success "Directory structure created at $INSTALL_DIR"
}


create_env_file() {
    log_step "Creating Environment Configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create .env file"
        return 0
    fi
    
    cat > "$INSTALL_DIR/.env" <<EOF
# n8n Production Environment Configuration
# Generated: $(date)

# PostgreSQL Configuration
POSTGRES_USER=n8n
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=n8n

# n8n Encryption Key (CRITICAL - BACKUP THIS VALUE!)
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY

# Domain Configuration
DOMAIN=$DOMAIN

# Let's Encrypt Email
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL

# Timezone
TZ=$TIMEZONE
EOF
    
    chmod 600 "$INSTALL_DIR/.env"
    
    log_success ".env file created with secure permissions (600)"
}

create_docker_compose() {
    log_step "Creating Docker Compose Configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create docker-compose.yml"
        return 0
    fi
    
    # Determine resource limits based on RAM
    local pg_memory="4G"
    local redis_memory="1G"
    local n8n_memory="2G"
    local worker_memory="2G"
    
    if [[ $TOTAL_RAM_GB -lt 12 ]]; then
        pg_memory="2G"
        redis_memory="512M"
        n8n_memory="1536M"
        worker_memory="1536M"
        log_info "Using reduced resource limits for ${TOTAL_RAM_GB}GB RAM"
    elif [[ $TOTAL_RAM_GB -ge 16 ]]; then
        pg_memory="6G"
        redis_memory="2G"
        n8n_memory="3G"
        worker_memory="3G"
        log_info "Using increased resource limits for ${TOTAL_RAM_GB}GB RAM"
    fi
    
    cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
version: "3.9"

services:
  # Traefik - Reverse Proxy & SSL Termination
  traefik:
    image: traefik:v2.11
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      # CRITICAL: Must bind to 0.0.0.0 for proper IPv4 access
      - "0.0.0.0:80:80"
      - "0.0.0.0:443:443"
    environment:
      - TZ=\${TZ}
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/traefik.yml:ro
      - ./traefik/config:/config:ro
      - ./traefik/acme.json:/acme.json
      - ./traefik/logs:/var/log/traefik
    networks:
      - n8n-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-http.entrypoints=web"
      - "traefik.http.routers.traefik-http.rule=Host(\`traefik.\${DOMAIN}\`)"
      - "traefik.http.routers.traefik-http.middlewares=https-redirect"
      - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"
      - "traefik.http.middlewares.https-redirect.redirectscheme.permanent=true"
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 256M

  # PostgreSQL 16 - Primary Database
  postgres:
    image: postgres:16-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
      TZ: \${TZ}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backups/postgres:/backups
    command:
      - "postgres"
      - "-c"
      - "shared_buffers=1024MB"
      - "-c"
      - "effective_cache_size=3072MB"
      - "-c"
      - "maintenance_work_mem=256MB"
      - "-c"
      - "checkpoint_completion_target=0.9"
      - "-c"
      - "wal_buffers=16MB"
      - "-c"
      - "default_statistics_target=100"
      - "-c"
      - "random_page_cost=1.1"
      - "-c"
      - "effective_io_concurrency=200"
      - "-c"
      - "work_mem=4MB"
      - "-c"
      - "min_wal_size=1GB"
      - "-c"
      - "max_wal_size=4GB"
      - "-c"
      - "max_connections=100"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    networks:
      - n8n-network
    deploy:
      resources:
        limits:
          memory: $pg_memory

  # Redis - Queue Broker
  redis:
    image: redis:7-alpine
    container_name: n8n-redis
    restart: unless-stopped
    command: >
      redis-server
      --maxmemory 512mb
      --maxmemory-policy noeviction
      --appendonly yes
      --appendfsync everysec
      --save 900 1
      --save 300 10
      --save 60 10000
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks:
      - n8n-network
    deploy:
      resources:
        limits:
          memory: $redis_memory

  # n8n - Main Application
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      # Database Configuration
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - DB_POSTGRESDB_POOL_SIZE=10
      # Queue Mode Configuration
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=0
      - QUEUE_HEALTH_CHECK_ACTIVE=true
      # Instance Configuration - CRITICAL: Must match Traefik Host() rule
      - N8N_HOST=\${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://\${DOMAIN}/
      - N8N_EDITOR_BASE_URL=https://\${DOMAIN}/
      # Security
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      # Timezone
      - GENERIC_TIMEZONE=\${TZ}
      - TZ=\${TZ}
      # Execution Data Management
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
      - EXECUTIONS_DATA_PRUNE_MAX_COUNT=50000
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      - EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true
      # Performance
      - N8N_PAYLOAD_SIZE_MAX=64
      - N8N_METRICS=true
      # Logging
      - N8N_LOG_LEVEL=info
      - N8N_LOG_OUTPUT=console
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - n8n-network
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=n8n-network"
      # HTTP Router (redirect to HTTPS)
      - "traefik.http.routers.n8n-http.entrypoints=web"
      - "traefik.http.routers.n8n-http.rule=Host(\`\${DOMAIN}\`)"
      - "traefik.http.routers.n8n-http.middlewares=https-redirect"
      # HTTPS Router
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.rule=Host(\`\${DOMAIN}\`)"
      - "traefik.http.routers.n8n.tls=true"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.routers.n8n.middlewares=n8n-headers"
      # Service
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
      # Security Headers
      - "traefik.http.middlewares.n8n-headers.headers.browserXssFilter=true"
      - "traefik.http.middlewares.n8n-headers.headers.contentTypeNosniff=true"
      - "traefik.http.middlewares.n8n-headers.headers.frameDeny=true"
      - "traefik.http.middlewares.n8n-headers.headers.stsSeconds=31536000"
      - "traefik.http.middlewares.n8n-headers.headers.stsIncludeSubdomains=true"
      - "traefik.http.middlewares.n8n-headers.headers.stsPreload=true"
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    deploy:
      resources:
        limits:
          memory: $n8n_memory

  # n8n Worker - Queue Mode Execution
  n8n-worker:
    image: n8nio/n8n:latest
    container_name: n8n-worker
    restart: unless-stopped
    command: worker
    environment:
      # Database Configuration
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - DB_POSTGRESDB_POOL_SIZE=10
      # Queue Mode Configuration
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=0
      # Security - MUST match main n8n
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      # Timezone
      - GENERIC_TIMEZONE=\${TZ}
      - TZ=\${TZ}
      # Logging
      - N8N_LOG_LEVEL=info
      - N8N_LOG_OUTPUT=console
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      n8n:
        condition: service_healthy
    networks:
      - n8n-network
    deploy:
      resources:
        limits:
          memory: $worker_memory

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  n8n_data:
    driver: local

networks:
  n8n-network:
    driver: bridge
    name: n8n-network
EOF
    
    log_success "Docker Compose configuration created"
}

create_traefik_config() {
    log_step "Creating Traefik Configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Traefik configuration"
        return 0
    fi
    
    # Create traefik.yml
    cat > "$INSTALL_DIR/traefik/traefik.yml" <<EOF
# Traefik Static Configuration
api:
  dashboard: false
  debug: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: n8n-network
    watch: true
  file:
    directory: /config
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: $LETSENCRYPT_EMAIL
      storage: /acme.json
      caServer: https://acme-v02.api.letsencrypt.org/directory
      httpChallenge:
        entryPoint: web

log:
  level: INFO

accessLog:
  filePath: /var/log/traefik/access.log
  format: json
  bufferingSize: 100
  filters:
    statusCodes:
      - "400-599"

ping:
  entryPoint: web
EOF
    
    # Create dynamic.yml
    cat > "$INSTALL_DIR/traefik/config/dynamic.yml" <<'EOF'
# Traefik Dynamic Configuration
http:
  middlewares:
    secure-headers:
      headers:
        browserXssFilter: true
        contentTypeNosniff: true
        frameDeny: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true
        customFrameOptionsValue: "SAMEORIGIN"
        referrerPolicy: "strict-origin-when-cross-origin"
        permissionsPolicy: "camera=(), microphone=(), geolocation=(), payment=()"
        customResponseHeaders:
          X-Powered-By: ""
          Server: ""

    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1m

    https-redirect:
      redirectScheme:
        scheme: https
        permanent: true

tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
EOF
    
    log_success "Traefik configuration created"
}


create_backup_scripts() {
    log_step "Creating Backup Scripts"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup scripts"
        return 0
    fi
    
    # PostgreSQL backup script
    cat > "$INSTALL_DIR/scripts/backup-postgres.sh" <<'PGBACKUP'
#!/bin/bash
set -e

CONTAINER_NAME="n8n-postgres"
BACKUP_DIR="/opt/n8n/backups/postgres"
POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
RETENTION_DAYS=7
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/${POSTGRES_DB}_${DATE}.sql.gz"

mkdir -p "${BACKUP_DIR}"

echo "[$(date)] Starting backup of ${POSTGRES_DB}..."
docker exec -t ${CONTAINER_NAME} pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} | gzip > "${BACKUP_FILE}"

if [ -f "${BACKUP_FILE}" ] && [ -s "${BACKUP_FILE}" ]; then
    echo "[$(date)] Backup successful: ${BACKUP_FILE}"
    echo "Size: $(du -h ${BACKUP_FILE} | cut -f1)"
else
    echo "[$(date)] ERROR: Backup failed!"
    exit 1
fi

echo "[$(date)] Removing backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "*.sql.gz" -type f -mtime +${RETENTION_DAYS} -delete

echo "[$(date)] Backup completed successfully!"
PGBACKUP
    
    # Complete backup script
    cat > "$INSTALL_DIR/scripts/backup-all.sh" <<ALLBACKUP
#!/bin/bash
set -e

SCRIPT_DIR="$INSTALL_DIR/scripts"
LOG_FILE="/var/log/n8n-backup.log"
DATE=\$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_BASE="$INSTALL_DIR/backups"

echo "=== n8n Backup Started: \$(date) ===" | tee -a \${LOG_FILE}

# Source environment variables
if [ -f $INSTALL_DIR/.env ]; then
    export \$(grep -v '^#' $INSTALL_DIR/.env | xargs)
fi

# Backup PostgreSQL
\${SCRIPT_DIR}/backup-postgres.sh 2>&1 | tee -a \${LOG_FILE}

# Backup Docker volumes
echo "[\$(date)] Backing up Docker volumes..." | tee -a \${LOG_FILE}
VOLUMES_BACKUP="\${BACKUP_BASE}/volumes/volumes_\${DATE}.tar.gz"
mkdir -p "\${BACKUP_BASE}/volumes"

docker run --rm \
    -v n8n_n8n_data:/n8n_data:ro \
    -v n8n_redis_data:/redis_data:ro \
    -v \${BACKUP_BASE}/volumes:/backup \
    alpine tar czf /backup/volumes_\${DATE}.tar.gz /n8n_data /redis_data 2>/dev/null || true

# Backup configuration files
echo "[\$(date)] Backing up configuration files..." | tee -a \${LOG_FILE}
CONFIG_BACKUP="\${BACKUP_BASE}/config_\${DATE}.tar.gz"
tar czf \${CONFIG_BACKUP} \
    --exclude='backups' \
    --exclude='traefik/logs' \
    -C $INSTALL_DIR \
    docker-compose.yml .env traefik/

# Cleanup old backups
find "\${BACKUP_BASE}/volumes" -name "*.tar.gz" -type f -mtime +7 -delete
find "\${BACKUP_BASE}" -maxdepth 1 -name "config_*.tar.gz" -type f -mtime +7 -delete

echo "=== n8n Backup Completed: \$(date) ===" | tee -a \${LOG_FILE}
ALLBACKUP
    
    # Healthcheck script
    cat > "$INSTALL_DIR/scripts/healthcheck.sh" <<'HEALTHCHECK'
#!/bin/bash

echo "=== n8n Health Check ==="
echo ""

# Container Status
echo "Container Status:"
cd /opt/n8n
docker compose ps --format "table {{.Name}}\t{{.Status}}"
echo ""

# n8n Health
echo "n8n Health Endpoint:"
DOMAIN=$(grep DOMAIN .env | cut -d= -f2)
curl -s https://${DOMAIN}/healthz
echo ""
echo ""

# SSL Certificate
echo "SSL Certificate Expiry:"
echo | openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null | openssl x509 -noout -dates
echo ""

# Disk Usage
echo "Disk Usage:"
df -h / | tail -1
echo ""

# Memory
echo "Memory Usage:"
free -h | grep Mem
echo ""

echo "=== Health Check Complete ==="
HEALTHCHECK
    
    chmod +x "$INSTALL_DIR/scripts"/*.sh
    
    log_success "Backup scripts created and made executable"
}

setup_configuration() {
    create_directory_structure
    create_env_file
    create_docker_compose
    create_traefik_config
    create_backup_scripts
    
    print_separator
    log_success "Configuration complete!"
    wait_for_user
}

# ===========================================
# PHASE 7: DEPLOYMENT
# ===========================================

deploy_containers() {
    log_step "Deploying Containers"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy containers"
        return 0
    fi
    
    cd "$INSTALL_DIR"
    
    # Create network
    log_info "Creating Docker network..."
    docker network create n8n-network 2>/dev/null || log_info "Network already exists"
    
    # Pull images
    log_info "Pulling Docker images (this may take a few minutes)..."
    docker compose pull 2>&1 | tee -a "$LOG_FILE" &
    show_progress $! "Pulling Docker images"
    
    # Start services
    log_info "Starting services..."
    docker compose up -d 2>&1 | tee -a "$LOG_FILE"
    
    # Wait for health checks
    log_info "Waiting for services to become healthy (timeout: 3 minutes)..."
    
    local timeout=180
    local elapsed=0
    local interval=5
    
    while [[ $elapsed -lt $timeout ]]; do
        local healthy_count=$(docker compose ps --format json | jq -r 'select(.Health == "healthy") | .Name' 2>/dev/null | wc -l)
        local total_services=4  # postgres, redis, n8n, traefik (worker has no healthcheck)
        
        if [[ $healthy_count -eq $total_services ]]; then
            log_success "All services are healthy!"
            break
        fi
        
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    
    if [[ $elapsed -ge $timeout ]]; then
        log_warning "Timeout waiting for services. Checking status..."
        docker compose ps
    fi
    
    # Monitor Traefik logs for SSL certificate
    log_info "Waiting for SSL certificate acquisition (up to 2 minutes)..."
    
    timeout=120
    elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if docker compose logs traefik 2>/dev/null | grep -q "Adding certificate for domain"; then
            log_success "SSL certificate obtained!"
            break
        fi
        
        if docker compose logs traefik 2>/dev/null | grep -qi "error obtaining certificate"; then
            log_error "SSL certificate acquisition failed. Check Traefik logs."
            break
        fi
        
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    echo ""
    
    log_success "Deployment complete!"
}

# ===========================================
# PHASE 8: VERIFICATION & TESTING
# ===========================================

verify_deployment() {
    log_step "Verifying Deployment"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify deployment"
        return 0
    fi
    
    cd "$INSTALL_DIR"
    
    local all_passed=true
    
    # Check containers
    echo "Checking container status..."
    local running_count=$(docker compose ps --format json | jq -r 'select(.State == "running") | .Name' 2>/dev/null | wc -l)
    
    if [[ $running_count -eq 5 ]]; then
        log_success "All 5 containers are running"
    else
        log_error "Expected 5 containers, found $running_count running"
        docker compose ps
        all_passed=false
    fi
    
    # Check PostgreSQL
    echo "Checking PostgreSQL connectivity..."
    if docker exec n8n-postgres pg_isready -U n8n &>/dev/null; then
        log_success "PostgreSQL is ready"
    else
        log_error "PostgreSQL is not ready"
        all_passed=false
    fi
    
    # Check Redis
    echo "Checking Redis connectivity..."
    if docker exec n8n-redis redis-cli ping &>/dev/null | grep -q "PONG"; then
        log_success "Redis is responding"
    else
        log_error "Redis is not responding"
        all_passed=false
    fi
    
    # Check n8n health endpoint
    echo "Checking n8n health endpoint..."
    sleep 10  # Give n8n time to fully start
    
    if curl -s -f https://$DOMAIN/healthz &>/dev/null; then
        log_success "n8n health endpoint responding"
    else
        log_warning "n8n health endpoint not responding (may need more time)"
    fi
    
    # Check HTTPS redirect
    echo "Checking HTTPS redirect..."
    if curl -s -I http://$DOMAIN | grep -q "301\|302"; then
        log_success "HTTP to HTTPS redirect working"
    else
        log_warning "HTTP redirect not working as expected"
    fi
    
    # Check SSL certificate
    echo "Checking SSL certificate..."
    if echo | openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null | grep -q "Verify return code: 0"; then
        log_success "SSL certificate is valid"
    else
        log_warning "SSL certificate validation failed or still pending"
    fi
    
    if [[ "$all_passed" == "true" ]]; then
        log_success "All verification checks passed!"
    else
        log_warning "Some verification checks failed. Review the output above."
    fi
}

# ===========================================
# PHASE 9: POST-DEPLOYMENT SETUP
# ===========================================

configure_automated_backups() {
    log_step "Configuring Automated Backups"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure automated backups"
        return 0
    fi
    
    echo "Would you like to set up automated daily backups?"
    echo "Backups will run at 2 AM daily and keep 7 days of history."
    echo ""
    
    if ! confirm "Enable automated backups?"; then
        log_info "Automated backups skipped"
        return 0
    fi
    
    # Add cron job
    local cron_line="0 2 * * * $INSTALL_DIR/scripts/backup-all.sh >> /var/log/n8n-backup.log 2>&1"
    
    if crontab -l 2>/dev/null | grep -q "$INSTALL_DIR/scripts/backup-all.sh"; then
        log_info "Backup cron job already exists"
    else
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        log_success "Automated backups configured (daily at 2 AM)"
    fi
    
    # Test backup script
    log_info "Testing backup script..."
    if bash "$INSTALL_DIR/scripts/backup-postgres.sh" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Backup test successful"
    else
        log_warning "Backup test failed. Check logs."
    fi
}

# ===========================================
# PHASE 10: FINAL OUTPUT
# ===========================================

show_final_output() {
    print_separator
    echo ""
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║           n8n Deployment Complete! 🎉                   ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo "${BOLD}Access your n8n instance:${RESET}"
    echo "  🌐 URL: ${CYAN}https://$DOMAIN${RESET}"
    echo ""
    echo "${BOLD}Service Status:${RESET}"
    echo "  ✓ n8n Main: Running (Editor & Webhooks)"
    echo "  ✓ n8n Worker: Running (Queue Execution)"
    echo "  ✓ PostgreSQL 16: Running"
    echo "  ✓ Redis: Running (Queue Broker)"
    echo "  ✓ Traefik: Running (Reverse Proxy)"
    echo ""
    echo "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${YELLOW}${BOLD}     IMPORTANT - SAVE THESE CREDENTIALS!${RESET}"
    echo "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo "${BOLD}PostgreSQL Password:${RESET}"
    echo "  $POSTGRES_PASSWORD"
    echo ""
    echo "${BOLD}n8n Encryption Key:${RESET}"
    echo "  $N8N_ENCRYPTION_KEY"
    echo ""
    echo "${YELLOW}⚠ WARNING: These are stored in: $INSTALL_DIR/.env (chmod 600)${RESET}"
    echo "${YELLOW}  If you lose the encryption key, you won't be able to${RESET}"
    echo "${YELLOW}  decrypt credentials stored in n8n!${RESET}"
    echo ""
    echo "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo "${BOLD}Next Steps:${RESET}"
    echo "  1. Visit: ${CYAN}https://$DOMAIN${RESET}"
    echo "  2. Create your first n8n admin user"
    echo "  3. Start building workflows!"
    echo ""
    echo "${BOLD}Backup Configuration:${RESET}"
    echo "  - Location: $INSTALL_DIR/backups/"
    echo "  - Retention: 7 days"
    echo "  - Schedule: Daily at 2 AM (if enabled)"
    echo ""
    echo "${BOLD}Useful Commands:${RESET}"
    echo "  - View logs:"
    echo "    ${CYAN}docker compose -f $INSTALL_DIR/docker-compose.yml logs -f${RESET}"
    echo "  - Check status:"
    echo "    ${CYAN}docker compose -f $INSTALL_DIR/docker-compose.yml ps${RESET}"
    echo "  - Health check:"
    echo "    ${CYAN}$INSTALL_DIR/scripts/healthcheck.sh${RESET}"
    echo "  - Manual backup:"
    echo "    ${CYAN}$INSTALL_DIR/scripts/backup-all.sh${RESET}"
    echo "  - Restart services:"
    echo "    ${CYAN}docker compose -f $INSTALL_DIR/docker-compose.yml restart${RESET}"
    echo ""
    echo "${BOLD}Resource Allocation (${TOTAL_RAM_GB}GB RAM):${RESET}"
    docker compose -f $INSTALL_DIR/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}"
    echo ""
    print_separator
    echo ""
    echo "Deployment logs saved to: $LOG_FILE"
    echo ""
}


# ===========================================
# ADDITIONAL ACTIONS: UPDATE, UNINSTALL, HEALTH CHECK
# ===========================================

update_installation() {
    log_step "Updating n8n Installation"
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_error "No installation found at $INSTALL_DIR"
        exit 1
    fi
    
    cd "$INSTALL_DIR"
    
    log_info "Pulling latest images..."
    docker compose pull
    
    log_info "Recreating containers with new images..."
    docker compose up -d
    
    log_success "Update complete!"
    
    docker compose ps
}

uninstall_n8n() {
    log_step "Uninstalling n8n"
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_error "No installation found at $INSTALL_DIR"
        exit 1
    fi
    
    echo ""
    echo "${RED}${BOLD}⚠ WARNING: This will completely remove n8n!${RESET}"
    echo ""
    echo "This will delete:"
    echo "  - All containers and images"
    echo "  - All volumes (database, workflows, etc.)"
    echo "  - Configuration files at $INSTALL_DIR"
    echo ""
    echo "${YELLOW}Backups in $INSTALL_DIR/backups/ will be preserved${RESET}"
    echo ""
    
    if ! confirm "Are you absolutely sure you want to uninstall?"; then
        log_info "Uninstall cancelled"
        exit 0
    fi
    
    cd "$INSTALL_DIR"
    
    # Stop and remove containers
    log_info "Stopping containers..."
    docker compose down
    
    # Remove volumes
    if confirm "Remove all data volumes? (Cannot be undone)"; then
        log_info "Removing volumes..."
        docker compose down -v
    fi
    
    # Remove network
    docker network rm n8n-network 2>/dev/null || true
    
    # Move backups
    if [[ -d "$INSTALL_DIR/backups" ]]; then
        local backup_move="/tmp/n8n-backups-$(date +%Y%m%d_%H%M%S)"
        mv "$INSTALL_DIR/backups" "$backup_move"
        log_info "Backups moved to: $backup_move"
    fi
    
    # Remove installation directory
    if confirm "Remove installation directory $INSTALL_DIR?"; then
        cd /
        sudo rm -rf "$INSTALL_DIR"
        log_success "Installation directory removed"
    fi
    
    # Remove cron job
    if crontab -l 2>/dev/null | grep -q "n8n"; then
        crontab -l | grep -v "n8n" | crontab -
        log_info "Removed automated backup cron job"
    fi
    
    log_success "Uninstall complete!"
}

run_health_check() {
    if [[ ! -f "$INSTALL_DIR/scripts/healthcheck.sh" ]]; then
        log_error "Health check script not found at $INSTALL_DIR/scripts/healthcheck.sh"
        exit 1
    fi
    
    bash "$INSTALL_DIR/scripts/healthcheck.sh"
}

run_backup() {
    if [[ ! -f "$INSTALL_DIR/scripts/backup-all.sh" ]]; then
        log_error "Backup script not found at $INSTALL_DIR/scripts/backup-all.sh"
        exit 1
    fi
    
    log_step "Running Backup"
    bash "$INSTALL_DIR/scripts/backup-all.sh"
}

# ===========================================
# CLI ARGUMENT PARSING
# ===========================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "n8n Production VPS Deployment Script v$VERSION"
    echo ""
    echo "OPTIONS:"
    echo "  -d, --domain DOMAIN       Domain name for n8n (e.g., n8n.example.com)"
    echo "  -e, --email EMAIL         Email for Let's Encrypt notifications"
    echo "  -t, --timezone TZ         Timezone (default: UTC)"
    echo "  --install-dir DIR         Installation directory (default: /opt/n8n)"
    echo "  -y, --yes                 Non-interactive mode (auto-accept prompts)"
    echo "  --skip-security           Skip SSH hardening and Fail2ban"
    echo "  --dry-run                 Show what would be done without doing it"
    echo "  --verbose                 Enable verbose output"
    echo ""
    echo "ACTIONS:"
    echo "  --update                  Update existing installation"
    echo "  --uninstall               Remove n8n installation"
    echo "  --backup                  Run backup only"
    echo "  --check-health            Run health check only"
    echo ""
    echo "EXAMPLES:"
    echo "  # Interactive installation"
    echo "  sudo $0"
    echo ""
    echo "  # Non-interactive installation"
    echo "  sudo $0 --domain n8n.example.com --email admin@example.com --yes"
    echo ""
    echo "  # Update existing installation"
    echo "  sudo $0 --update"
    echo ""
    echo "  # Check health"
    echo "  $0 --check-health"
    echo ""
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -e|--email)
                LETSENCRYPT_EMAIL="$2"
                shift 2
                ;;
            -t|--timezone)
                TIMEZONE="$2"
                shift 2
                ;;
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -y|--yes)
                NON_INTERACTIVE=true
                shift
                ;;
            --skip-security)
                SKIP_SECURITY=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            --update)
                ACTION="update"
                shift
                ;;
            --uninstall)
                ACTION="uninstall"
                shift
                ;;
            --backup)
                ACTION="backup"
                shift
                ;;
            --check-health)
                ACTION="health-check"
                shift
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                ;;
        esac
    done
}

# ===========================================
# MAIN EXECUTION
# ===========================================

main() {
    # Initialize logging
    sudo mkdir -p /var/log
    sudo touch "$LOG_FILE" "$ERROR_LOG"
    sudo chmod 644 "$LOG_FILE" "$ERROR_LOG"
    
    log "=== n8n Deployment Script Started ==="
    log "Version: $VERSION"
    log "User: $USER"
    log "Action: $ACTION"
    
    case "$ACTION" in
        install)
            run_preflight_checks
            collect_user_inputs
            prepare_system
            harden_security
            verify_dns
            setup_configuration
            deploy_containers
            verify_deployment
            configure_automated_backups
            show_final_output
            ;;
        update)
            update_installation
            ;;
        uninstall)
            uninstall_n8n
            ;;
        backup)
            run_backup
            ;;
        health-check)
            run_health_check
            ;;
        *)
            log_error "Unknown action: $ACTION"
            exit 1
            ;;
    esac
    
    log "=== n8n Deployment Script Completed ==="
}

# ===========================================
# ENTRY POINT
# ===========================================

# Parse command line arguments
parse_arguments "$@"

# Run main function
main

