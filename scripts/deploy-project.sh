#!/bin/bash
set -e

# Deploy Individual Ignition Project
# Usage: ./scripts/deploy-project.sh <environment> <project_zip_file|project_directory>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT_INPUT=$1
PROJECT_SOURCE=$2

if [ -z "$ENVIRONMENT_INPUT" ] || [ -z "$PROJECT_SOURCE" ]; then
  echo "Error: Missing required arguments"
  echo "Usage: ./scripts/deploy-project.sh <environment> <project_zip_file|project_directory>"
  exit 1
fi

case "$ENVIRONMENT_INPUT" in
  local)
    ENVIRONMENT="local"
    ENV_VAR_PREFIX="LOCAL"
    ;;
  dev|development)
    ENVIRONMENT="dev"
    ENV_VAR_PREFIX="DEV"
    ;;
  staging)
    ENVIRONMENT="staging"
    ENV_VAR_PREFIX="STAGING"
    ;;
  prod|production)
    ENVIRONMENT="prod"
    ENV_VAR_PREFIX="PROD"
    ;;
  *)
    echo "Error: Unknown environment: $ENVIRONMENT_INPUT"
    echo "Available environments: local, dev, staging, prod"
    exit 1
    ;;
esac

# Check if source is zip file or directory
IS_ZIP=false
if [ -f "$PROJECT_SOURCE" ] && [[ "$PROJECT_SOURCE" == *.zip ]]; then
  IS_ZIP=true
elif [ ! -d "$PROJECT_SOURCE" ]; then
  echo "Error: Project source not found: $PROJECT_SOURCE"
  exit 1
fi

CONFIG_FILE="$PROJECT_ROOT/config/environments/${ENVIRONMENT}.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found: $CONFIG_FILE"
  exit 1
fi

# Parse configuration
DEPLOY_ROOT=$(grep "^deploy_root:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
GATEWAY_URL_FROM_CONFIG=$(grep "url:" "$CONFIG_FILE" | head -1 | awk '{print $2}')
API_KEY_FROM_CONFIG=$(grep "api_key:" "$CONFIG_FILE" | head -1 | awk '{print $2}')

GATEWAY_URL_ENV_VAR="${ENV_VAR_PREFIX}_GATEWAY_URL"
GATEWAY_API_KEY_ENV_VAR="${ENV_VAR_PREFIX}_GATEWAY_API_KEY"
GATEWAY_URL="$(eval echo \$${GATEWAY_URL_ENV_VAR})"
API_KEY="$(eval echo \$${GATEWAY_API_KEY_ENV_VAR})"

if [ -z "$GATEWAY_URL" ]; then
  GATEWAY_URL="$GATEWAY_URL_FROM_CONFIG"
fi
if [ -z "$API_KEY" ]; then
  API_KEY="$API_KEY_FROM_CONFIG"
fi

# Use deploy_root if specified, otherwise use PROJECT_ROOT
if [ -n "$DEPLOY_ROOT" ]; then
  DEPLOY_TARGET="$DEPLOY_ROOT"
else
  DEPLOY_TARGET="$PROJECT_ROOT"
fi

# Determine project name and prepare source
if [ "$IS_ZIP" = true ]; then
  TEMP_DIR=$(mktemp -d)
  unzip -q "$PROJECT_SOURCE" -d "$TEMP_DIR"
  SOURCE_DIR="$TEMP_DIR"
  ZIP_BASENAME=$(basename "$PROJECT_SOURCE" .zip)
  PROJECT_NAME=$(echo "$ZIP_BASENAME" | sed -E 's/-+[v]?[0-9]+\.[0-9]+\.[0-9]+(-[a-f0-9]+)?$//' | sed -E 's/-+[a-f0-9]{7,}$//')
  if [ -z "$PROJECT_NAME" ] || [ "$PROJECT_NAME" = "$ZIP_BASENAME" ]; then
    PROJECT_NAME="$ZIP_BASENAME"
  fi
else
  PROJECT_NAME=$(basename "$PROJECT_SOURCE")
  SOURCE_DIR="$PROJECT_SOURCE"
fi

echo "=========================================="
echo "Deploying Project: $PROJECT_NAME"
echo "Environment: $ENVIRONMENT"
echo "=========================================="

# Deploy directory — directly inside deploy_root
DEPLOY_DIR="$DEPLOY_TARGET/$PROJECT_NAME"

echo "Deploying to: $DEPLOY_DIR"

# Create directory if it doesn't exist
mkdir -p "$(dirname "$DEPLOY_DIR")"

# Remove existing project if it exists
if [ -d "$DEPLOY_DIR" ]; then
  echo "Removing existing project..."
  rm -rf "$DEPLOY_DIR"
fi

# Copy project files
echo "Copying project files..."
cp -r "$SOURCE_DIR" "$DEPLOY_DIR"

# Clean up temp directory if we extracted a zip
if [ "$IS_ZIP" = true ]; then
  rm -rf "$TEMP_DIR"
fi

# Function to trigger Ignition scans
trigger_ignition_scans() {
  echo "Triggering Ignition resource scans..."

  if [ -z "$API_KEY" ]; then
    echo "  No API key configured, skipping resource scans"
    echo "  Gateway will auto-detect changes"
    return 0
  fi

  # Trigger config scan
  echo "  - Scanning gateway configuration..."
  CONFIG_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Ignition-API-Token: $API_KEY" \
    -X POST "${GATEWAY_URL}/data/api/v1/scan/config")
  if [ "$CONFIG_HTTP_CODE" = "200" ]; then
    echo "    ✓ Config scan triggered"
  else
    echo "    ✗ Config scan failed (HTTP $CONFIG_HTTP_CODE) — continuing anyway"
  fi

  # Trigger projects scan
  echo "  - Scanning projects..."
  PROJECTS_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Ignition-API-Token: $API_KEY" \
    -X POST "${GATEWAY_URL}/data/api/v1/scan/projects")
  if [ "$PROJECTS_HTTP_CODE" = "200" ]; then
    echo "    ✓ Projects scan triggered"
  else
    echo "    ✗ Projects scan failed (HTTP $PROJECTS_HTTP_CODE) — continuing anyway"
  fi
}

# Verify gateway is running
echo "Verifying gateway health..."
if ! curl -s -f "${GATEWAY_URL}/StatusPing" > /dev/null 2>&1; then
  echo ""
  echo "✗ Gateway is not responding at ${GATEWAY_URL}"
  echo "  Please ensure Ignition is running"
  echo ""
  exit 1
fi
echo "✓ Gateway is healthy"

# Trigger scans — failures won't abort deployment now
trigger_ignition_scans

echo ""
echo "✓ Project deployed successfully!"
echo "  Project: $PROJECT_NAME"
echo "  Environment: $ENVIRONMENT"
echo "  Location: $DEPLOY_DIR"
echo "  Gateway: ${GATEWAY_URL}/web/home"
echo ""
