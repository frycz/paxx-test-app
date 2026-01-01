#!/bin/bash
# Server setup script for paxx-test-app
# Idempotent - safe to run multiple times
# Supports: Debian, Ubuntu, Raspbian

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Detect distro
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID  # debian, ubuntu, raspbian
    VERSION=$VERSION_ID
else
    log_error "Cannot detect distribution. /etc/os-release not found."
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)  # aarch64, x86_64
log_info "Detected: $DISTRO $VERSION on $ARCH"

case $DISTRO in
    debian|ubuntu|raspbian)
        log_info "Supported distribution detected"
        ;;
    *)
        log_warn "Untested distribution: $DISTRO (proceeding anyway)"
        ;;
esac

# Get the user who invoked sudo (for adding to docker group)
SUDO_USER=${SUDO_USER:-$USER}
if [ "$SUDO_USER" = "root" ]; then
    log_warn "Running as root user - consider creating a non-root user for security"
fi

# 1. Update system packages
log_info "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# 2. Install prerequisites
log_info "Installing prerequisites..."
apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    ufw \
    jq

# 3. Install Docker (if not already installed)
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
    log_info "Docker already installed (version $DOCKER_VERSION)"
else
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    log_info "Docker installed successfully"
fi

# 4. Configure Docker for non-root user
if [ "$SUDO_USER" != "root" ]; then
    if groups "$SUDO_USER" | grep -q docker; then
        log_info "User $SUDO_USER already in docker group"
    else
        log_info "Adding $SUDO_USER to docker group..."
        usermod -aG docker "$SUDO_USER"
        log_warn "Log out and back in for docker group to take effect"
    fi
fi

# 5. Ensure Docker is running and enabled
log_info "Enabling Docker service..."
systemctl enable docker
systemctl start docker

# 6. Configure firewall (ufw)
log_info "Configuring firewall..."
# Allow SSH (important - don't lock yourself out!)
ufw allow ssh
# Allow HTTP/HTTPS for Traefik
ufw allow 80/tcp
ufw allow 443/tcp
# Enable firewall (non-interactive)
if ufw status | grep -q "Status: inactive"; then
    log_info "Enabling firewall..."
    echo "y" | ufw enable
else
    log_info "Firewall already enabled"
fi
ufw status

# 7. Create app directory structure
APP_DIR="/opt/paxx-test-app"
log_info "Creating app directory: $APP_DIR"
mkdir -p "$APP_DIR"
if [ "$SUDO_USER" != "root" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$APP_DIR"
fi

# 8. Create Docker network for Traefik (if not exists)
if docker network ls | grep -q traefik-public; then
    log_info "Docker network 'traefik-public' already exists"
else
    log_info "Creating Docker network 'traefik-public'..."
    docker network create traefik-public
fi

# 9. Create log directory for deploy scripts
LOG_DIR="/var/log/paxx-test-app"
mkdir -p "$LOG_DIR"
if [ "$SUDO_USER" != "root" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$LOG_DIR"
fi

# 10. Setup cron job for auto-deploy (checks for new images every 5 minutes)
CRON_FILE="/etc/cron.d/paxx-test-app-deploy"
CRON_USER="${SUDO_USER:-root}"
log_info "Setting up auto-deploy cron job..."
cat > "$CRON_FILE" << EOF
# Auto-deploy paxx-test-app - checks for new Docker images every 5 minutes
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin

*/5 * * * * $CRON_USER $APP_DIR/deploy-if-changed.sh >> $LOG_DIR/deploy.log 2>&1
EOF
chmod 644 "$CRON_FILE"
log_info "Cron job created: $CRON_FILE"

# Summary
echo ""
echo "=========================================="
log_info "Server setup complete!"
echo "=========================================="
echo ""
echo "System info:"
echo "  Distribution: $DISTRO $VERSION"
echo "  Architecture: $ARCH"
echo "  Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
echo ""
echo "Directories created:"
echo "  App directory: $APP_DIR"
echo "  Log directory: $LOG_DIR"
echo ""
echo "Auto-deploy:"
echo "  Cron job: $CRON_FILE (every 5 minutes)"
echo "  Log file: $LOG_DIR/deploy.log"
echo ""
echo "Next steps:"
echo "  1. Copy your deploy files to $APP_DIR"
echo "  2. Configure .env file"
echo "  3. Run: docker compose up -d"
echo "  4. Run: ./deploy.sh to deploy your app"
echo ""
if [ "$SUDO_USER" != "root" ]; then
    echo "Note: Log out and back in for docker group membership to take effect"
fi
