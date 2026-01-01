#!/bin/bash
# Auto-deploy script for paxx-test-app
# Checks if a new image is available and deploys if changed
#
# Usage: ./deploy-if-changed.sh
#
# Intended to be run via cron:
#   */5 * * * * /opt/paxx-test-app/deploy-if-changed.sh >> /var/log/paxx-test-app/deploy.log 2>&1

set -e


# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Configuration
IMAGE=${IMAGE:-ghcr.io/your-username/paxx-test-app:latest}
LOCK_FILE="/tmp/paxx-test-app-deploy.lock"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "$(date): Deploy already in progress (PID $LOCK_PID), skipping"
        exit 0
    else
        # Stale lock file, remove it
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# Get local image digest
LOCAL_DIGEST=$(docker images --digests --format "{{.Digest}}" "$IMAGE" 2>/dev/null | head -1)

# Get remote digest (without pulling the full image)
# Try docker manifest inspect first, fall back to skopeo if available
if command -v skopeo &> /dev/null; then
    REMOTE_DIGEST=$(skopeo inspect --format "{{.Digest}}" "docker://$IMAGE" 2>/dev/null || echo "")
else
    # docker manifest inspect requires experimental features or login
    REMOTE_DIGEST=$(docker manifest inspect "$IMAGE" 2>/dev/null | jq -r '.manifests[0].digest // .config.digest // empty' || echo "")
fi

# Handle case where we can't get remote digest
if [ -z "$REMOTE_DIGEST" ]; then
    echo "$(date): Could not fetch remote digest for $IMAGE (may need docker login for private repos)"
    exit 0
fi

# Compare digests
if [ -z "$LOCAL_DIGEST" ]; then
    echo "$(date): No local image found, deploying $IMAGE..."
    "$SCRIPT_DIR/deploy.sh" latest
elif [ "$LOCAL_DIGEST" != "$REMOTE_DIGEST" ]; then
    echo "$(date): New image detected!"
    echo "  Local:  $LOCAL_DIGEST"
    echo "  Remote: $REMOTE_DIGEST"
    echo "$(date): Deploying..."
    "$SCRIPT_DIR/deploy.sh" latest
else
    echo "$(date): Image up to date ($IMAGE)"
fi

