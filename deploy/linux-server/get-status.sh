#!/bin/bash
# Get deployment status from a remote server (read-only)
# Usage: ./deploy/linux-server/get-status.sh [OPTIONS] user@server

set -euo pipefail

APP_NAME="paxx-test-app"
APP_DIR="/opt/paxx-test-app"

# Default values
FORMAT="text"
SERVER=""

show_help() {
    echo "Get deployment status for $APP_NAME (read-only)"
    echo ""
    echo "Usage: ./deploy/linux-server/get-status.sh [OPTIONS] user@server"
    echo ""
    echo "Arguments:"
    echo "  user@server       SSH connection string (e.g., admin@192.168.1.100)"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -f, --format FMT  Output format: text (default) or json"
    echo "  --format=FMT      Same as above"
    echo ""
    echo "Examples:"
    echo "  ./deploy/linux-server/get-status.sh admin@192.168.1.100"
    echo "  ./deploy/linux-server/get-status.sh --format=json admin@server"
    echo "  ./deploy/linux-server/get-status.sh -f json user@server | jq '.containers'"
    echo ""
    echo "The script connects via SSH and inspects:"
    echo "  - Container status (Traefik, database, app blue/green)"
    echo "  - Resource usage (CPU, memory, disk)"
    echo "  - TLS certificate expiry"
    echo "  - Auto-deploy cron job"
    echo "  - Recent deploy logs"
    echo "  - Health endpoint"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        --format=*)
            FORMAT="${1#*=}"
            shift
            ;;
        -*)
            echo "Error: Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            SERVER="$1"
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$SERVER" ]; then
    echo "Error: Missing server argument"
    echo ""
    show_help
    exit 1
fi

if [ "$FORMAT" != "text" ] && [ "$FORMAT" != "json" ]; then
    echo "Error: Invalid format '$FORMAT'. Use 'text' or 'json'"
    exit 1
fi

# Text format output
run_text_status() {
    echo "=========================================="
    echo "Deployment Status: $APP_NAME"
    echo "Server: $SERVER"
    echo "=========================================="
    echo ""

    ssh "$SERVER" bash << 'REMOTE_SCRIPT'
APP_DIR="/opt/paxx-test-app"
APP_NAME="paxx-test-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}--- $1 ---${NC}"
}

print_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Track overall deployment status
APP_DEPLOYED=false

# Check if app directory exists
print_header "Deployment Directory"
if [ -d "$APP_DIR" ]; then
    APP_DEPLOYED=true
    print_ok "App directory exists: $APP_DIR"
    ls -la "$APP_DIR" 2>/dev/null | head -15
else
    print_warn "App directory not found: $APP_DIR"
    echo "  App has not been deployed to this server yet."
fi
echo ""

# Load environment variables
if [ -f "$APP_DIR/.env" ]; then
    source "$APP_DIR/.env"
    print_ok "Environment file loaded"
    echo "  IMAGE: ${IMAGE:-not set}"
elif [ "$APP_DEPLOYED" = true ]; then
    print_warn "No .env file found"
else
    echo "  Skipped (app not deployed)"
fi
echo ""

# Container status
print_header "Container Status"
echo ""

# Find Traefik container
TRAEFIK_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "traefik" | head -1)
if [ -n "$TRAEFIK_CONTAINER" ]; then
    TRAEFIK_STATUS=$(docker inspect --format='{{.State.Status}}' "$TRAEFIK_CONTAINER" 2>/dev/null)
    print_ok "Traefik ($TRAEFIK_CONTAINER): $TRAEFIK_STATUS"
else
    print_error "Traefik: not running"
fi

