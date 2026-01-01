# Linux Server Deployment for paxx-test-app

Deploy paxx-test-app to any Linux server (Debian, Ubuntu, Raspbian) with zero-downtime blue-green deployments.

## Quick Start

### 1. Activate deployment

```bash
paxx deploy add linux-server
```

This copies deployment files to `deploy/linux-server/` and creates `.github/workflows/build.yml`.

### 2. Configure

```bash
cp deploy/linux-server/.env.example deploy/linux-server/.env
# Edit .env with your settings (IMAGE, POSTGRES_PASSWORD)
```

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

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Traefik + PostgreSQL stack |
| `deploy.sh` | Blue-green deploy script |
| `deploy-if-changed.sh` | Auto-deploy (runs via cron) |
| `server-setup.sh` | One-time server setup |
| `.env.example` | Environment template |

## How It Works

1. **GitHub Actions** builds Docker image on git tags
2. **Cron job** checks for new images every 5 minutes
3. **Blue-green deploy** starts new container, waits for health check, stops old
4. **Traefik** routes traffic to healthy container

## Manual Deploy

```bash
ssh user@your-server
cd ~/paxx-test-app
./deploy.sh v1.2.0    # Deploy specific version
./deploy.sh           # Deploy :latest
```

## Rollback

```bash
./deploy.sh v1.0.0    # Just deploy the previous version
```

## Logs

```bash
# Deploy logs
tail -f /var/log/paxx-test-app/deploy.log

# App logs
docker logs -f paxx-test-app-blue   # or -green
```
