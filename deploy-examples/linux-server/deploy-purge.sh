#!/bin/bash
# Complete purge script for paxx-test-app
# Removes ALL deployment artifacts and system changes from the server
#
# Usage: sudo ./deploy-purge.sh
#
# This script will:
#   - Stop and remove all containers (traefik, db, app)
#   - Delete Docker volumes (DATA LOSS)
#   - Remove Docker networks and images
#   - Delete app and log directories
#   - Remove cron job and lock files
#   - Remove firewall rules (80/tcp, 443/tcp)
#   - Remove user from docker group
#   - Uninstall Docker
#   - Remove installed packages (jq, curl)

set -e


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "\n${GREEN}${BOLD}=== $1 ===${NC}\n"; }
log_comment() { echo -e "${CYAN}$1${NC}"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# ============================================================================
# INTRODUCTION
# ============================================================================
log_header "DEPLOY PURGE"
echo "This script will completely remove all deployment artifacts from this server."
echo -e "${BOLD}Nothing will be deleted until you confirm by typing PURGE.${NC}"
echo ""
echo "What will happen:"
echo "  1. Scan the system for deployment artifacts"
echo "  2. Show you what was found and what will be removed"
echo "  3. Ask for confirmation"
echo "  4. Execute the purge"
echo ""
read -p "Start scanning? (y/N): " -r REPLY
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Configuration
APP_NAME="paxx-test-app"
APP_DIR="/opt/$APP_NAME"
LOG_DIR="/var/log/$APP_NAME"
CRON_FILE="/etc/cron.d/${APP_NAME}-deploy"
LOCK_FILE="/tmp/${APP_NAME}-deploy.lock"
COMPOSE_PROJECT="${APP_NAME//-/_}"  # docker compose uses underscores

# Get the user who invoked sudo (for docker group removal)
SUDO_USER=${SUDO_USER:-$USER}

# ============================================================================
# RECONNAISSANCE
# ============================================================================
log_header "RECONNAISSANCE"
log_info "Scanning for deployment artifacts..."

# Arrays to track findings
declare -a CONTAINERS_FOUND=()
declare -a NETWORKS_FOUND=()
declare -a VOLUMES_FOUND=()
declare -a IMAGES_FOUND=()
declare -a DIRS_FOUND=()
declare -a FILES_FOUND=()
declare -a FIREWALL_FOUND=()
declare -a SYSTEM_FOUND=()

# Check containers (compose adds -1 suffix, blue/green are named explicitly)
for container in "${APP_NAME}-traefik-1" "${APP_NAME}-db-1" "${APP_NAME}-blue" "${APP_NAME}-green"; do
    if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
        CONTAINERS_FOUND+=("$container")
    fi
done

# Check networks
for network in "traefik-public" "backend"; do
    if docker network ls --format "{{.Name}}" 2>/dev/null | grep -q "^${network}$"; then
        NETWORKS_FOUND+=("$network")
    fi
done

# Check volumes - find all volumes matching app name prefix
while IFS= read -r volume; do
    [ -n "$volume" ] && VOLUMES_FOUND+=("$volume")
done < <(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "^(${APP_NAME}|${COMPOSE_PROJECT})_" || true)

# Also check for standalone postgres_data volume
if docker volume ls --format "{{.Name}}" 2>/dev/null | grep -q "^postgres_data$"; then
    VOLUMES_FOUND+=("postgres_data")
fi

# Check for infrastructure images
for image in "traefik:latest" "postgres:16-alpine"; do
    if docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "^${image}$"; then
        IMAGES_FOUND+=("$image")
    fi
done

# Check for app images
APP_IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -i "$APP_NAME" || true)
if [ -n "$APP_IMAGES" ]; then
    while IFS= read -r img; do
        IMAGES_FOUND+=("$img")
    done <<< "$APP_IMAGES"
fi

# Check directories
[ -d "$APP_DIR" ] && DIRS_FOUND+=("$APP_DIR")
[ -d "$LOG_DIR" ] && DIRS_FOUND+=("$LOG_DIR")