# Find Database container
DB_CONTAINER=$(docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | grep -E "postgres" | awk '{print $1}' | head -1)
if [ -n "$DB_CONTAINER" ]; then
    DB_STATUS=$(docker inspect --format='{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null)
    print_ok "Database ($DB_CONTAINER): $DB_STATUS"
else
    print_error "Database: not running"
fi

# Check App containers (blue/green)
BLUE_CONTAINER="${APP_NAME}-blue"
GREEN_CONTAINER="${APP_NAME}-green"
ACTIVE_CONTAINER=""
BLUE_RUNNING=false
GREEN_RUNNING=false

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${BLUE_CONTAINER}$"; then
    BLUE_RUNNING=true
    BLUE_STATUS=$(docker inspect --format='{{.State.Status}}' "$BLUE_CONTAINER" 2>/dev/null)
    BLUE_HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' "$BLUE_CONTAINER" 2>/dev/null)
    BLUE_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$BLUE_CONTAINER" 2>/dev/null)
    print_ok "App (blue): $BLUE_STATUS (health: $BLUE_HEALTH) [active]"
    echo "    Image: $BLUE_IMAGE"
    ACTIVE_CONTAINER="$BLUE_CONTAINER"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${GREEN_CONTAINER}$"; then
    GREEN_RUNNING=true
    GREEN_STATUS=$(docker inspect --format='{{.State.Status}}' "$GREEN_CONTAINER" 2>/dev/null)
    GREEN_HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' "$GREEN_CONTAINER" 2>/dev/null)
    GREEN_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$GREEN_CONTAINER" 2>/dev/null)
    print_ok "App (green): $GREEN_STATUS (health: $GREEN_HEALTH) [active]"
    echo "    Image: $GREEN_IMAGE"
    ACTIVE_CONTAINER="$GREEN_CONTAINER"
fi

if [ "$BLUE_RUNNING" = false ] && [ "$GREEN_RUNNING" = false ]; then
    print_error "No app container is running (neither blue nor green)"
elif [ "$BLUE_RUNNING" = true ] && [ "$GREEN_RUNNING" = true ]; then
    print_warn "Both blue and green are running (transitional state during deploy)"
else
    if [ "$BLUE_RUNNING" = false ]; then
        echo -e "  App (blue): standby"
    fi
    if [ "$GREEN_RUNNING" = false ]; then
        echo -e "  App (green): standby"
    fi
fi
echo ""

# Container resource usage
print_header "Resource Usage"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null | grep -E "(NAME|traefik|${APP_NAME})" || echo "No containers running"
echo ""

# System resources
print_header "System Resources"
echo ""
echo "Disk usage:"
df -h / | tail -1 | awk '{print "  Used: " $3 " / " $2 " (" $5 " used)"}'
echo ""
echo "Memory:"
free -h | grep Mem | awk '{print "  Used: " $3 " / " $2}'
echo ""
echo "Docker disk usage:"
docker system df 2>/dev/null | head -4
echo ""

# Network ports
print_header "Network Ports"
echo "Listening ports:"
ss -tlnp 2>/dev/null | grep -E "(80|443|5432|8080)" | awk '{print "  " $4}' || netstat -tlnp 2>/dev/null | grep -E "(80|443|5432|8080)" | awk '{print "  " $4}' || echo "  Unable to check ports"
echo ""

# TLS certificates
print_header "TLS Certificates"
if [ "$APP_DEPLOYED" = false ]; then
    echo "  Skipped (app not deployed)"
elif [ -f "$APP_DIR/certs/cert.pem" ]; then
    CERT_EXPIRY=$(openssl x509 -enddate -noout -in "$APP_DIR/certs/cert.pem" 2>/dev/null | cut -d= -f2)
    if [ -n "$CERT_EXPIRY" ]; then
        print_ok "Certificate found, expires: $CERT_EXPIRY"
    else
        print_warn "Certificate found but could not read expiry"
    fi
else
    print_warn "No TLS certificate found (using self-signed or Let's Encrypt)"
fi
echo ""

# Cron job
print_header "Auto-Deploy Cron"
CRON_FILE="/etc/cron.d/${APP_NAME}-deploy"
if [ "$APP_DEPLOYED" = false ]; then
    echo "  Skipped (app not deployed)"
elif [ -f "$CRON_FILE" ]; then
    print_ok "Cron job configured: $CRON_FILE"
    grep -v "^#" "$CRON_FILE" | grep -v "^$" | head -3 | sed 's/^/  /'
else
    if crontab -l 2>/dev/null | grep -q "deploy-if-changed"; then
        print_ok "Cron job configured (user crontab)"
        crontab -l 2>/dev/null | grep "deploy-if-changed" | head -1 | sed 's/^/  /'
    else
        print_warn "No auto-deploy cron job found"
    fi
fi
echo ""

# Recent deploy logs
print_header "Recent Deploy Activity"
LOG_FILE="/var/log/${APP_NAME}/deploy.log"
if [ "$APP_DEPLOYED" = false ]; then
    echo "  Skipped (app not deployed)"
elif [ -f "$LOG_FILE" ]; then
    echo "Last 10 lines of deploy.log:"
    tail -10 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
else
    print_warn "No deploy log found at $LOG_FILE"
fi
echo ""

# Health check
print_header "Health Check"
if [ -n "$ACTIVE_CONTAINER" ]; then
    HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null || echo "failed")
    if [ "$HEALTH_RESPONSE" = "200" ]; then
        print_ok "Health endpoint: HTTP 200"
        curl -s http://localhost/health 2>/dev/null | head -c 200
        echo ""
    else
        print_error "Health endpoint: HTTP $HEALTH_RESPONSE"
    fi
