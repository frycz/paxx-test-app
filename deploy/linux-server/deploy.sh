#!/bin/bash
# Blue-green deployment script for paxx-test-app
# Usage: ./deploy.sh [version]
#        ./deploy.sh v1.0.0    # Deploy specific version
#        ./deploy.sh           # Deploy :latest
#
# This script:
#   1. Pulls the new image
#   2. Starts a new container (green) alongside the old one (blue)
#   3. Waits for the new container to be healthy
#   4. Traefik automatically routes traffic to the healthy container
#   5. Stops and removes the old container

set -e


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Configuration
VERSION=${1:-latest}
IMAGE_BASE=${IMAGE:-ghcr.io/your-username/paxx-test-app}
IMAGE="${IMAGE_BASE%:*}:${VERSION}"  # Replace any existing tag with VERSION
APP_NAME="paxx-test-app"
HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-60}  # seconds to wait for health check
DRAIN_TIMEOUT=${DRAIN_TIMEOUT:-30}    # seconds for graceful shutdown

log_info "Deploying $IMAGE"

# 1. Pull new image
log_info "Pulling image..."
if ! docker pull "$IMAGE"; then
    log_error "Failed to pull image: $IMAGE"
    exit 1
fi

# 2. Determine current and new slots
CURRENT_CONTAINER=$(docker ps --filter "name=${APP_NAME}-blue" --filter "name=${APP_NAME}-green" --format "{{.Names}}" | head -1)

if [[ "$CURRENT_CONTAINER" == *"blue"* ]]; then
    NEW_SLOT="green"
    OLD_SLOT="blue"
else
    NEW_SLOT="blue"
    OLD_SLOT="green"
fi

NEW_CONTAINER="${APP_NAME}-${NEW_SLOT}"
OLD_CONTAINER="${APP_NAME}-${OLD_SLOT}"

log_info "Current: ${CURRENT_CONTAINER:-none}, deploying to: $NEW_CONTAINER"

# 3. Stop any existing container with the new slot name (cleanup from failed deploy)
if docker inspect "$NEW_CONTAINER" &>/dev/null; then
    log_warn "Removing existing $NEW_CONTAINER (leftover from previous deploy)"
    docker stop "$NEW_CONTAINER" 2>/dev/null || true
    docker rm -f "$NEW_CONTAINER" 2>/dev/null || true

    # Verify container is actually removed
    if docker inspect "$NEW_CONTAINER" &>/dev/null; then
        log_error "Failed to remove existing container $NEW_CONTAINER"
        log_error "Please remove it manually: docker rm -f $NEW_CONTAINER"
        exit 1
    fi
fi

# 4. Start new container
log_info "Starting $NEW_CONTAINER..."

# Read database URL from environment or construct it
DB_URL=${DATABASE_URL:-postgresql+asyncpg://postgres:${POSTGRES_PASSWORD:-postgres}@db:5432/paxx_test_app}

docker run -d \
    --name "$NEW_CONTAINER" \
    --network traefik-public \
    --restart unless-stopped \
    -e "DATABASE_URL=$DB_URL" \
    -e "APP_ENV=${APP_ENV:-production}" \
    --label "traefik.enable=true" \
    --label "traefik.http.routers.${NEW_CONTAINER}.rule=PathPrefix(\`/\`)" \
    --label "traefik.http.routers.${NEW_CONTAINER}.entrypoints=web" \
    --label "traefik.http.routers.${NEW_CONTAINER}-secure.rule=PathPrefix(\`/\`)" \
    --label "traefik.http.routers.${NEW_CONTAINER}-secure.entrypoints=websecure" \
    --label "traefik.http.routers.${NEW_CONTAINER}-secure.tls=true" \
    --label "traefik.http.services.${NEW_CONTAINER}.loadbalancer.server.port=8000" \
    --label "traefik.http.services.${NEW_CONTAINER}.loadbalancer.healthcheck.path=/health" \
    --label "traefik.http.services.${NEW_CONTAINER}.loadbalancer.healthcheck.interval=5s" \
    --label "traefik.http.services.${NEW_CONTAINER}.loadbalancer.healthcheck.timeout=3s" \
    "$IMAGE"

# Also connect to backend network for database access
docker network connect backend "$NEW_CONTAINER" 2>/dev/null || true

# 5. Wait for health check (uses Docker's built-in HEALTHCHECK from Dockerfile)
log_info "Waiting for $NEW_CONTAINER to be healthy (timeout: ${HEALTH_TIMEOUT}s)..."

SECONDS=0
while true; do
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$NEW_CONTAINER" 2>/dev/null || echo "unknown")

    if [ "$HEALTH" = "healthy" ]; then
        break
    fi

    if [ "$HEALTH" = "unhealthy" ] || [ $SECONDS -ge $HEALTH_TIMEOUT ]; then
        log_error "Health check failed (status: $HEALTH)"
        log_error "Container logs:"
        docker logs --tail 20 "$NEW_CONTAINER" 2>&1 || true
        log_error "Removing failed container..."
        docker stop "$NEW_CONTAINER" 2>/dev/null || true
        docker rm "$NEW_CONTAINER" 2>/dev/null || true
        exit 1
    fi

    echo -n "."
    sleep 2
done
echo ""

log_info "$NEW_CONTAINER is healthy!"

# 6. Graceful shutdown of old container (if exists)
if [ -n "$CURRENT_CONTAINER" ] && docker ps --format "{{.Names}}" | grep -q "^${OLD_CONTAINER}$"; then
    log_info "Stopping $OLD_CONTAINER (graceful drain: ${DRAIN_TIMEOUT}s)..."
    docker stop --time "$DRAIN_TIMEOUT" "$OLD_CONTAINER" 2>/dev/null || true
    docker rm "$OLD_CONTAINER" 2>/dev/null || true
    log_info "$OLD_CONTAINER removed"
fi

# Success
echo ""
echo "=========================================="
log_info "Deployment complete!"
echo "=========================================="
echo "  Image:     $IMAGE"
echo "  Container: $NEW_CONTAINER"
echo "  Status:    $(docker inspect --format='{{.State.Status}}' "$NEW_CONTAINER")"
echo ""

