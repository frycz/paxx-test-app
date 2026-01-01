#!/bin/bash
# Install linux-server deployment for paxx-test-app
# This script copies deployment files to their correct locations

set -e


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKFLOW_FILE="$PROJECT_ROOT/.github/workflows/build.yml"
DEPLOY_DIR="$PROJECT_ROOT/deploy/linux-server"

# Check for potential conflicts
WARNINGS=()

if [ -f "$WORKFLOW_FILE" ]; then
    WARNINGS+=("  - .github/workflows/build.yml already exists (will be overwritten)")
fi

if [ -d "$DEPLOY_DIR" ] && [ "$(ls -A "$DEPLOY_DIR" 2>/dev/null)" ]; then
    WARNINGS+=("  - deploy/linux-server/ is not empty (files may be overwritten)")
fi

# Ask for confirmation if there are warnings
if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "Warning:"
    for warning in "${WARNINGS[@]}"; do
        echo "$warning"
    done
    echo ""
    read -p "Continue? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo "Adding linux-server deployment..."

# Create directories
mkdir -p "$PROJECT_ROOT/.github/workflows"
mkdir -p "$DEPLOY_DIR"

# Copy GitHub Actions workflow
cp "$SCRIPT_DIR/build.yml.example" "$WORKFLOW_FILE"
echo "  Created .github/workflows/build.yml"

# Copy deployment scripts
cp "$SCRIPT_DIR/server-setup.sh" "$DEPLOY_DIR/"
cp "$SCRIPT_DIR/deploy-init.sh" "$DEPLOY_DIR/"
cp "$SCRIPT_DIR/deploy.sh" "$DEPLOY_DIR/"
cp "$SCRIPT_DIR/deploy-if-changed.sh" "$DEPLOY_DIR/"
cp "$SCRIPT_DIR/docker-compose.yml" "$DEPLOY_DIR/"
cp "$SCRIPT_DIR/.env.example" "$DEPLOY_DIR/"
chmod +x "$DEPLOY_DIR/server-setup.sh" "$DEPLOY_DIR/deploy-init.sh" "$DEPLOY_DIR/deploy.sh" "$DEPLOY_DIR/deploy-if-changed.sh"
echo "  Created deploy/linux-server/server-setup.sh"
echo "  Created deploy/linux-server/deploy-init.sh"
echo "  Created deploy/linux-server/deploy.sh"
echo "  Created deploy/linux-server/deploy-if-changed.sh"
echo "  Created deploy/linux-server/docker-compose.yml"
echo "  Created deploy/linux-server/.env.example"

echo ""
echo "Linux-server deployment added!"
echo ""
echo "Next steps:"
echo "  1. Copy deploy/linux-server/.env.example, rename to deploy/linux-server/.env and customize it."
echo "  2. Push to GitHub the changes you want to deploy."
echo "  3. Create a git tag to trigger the build, eg.: git tag v1.0.0 && git push origin v1.0.0"
echo "  4. Run: ./deploy/linux-server/deploy-init.sh user@your-server"