else
    print_warn "No app container running, skipping health check"
fi
echo ""

# Recent app logs
print_header "Recent App Logs (last 5 lines)"
if [ -n "$ACTIVE_CONTAINER" ]; then
    docker logs --tail 5 "$ACTIVE_CONTAINER" 2>&1 | sed 's/^/  /'
else
    echo "  No app container running"
fi
echo ""

echo "=========================================="
if [ "$APP_DEPLOYED" = false ]; then
    print_warn "Status: App not deployed"
    echo "  Run 'deploy-init.sh' to deploy the app to this server."
elif [ -n "$ACTIVE_CONTAINER" ]; then
    print_ok "Status: App is running"
else
    print_error "Status: App deployed but not running"
    echo "  Check container logs for errors."
fi
echo "=========================================="
REMOTE_SCRIPT
}

# JSON format output
run_json_status() {
    ssh "$SERVER" bash << 'REMOTE_SCRIPT'
APP_DIR="/opt/paxx-test-app"
APP_NAME="paxx-test-app"

# Helper to escape JSON strings
json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

# Check if app is deployed
APP_DEPLOYED=false
if [ -d "$APP_DIR" ]; then
    APP_DEPLOYED=true
fi

# Collect data
ENV_EXISTS=false
IMAGE=""
if [ -f "$APP_DIR/.env" ]; then
    ENV_EXISTS=true
    source "$APP_DIR/.env"
fi

# Traefik
TRAEFIK_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "traefik" | head -1)
TRAEFIK_STATUS="not running"
TRAEFIK_RUNNING=false
if [ -n "$TRAEFIK_CONTAINER" ]; then
    TRAEFIK_STATUS=$(docker inspect --format='{{.State.Status}}' "$TRAEFIK_CONTAINER" 2>/dev/null)
    TRAEFIK_RUNNING=true
fi

