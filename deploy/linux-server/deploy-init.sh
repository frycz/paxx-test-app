#!/bin/bash
# Initialize deployment on a remote server
# Usage: ./deploy/linux-server/deploy-init.sh user@server

set -e

if [ -z "$1" ]; then
    echo "Usage: ./deploy/linux-server/deploy-init.sh user@server"
    echo "Example: ./deploy/linux-server/deploy-init.sh admin@192.168.1.100"
    exit 1
fi

SERVER=$1
APP_DIR="/opt/paxx-test-app"

if [ ! -f "deploy/linux-server/.env" ]; then
    echo "Error: deploy/linux-server/.env not found"
    echo "Create it from deploy/linux-server/.env.example before deploying"
    exit 1
fi

if [ ! -f "deploy/linux-server/server-setup.sh" ]; then
    echo "Error: deploy/linux-server/server-setup.sh not found"
    exit 1
fi

echo "Deploying to $SERVER..."

# Copy deploy files
echo "Copying deploy files..."
ssh "$SERVER" "sudo mkdir -p $APP_DIR $APP_DIR/certs && sudo chown \$(whoami):\$(whoami) $APP_DIR $APP_DIR/certs"
scp deploy/linux-server/.env \
    deploy/linux-server/server-setup.sh \
    deploy/linux-server/deploy.sh \
    deploy/linux-server/deploy-if-changed.sh \
    deploy/linux-server/deploy-purge.sh \
    deploy/linux-server/docker-compose.yml \
    deploy/linux-server/traefik-dynamic.yml \
    "$SERVER:$APP_DIR/"

# Copy TLS certificates if they exist
CERTS_COPIED=false
if [ -f "deploy/linux-server/certs/cert.pem" ] && [ -f "deploy/linux-server/certs/key.pem" ]; then
    echo "Copying TLS certificates..."
    scp deploy/linux-server/certs/cert.pem deploy/linux-server/certs/key.pem "$SERVER:$APP_DIR/certs/"
    CERTS_COPIED=true
fi

# Make scripts executable
ssh "$SERVER" "chmod +x $APP_DIR/server-setup.sh $APP_DIR/deploy.sh $APP_DIR/deploy-if-changed.sh $APP_DIR/deploy-purge.sh"

# Run setup
echo "Running server setup..."
ssh "$SERVER" "cd $APP_DIR && sudo ./server-setup.sh"

# Start infrastructure (Traefik + PostgreSQL)
echo ""
echo "Starting infrastructure (Traefik + PostgreSQL)..."
ssh "$SERVER" "cd $APP_DIR && docker compose up -d traefik db"

# Check if app image exists and deploy if available
echo ""
echo "Checking if app image exists..."
IMAGE=$(ssh "$SERVER" "cd $APP_DIR && source .env && echo \$IMAGE")
if ssh "$SERVER" "docker manifest inspect $IMAGE > /dev/null 2>&1"; then
    echo "Image found: $IMAGE"
    echo "Deploying app..."
    ssh "$SERVER" "cd $APP_DIR && ./deploy.sh"
    APP_DEPLOYED=true
else
    echo "Image not found: $IMAGE"
    echo "App will be deployed automatically when image is pushed."
    APP_DEPLOYED=false
fi

echo ""
echo "=========================================="
echo "Server initialization complete!"
echo "=========================================="
echo ""
echo "Infrastructure running:"
echo "  - Traefik (load balancer) on ports 80 and 443"
echo "  - PostgreSQL database"
echo "  - Auto-deploy cron job (every 5 minutes)"
if [ "$APP_DEPLOYED" = true ]; then
    echo "  - App deployed and running"
fi
echo ""

if [ "$CERTS_COPIED" = false ]; then
    echo "TLS Certificates:"
    echo "  No certificates found. For trusted HTTPS, create certs with mkcert:"
    echo ""
    echo "    brew install mkcert && mkcert -install"
    echo "    mkcert -cert-file deploy/linux-server/certs/cert.pem -key-file deploy/linux-server/certs/key.pem <SERVER_IP>"
    echo ""
    echo "  Then re-run deploy-init.sh to copy them."
    echo ""
fi

if [ "$APP_DEPLOYED" = false ]; then
    echo "Next steps:"
    echo "  1. Build and push your Docker image (git tag + push)"
    echo "  2. Wait for auto-deploy, or run manually: ssh $SERVER \"cd $APP_DIR && ./deploy.sh\""
fi
