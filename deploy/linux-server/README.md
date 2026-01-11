# Linux Server Deployment for paxx-test-app

Deploy paxx-test-app to any Linux server (Debian, Ubuntu, Raspbian) with zero-downtime blue-green deployments.

## Quick Start

### 1. Configure environment

Create and edit `.env` file:

```bash
cp deploy/linux-server/.env.example deploy/linux-server/.env
```

### 2. Setup TLS certificates (optional but recommended)

For trusted HTTPS on local networks, use [mkcert](https://github.com/FiloSottile/mkcert) to create locally-trusted certificates.

**macOS:**
```bash
brew install mkcert
mkcert -install
mkcert -cert-file deploy/linux-server/certs/cert.pem \
       -key-file deploy/linux-server/certs/key.pem \
       YOUR_SERVER_IP
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt install libnss3-tools
curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
chmod +x mkcert-v*-linux-amd64
sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
mkcert -install
mkcert -cert-file deploy/linux-server/certs/cert.pem \
       -key-file deploy/linux-server/certs/key.pem \
       YOUR_SERVER_IP
```

**Windows (PowerShell as Admin):**
```powershell
choco install mkcert
mkcert -install
mkcert -cert-file deploy/linux-server/certs/cert.pem `
       -key-file deploy/linux-server/certs/key.pem `
       YOUR_SERVER_IP
```

Replace `YOUR_SERVER_IP` with your server's IP (e.g., `192.168.1.100`).

Without certificates, HTTPS still works but browsers will show a security warning.

### 3. Prepare server environment

```bash
./deploy/linux-server/deploy-init.sh user@your-server
```

This runs server setup (Docker, firewall, cron), starts Traefik + PostgreSQL, and enables auto-deploy.

### 4. Build and push image

```bash
git add -A && git commit -m "Add deployment"
git tag v1.0.0
git push origin main --tags
```

GitHub Actions builds and pushes to `ghcr.io/<username>/paxx-test-app:v1.0.0`.

The cron job detects the new image within 5 minutes and deploys automatically.

Your app is available at:
- `http://YOUR_SERVER_IP/` (HTTP)
- `https://YOUR_SERVER_IP/` (HTTPS - trusted if you set up mkcert)

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Traefik + PostgreSQL stack |
| `deploy.sh` | Blue-green deploy script |
| `deploy-if-changed.sh` | Auto-deploy (runs via cron) |
| `deploy-init.sh` | Initialize deployment on server |
| `get-status.sh` | Check deployment status (read-only) |
| `deploy-purge.sh` | Complete cleanup of all deployment artifacts |
| `server-setup.sh` | One-time server setup |
| `traefik-dynamic.yml` | TLS certificate configuration |
| `certs/` | TLS certificates (cert.pem, key.pem) |
| `.env.example` | Environment template |

## How It Works

1. **GitHub Actions** builds Docker image on git tags
2. **Cron job** checks for new images every 5 minutes
3. **Blue-green deploy** starts new container, waits for health check, stops old
4. **Traefik** routes traffic to healthy container

## Manual Deploy

```bash
ssh user@your-server
cd /opt/paxx-test-app
./deploy.sh v1.2.0    # Deploy specific version
./deploy.sh           # Deploy :latest
```

## Rollback

```bash
./deploy.sh v1.0.0    # Just deploy the previous version
```

## Check Status

Get a comprehensive status report from your server (read-only):

```bash
./deploy/linux-server/get-status.sh user@your-server
```

This shows:
- Container status (Traefik, database, app blue/green)
- Resource usage (CPU, memory, disk)
- TLS certificate expiry
- Auto-deploy cron status
- Recent deploy logs
- Health check response
- Recent app logs

## Complete Purge (Reset Server)

To completely remove all deployment artifacts and reset the server to pre-deployment state:

```bash
ssh user@your-server
cd /opt/paxx-test-app
sudo ./deploy-purge.sh
```

**WARNING: This is destructive!** The purge script will:

1. **Scan** for all deployment artifacts
2. **Report** findings grouped by category:
   - **DESTRUCTIVE** (red): PostgreSQL volume with all database data
   - **DEPLOYMENT** (yellow): Containers, networks, images, directories, files, firewall rules
   - **SYSTEM** (blue): Docker, docker group membership, packages (jq)
3. **Show** exact commands that will run
4. **Require** typing `PURGE` to confirm (not just y/n)
5. **Execute** complete cleanup including Docker uninstall

Use this when you want to:
- Completely remove the deployment from a server
- Start fresh with a clean slate
- Decommission a server

## Logs & Debugging

### Application Logs

```bash
# Follow app logs (use -blue or -green depending on which is active)
docker logs -f paxx-test-app-blue
docker logs -f paxx-test-app-green

# Last 100 lines (use -blue or -green)
docker logs --tail 100 paxx-test-app-blue

# Logs with timestamps
docker logs -t paxx-test-app-blue

# Logs since specific time
docker logs --since 1h paxx-test-app-blue
docker logs --since "2024-01-15T10:00:00" paxx-test-app-blue
```

> **Tip:** Use `docker ps | grep paxx-test-app` to see which container (blue or green) is currently running.

### Deploy Logs

```bash
# Follow deploy log
tail -f /var/log/paxx-test-app/deploy.log

# Last 50 lines of deploy log
tail -50 /var/log/paxx-test-app/deploy.log
```

### Container Status

```bash
# List all containers
docker ps -a

# Check which container is active (blue or green)
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep paxx-test-app

# Container resource usage
docker stats --no-stream

# Inspect container details (use -blue or -green)
docker inspect paxx-test-app-blue

# Container health check status (use -blue or -green)
docker inspect --format='{{.State.Health.Status}}' paxx-test-app-blue
```

### Traefik (Reverse Proxy)

```bash
# Traefik logs
docker logs -f traefik

# Check Traefik routing
docker logs traefik 2>&1 | grep paxx-test-app

# Traefik dashboard (if enabled)
# Access at http://YOUR_SERVER_IP:8080
```

### PostgreSQL

```bash
# Database logs
docker logs -f paxx-test-app-db

# Connect to database
docker exec -it paxx-test-app-db psql -U postgres -d paxx-test-app

# Database size
docker exec paxx-test-app-db psql -U postgres -d paxx-test-app -c "SELECT pg_size_pretty(pg_database_size('paxx-test-app'));"

# Active connections
docker exec paxx-test-app-db psql -U postgres -c "SELECT * FROM pg_stat_activity WHERE datname = 'paxx-test-app';"
```

### Network & Connectivity

```bash
# Check if app is responding
curl -s http://localhost/health | jq

# Check container networking
docker network ls
docker network inspect paxx-test-app_default

# Test internal connectivity (use -blue or -green)
docker exec paxx-test-app-blue curl -s http://localhost:8000/health
```

### System Resources

```bash
# Disk usage
df -h
docker system df

# Memory usage
free -h

# Clean up unused Docker resources
docker system prune -f
docker image prune -a -f  # Remove all unused images
```

### Interactive Debugging

```bash
# Shell into running container (use -blue or -green)
docker exec -it paxx-test-app-blue /bin/bash

# Run a one-off command (use -blue or -green)
docker exec paxx-test-app-blue python -c "print('hello')"

# Check environment variables (use -blue or -green)
docker exec paxx-test-app-blue env | sort
```

### Cron Job (Auto-deploy)

```bash
# Check cron status
systemctl status cron

# View cron logs
grep CRON /var/log/syslog | tail -20

# List cron jobs
crontab -l
```