# Database
DB_CONTAINER=$(docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | grep -E "postgres" | awk '{print $1}' | head -1)
DB_STATUS="not running"
DB_RUNNING=false
if [ -n "$DB_CONTAINER" ]; then
    DB_STATUS=$(docker inspect --format='{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null)
    DB_RUNNING=true
fi

# App blue
BLUE_CONTAINER="${APP_NAME}-blue"
BLUE_RUNNING=false
BLUE_STATUS="not running"
BLUE_HEALTH=""
BLUE_IMAGE=""
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${BLUE_CONTAINER}$"; then
    BLUE_RUNNING=true
    BLUE_STATUS=$(docker inspect --format='{{.State.Status}}' "$BLUE_CONTAINER" 2>/dev/null)
    BLUE_HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$BLUE_CONTAINER" 2>/dev/null)
    BLUE_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$BLUE_CONTAINER" 2>/dev/null)
fi

# App green
GREEN_CONTAINER="${APP_NAME}-green"
GREEN_RUNNING=false
GREEN_STATUS="not running"
GREEN_HEALTH=""
GREEN_IMAGE=""
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${GREEN_CONTAINER}$"; then
    GREEN_RUNNING=true
    GREEN_STATUS=$(docker inspect --format='{{.State.Status}}' "$GREEN_CONTAINER" 2>/dev/null)
    GREEN_HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$GREEN_CONTAINER" 2>/dev/null)
    GREEN_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$GREEN_CONTAINER" 2>/dev/null)
fi

# Determine active container
ACTIVE_SLOT="none"
ACTIVE_IMAGE=""
if [ "$BLUE_RUNNING" = true ]; then
    ACTIVE_SLOT="blue"
    ACTIVE_IMAGE="$BLUE_IMAGE"
fi
if [ "$GREEN_RUNNING" = true ]; then
    ACTIVE_SLOT="green"
    ACTIVE_IMAGE="$GREEN_IMAGE"
fi
if [ "$BLUE_RUNNING" = true ] && [ "$GREEN_RUNNING" = true ]; then
    ACTIVE_SLOT="both"
fi

# System resources
DISK_TOTAL=$(df -h / | tail -1 | awk '{print $2}')
DISK_USED=$(df -h / | tail -1 | awk '{print $3}')
DISK_PERCENT=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
MEM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
MEM_USED=$(free -h | grep Mem | awk '{print $3}')

# TLS
TLS_EXISTS=false
TLS_EXPIRY=""
if [ -f "$APP_DIR/certs/cert.pem" ]; then
    TLS_EXISTS=true
    TLS_EXPIRY=$(openssl x509 -enddate -noout -in "$APP_DIR/certs/cert.pem" 2>/dev/null | cut -d= -f2)
fi

# Cron
CRON_CONFIGURED=false
CRON_FILE="/etc/cron.d/${APP_NAME}-deploy"
if [ -f "$CRON_FILE" ] || crontab -l 2>/dev/null | grep -q "deploy-if-changed"; then
    CRON_CONFIGURED=true
fi

# Health check
HEALTH_STATUS="unknown"
HEALTH_CODE=""
if [ "$ACTIVE_SLOT" != "none" ]; then
    HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null || echo "0")
    if [ "$HEALTH_CODE" = "200" ]; then
        HEALTH_STATUS="healthy"
    else
        HEALTH_STATUS="unhealthy"
    fi
fi

# Determine overall status
OVERALL_STATUS="not_deployed"
if [ "$APP_DEPLOYED" = true ]; then
    if [ "$ACTIVE_SLOT" != "none" ]; then
        if [ "$HEALTH_STATUS" = "healthy" ]; then
            OVERALL_STATUS="running"
        else
            OVERALL_STATUS="running_unhealthy"
        fi
    else
        OVERALL_STATUS="stopped"
    fi
fi

# Output JSON
cat << EOF
{
  "app": "$APP_NAME",
  "server": "$(hostname)",
  "timestamp": "$(date -Iseconds)",
  "deployed": $APP_DEPLOYED,
  "status": "$OVERALL_STATUS",
  "environment": {
    "exists": $ENV_EXISTS,
    "image": "$IMAGE"
  },
  "containers": {
    "traefik": {
      "running": $TRAEFIK_RUNNING,
      "name": "$TRAEFIK_CONTAINER",
      "status": "$TRAEFIK_STATUS"
    },
    "database": {
      "running": $DB_RUNNING,
      "name": "$DB_CONTAINER",
      "status": "$DB_STATUS"
    },
    "app": {
      "active_slot": "$ACTIVE_SLOT",
      "active_image": "$ACTIVE_IMAGE",
      "blue": {
        "running": $BLUE_RUNNING,
        "status": "$BLUE_STATUS",
        "health": "$BLUE_HEALTH",
        "image": "$BLUE_IMAGE"
      },
      "green": {
        "running": $GREEN_RUNNING,
        "status": "$GREEN_STATUS",
        "health": "$GREEN_HEALTH",
        "image": "$GREEN_IMAGE"
      }
    }
  },
  "resources": {
    "disk": {
      "total": "$DISK_TOTAL",
      "used": "$DISK_USED",
      "percent": $DISK_PERCENT
    },
    "memory": {
      "total": "$MEM_TOTAL",
      "used": "$MEM_USED"
    }
  },
  "tls": {
    "configured": $TLS_EXISTS,
    "expiry": "$TLS_EXPIRY"
  },
  "cron": {
    "configured": $CRON_CONFIGURED
  },
  "health": {
    "status": "$HEALTH_STATUS",
    "http_code": "$HEALTH_CODE"
  }
}
EOF
REMOTE_SCRIPT
}

# Run the appropriate format
if [ "$FORMAT" = "json" ]; then
    run_json_status
else
    run_text_status
fi