# Check files
[ -f "$CRON_FILE" ] && FILES_FOUND+=("$CRON_FILE")
[ -f "$LOCK_FILE" ] && FILES_FOUND+=("$LOCK_FILE")

# Check firewall rules
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    ufw status | grep -q "80/tcp.*ALLOW" && FIREWALL_FOUND+=("80/tcp")
    ufw status | grep -q "443/tcp.*ALLOW" && FIREWALL_FOUND+=("443/tcp")
fi

# Check system-level changes
if [ "$SUDO_USER" != "root" ] && groups "$SUDO_USER" 2>/dev/null | grep -q docker; then
    SYSTEM_FOUND+=("docker-group:$SUDO_USER")
fi

if command -v docker &> /dev/null; then
    SYSTEM_FOUND+=("docker:installed")
fi

for pkg in jq curl; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        SYSTEM_FOUND+=("package:$pkg")
    fi
done

# ============================================================================
# REPORT
# ============================================================================
log_header "FINDINGS REPORT"

# Count total items
TOTAL_ITEMS=0
((TOTAL_ITEMS += ${#CONTAINERS_FOUND[@]}))
((TOTAL_ITEMS += ${#NETWORKS_FOUND[@]}))
((TOTAL_ITEMS += ${#VOLUMES_FOUND[@]}))
((TOTAL_ITEMS += ${#IMAGES_FOUND[@]}))
((TOTAL_ITEMS += ${#DIRS_FOUND[@]}))
((TOTAL_ITEMS += ${#FILES_FOUND[@]}))
((TOTAL_ITEMS += ${#FIREWALL_FOUND[@]}))
((TOTAL_ITEMS += ${#SYSTEM_FOUND[@]}))

if [ $TOTAL_ITEMS -eq 0 ]; then
    log_info "No deployment artifacts found. Nothing to purge."
    exit 0
fi

# DESTRUCTIVE items (data loss)
if [ ${#VOLUMES_FOUND[@]} -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}DESTRUCTIVE (data loss):${NC}"
    for vol in "${VOLUMES_FOUND[@]}"; do
        echo -e "  ${YELLOW}${BOLD}* Docker volume: $vol${NC}"
        SIZE=$(docker system df -v 2>/dev/null | grep "^$vol" | awk '{print $3}' || echo "unknown")
        # Determine volume type based on name
        if [[ "$vol" == *"postgres"* ]]; then
            VOL_DESC="PostgreSQL database"
        elif [[ "$vol" == *"certs"* ]] || [[ "$vol" == *"tls"* ]]; then
            VOL_DESC="TLS certificates"
        else
            VOL_DESC="data"
        fi
        echo -e "    ${YELLOW}${BOLD}($VOL_DESC - size: $SIZE)${NC}"
    done
    echo ""
fi

# DEPLOYMENT items
DEPLOYMENT_COUNT=$((${#CONTAINERS_FOUND[@]} + ${#NETWORKS_FOUND[@]} + ${#IMAGES_FOUND[@]} + ${#DIRS_FOUND[@]} + ${#FILES_FOUND[@]} + ${#FIREWALL_FOUND[@]}))
if [ $DEPLOYMENT_COUNT -gt 0 ]; then
    echo -e "${WHITE}${BOLD}DEPLOYMENT:${NC}"

    for container in "${CONTAINERS_FOUND[@]}"; do
        STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        echo -e "  ${WHITE}* Container: $container ($STATUS)${NC}"
    done

    for network in "${NETWORKS_FOUND[@]}"; do
        echo -e "  ${WHITE}* Network: $network${NC}"
    done

    for image in "${IMAGES_FOUND[@]}"; do
        echo -e "  ${WHITE}* Image: $image${NC}"
    done

    for dir in "${DIRS_FOUND[@]}"; do
        if [ -d "$dir" ]; then
            SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown")
            echo -e "  ${WHITE}* Directory: $dir ($SIZE)${NC}"
        fi
    done

    for file in "${FILES_FOUND[@]}"; do
        echo -e "  ${WHITE}* File: $file${NC}"
    done

    for rule in "${FIREWALL_FOUND[@]}"; do
        echo -e "  ${WHITE}* Firewall rule: $rule ALLOW${NC}"
    done
    echo ""
fi

# SYSTEM items
if [ ${#SYSTEM_FOUND[@]} -gt 0 ]; then
    echo -e "${WHITE}${BOLD}SYSTEM:${NC}"
    for item in "${SYSTEM_FOUND[@]}"; do
        case "$item" in
            docker-group:*)
                USER_NAME="${item#docker-group:}"
                echo -e "  ${WHITE}* Docker group membership: $USER_NAME${NC}"
                ;;
            docker:*)
                DOCKER_VERSION=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "unknown")
                echo -e "  ${WHITE}* Docker: $DOCKER_VERSION${NC}"
                ;;
            package:*)
                PKG="${item#package:}"
                echo -e "  ${WHITE}* Package: $PKG${NC}"
                ;;
        esac
    done
    echo ""
fi

# ============================================================================
# SHOW COMMANDS
# ============================================================================
log_header "ACTIONS TO BE PERFORMED"

echo "The following commands will be executed:"
echo ""

if [ ${#CONTAINERS_FOUND[@]} -gt 0 ]; then
    log_comment "# Stop and remove containers"
    for container in "${CONTAINERS_FOUND[@]}"; do
        echo "docker stop $container && docker rm $container"
    done
    echo ""
fi

if [ -f "$APP_DIR/docker-compose.yml" ] || [ -f "$APP_DIR/docker-compose.yaml" ]; then
    log_comment "# Docker compose down"
    echo "cd $APP_DIR && docker compose down --remove-orphans"
    echo ""
fi

if [ ${#NETWORKS_FOUND[@]} -gt 0 ]; then
    log_comment "# Remove networks"
    for network in "${NETWORKS_FOUND[@]}"; do
        echo "docker network rm $network"
    done
    echo ""
fi

if [ ${#VOLUMES_FOUND[@]} -gt 0 ]; then
    log_comment "# Remove volumes (DATA LOSS)"
    for vol in "${VOLUMES_FOUND[@]}"; do
        echo "docker volume rm $vol"
    done
    echo ""
fi

if [ ${#IMAGES_FOUND[@]} -gt 0 ]; then
    log_comment "# Remove images"
    for image in "${IMAGES_FOUND[@]}"; do
        echo "docker rmi $image"
    done
    echo ""
fi

if [ ${#DIRS_FOUND[@]} -gt 0 ]; then
    log_comment "# Remove directories"
    for dir in "${DIRS_FOUND[@]}"; do
        echo "rm -rf $dir"
    done
    echo ""
fi

if [ ${#FILES_FOUND[@]} -gt 0 ]; then
    log_comment "# Remove files"
    for file in "${FILES_FOUND[@]}"; do
        echo "rm -f $file"
    done
    echo ""
fi

if [ ${#FIREWALL_FOUND[@]} -gt 0 ]; then
    log_comment "# Remove firewall rules"
    for rule in "${FIREWALL_FOUND[@]}"; do
        echo "ufw delete allow $rule"
    done
    echo ""
fi

# System-level commands
HAS_DOCKER_GROUP=false
HAS_DOCKER=false
HAS_PACKAGES=false
PACKAGES_TO_REMOVE=()

for item in "${SYSTEM_FOUND[@]}"; do
    case "$item" in
        docker-group:*) HAS_DOCKER_GROUP=true ;;
        docker:*) HAS_DOCKER=true ;;
        package:*)
            HAS_PACKAGES=true
            PACKAGES_TO_REMOVE+=("${item#package:}")
            ;;
    esac
done

if [ "$HAS_DOCKER_GROUP" = true ] && [ "$SUDO_USER" != "root" ]; then
    log_comment "# Remove user from docker group"
    echo "gpasswd -d $SUDO_USER docker"
    echo ""
fi

if [ "$HAS_DOCKER" = true ]; then
    log_comment "# Stop and disable Docker service"
    echo "systemctl stop docker docker.socket containerd"
    echo "systemctl disable docker docker.socket containerd"
    echo ""
    log_comment "# Uninstall Docker"
    echo "apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    echo "rm -rf /var/lib/docker /var/lib/containerd"
    echo ""
    log_comment "# Remove Docker apt repository"
    echo "rm -f /etc/apt/sources.list.d/docker.list"
    echo "rm -f /etc/apt/keyrings/docker.gpg /usr/share/keyrings/docker-archive-keyring.gpg"
    echo ""
fi

if [ "$HAS_PACKAGES" = true ]; then
    log_comment "# Remove packages"
    echo "apt-get purge -y ${PACKAGES_TO_REMOVE[*]}"
    echo "apt-get autoremove -y"
    echo ""
fi

# ============================================================================
# CONFIRMATION
# ============================================================================
log_header "CONFIRMATION REQUIRED"

if [ ${#VOLUMES_FOUND[@]} -gt 0 ]; then
    echo -e "${BOLD}WARNING: This will permanently delete all data including the PostgreSQL database!${NC}"
else
    echo -e "${BOLD}WARNING: This will remove all deployment artifacts and Docker from this server.${NC}"
fi
echo ""
echo -e "To confirm, type ${BOLD}PURGE${NC} (all caps):"
read -r CONFIRM

if [ "$CONFIRM" != "PURGE" ]; then
    log_error "Confirmation failed. Aborting."
    exit 1
fi

# ============================================================================
# EXECUTION
# ============================================================================
log_header "EXECUTING PURGE"

ERRORS=0

# 1. Stop and remove containers
if [ ${#CONTAINERS_FOUND[@]} -gt 0 ]; then
    log_info "Stopping and removing containers..."
    for container in "${CONTAINERS_FOUND[@]}"; do
        if docker stop "$container" 2>/dev/null && docker rm "$container" 2>/dev/null; then
            log_info "  Removed: $container"
        else
            log_warn "  Failed to remove: $container"
            ((ERRORS++))
        fi
    done
fi

# 2. Docker compose down (cleanup any orphans)
if [ -f "$APP_DIR/docker-compose.yml" ] || [ -f "$APP_DIR/docker-compose.yaml" ]; then
    log_info "Running docker compose down..."
    cd "$APP_DIR" && docker compose down --remove-orphans 2>/dev/null || true
fi

# 3. Remove networks
if [ ${#NETWORKS_FOUND[@]} -gt 0 ]; then
    log_info "Removing networks..."
    for network in "${NETWORKS_FOUND[@]}"; do
        if docker network rm "$network" 2>/dev/null; then
            log_info "  Removed: $network"
        else
            log_warn "  Failed to remove: $network (may be in use)"
            ((ERRORS++))
        fi
    done
fi

# 4. Remove volumes
if [ ${#VOLUMES_FOUND[@]} -gt 0 ]; then
    log_info "Removing volumes..."
    for vol in "${VOLUMES_FOUND[@]}"; do
        if docker volume rm "$vol" 2>/dev/null; then
            log_info "  Removed: $vol"
        else
            log_warn "  Failed to remove: $vol"
            ((ERRORS++))
        fi
    done
fi

# 5. Remove images
if [ ${#IMAGES_FOUND[@]} -gt 0 ]; then
    log_info "Removing images..."
    for image in "${IMAGES_FOUND[@]}"; do
        if docker rmi "$image" 2>/dev/null; then
            log_info "  Removed: $image"
        else
            log_warn "  Failed to remove: $image"
            ((ERRORS++))
        fi
    done
fi

# 6. Remove directories
if [ ${#DIRS_FOUND[@]} -gt 0 ]; then
    log_info "Removing directories..."
    for dir in "${DIRS_FOUND[@]}"; do
        if rm -rf "$dir" 2>/dev/null; then
            log_info "  Removed: $dir"
        else
            log_warn "  Failed to remove: $dir"
            ((ERRORS++))
        fi
    done
fi

# 7. Remove files
if [ ${#FILES_FOUND[@]} -gt 0 ]; then
    log_info "Removing files..."
    for file in "${FILES_FOUND[@]}"; do
        if rm -f "$file" 2>/dev/null; then
            log_info "  Removed: $file"
        else
            log_warn "  Failed to remove: $file"
            ((ERRORS++))
        fi
    done
fi

# 8. Remove firewall rules
if [ ${#FIREWALL_FOUND[@]} -gt 0 ]; then
    log_info "Removing firewall rules..."
    for rule in "${FIREWALL_FOUND[@]}"; do
        if ufw delete allow "$rule" 2>/dev/null; then
            log_info "  Removed: $rule"
        else
            log_warn "  Failed to remove: $rule"
            ((ERRORS++))
        fi
    done
fi

# 9. Remove user from docker group
if [ "$HAS_DOCKER_GROUP" = true ] && [ "$SUDO_USER" != "root" ]; then
    log_info "Removing $SUDO_USER from docker group..."
    if gpasswd -d "$SUDO_USER" docker 2>/dev/null; then
        log_info "  Removed $SUDO_USER from docker group"
    else
        log_warn "  Failed to remove $SUDO_USER from docker group"
        ((ERRORS++))
    fi
fi

# 10. Stop and uninstall Docker
if [ "$HAS_DOCKER" = true ]; then
    log_info "Stopping Docker services..."
    systemctl stop docker docker.socket containerd 2>/dev/null || true
    systemctl disable docker docker.socket containerd 2>/dev/null || true

    log_info "Uninstalling Docker..."
    if apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null; then
        log_info "  Docker packages removed"
    else
        log_warn "  Failed to remove some Docker packages"
        ((ERRORS++))
    fi

    log_info "Removing Docker data directories..."
    rm -rf /var/lib/docker /var/lib/containerd 2>/dev/null || true

    log_info "Removing Docker apt repository..."
    rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
    rm -f /etc/apt/keyrings/docker.gpg /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true
fi

# 11. Remove packages
if [ "$HAS_PACKAGES" = true ]; then
    log_info "Removing packages..."
    if apt-get purge -y "${PACKAGES_TO_REMOVE[@]}" 2>/dev/null; then
        log_info "  Packages removed: ${PACKAGES_TO_REMOVE[*]}"
    else
        log_warn "  Failed to remove some packages"
        ((ERRORS++))
    fi

    log_info "Running apt autoremove..."
    apt-get autoremove -y 2>/dev/null || true
fi

# ============================================================================
# SUMMARY
# ============================================================================
log_header "PURGE COMPLETE"

if [ $ERRORS -eq 0 ]; then
    log_info "All artifacts removed successfully!"
else
    log_warn "$ERRORS items could not be removed (see warnings above)"
fi

echo ""
echo "Removed:"
[ ${#CONTAINERS_FOUND[@]} -gt 0 ] && echo "  - ${#CONTAINERS_FOUND[@]} container(s)"
[ ${#NETWORKS_FOUND[@]} -gt 0 ] && echo "  - ${#NETWORKS_FOUND[@]} network(s)"
[ ${#VOLUMES_FOUND[@]} -gt 0 ] && echo "  - ${#VOLUMES_FOUND[@]} volume(s)"
[ ${#IMAGES_FOUND[@]} -gt 0 ] && echo "  - ${#IMAGES_FOUND[@]} image(s)"
[ ${#DIRS_FOUND[@]} -gt 0 ] && echo "  - ${#DIRS_FOUND[@]} directory(ies)"
[ ${#FILES_FOUND[@]} -gt 0 ] && echo "  - ${#FILES_FOUND[@]} file(s)"
[ ${#FIREWALL_FOUND[@]} -gt 0 ] && echo "  - ${#FIREWALL_FOUND[@]} firewall rule(s)"
[ "$HAS_DOCKER_GROUP" = true ] && echo "  - Docker group membership"
[ "$HAS_DOCKER" = true ] && echo "  - Docker"
[ "$HAS_PACKAGES" = true ] && echo "  - Packages: ${PACKAGES_TO_REMOVE[*]}"
echo ""

log_info "Server has been reset to pre-deployment state."

