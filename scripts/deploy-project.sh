#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT_INPUT=$1
PROJECT_SOURCE=$2

if [ -z "$ENVIRONMENT_INPUT" ] || [ -z "$PROJECT_SOURCE" ]; then
  echo "Error: Missing required arguments"
  exit 1
fi

case "$ENVIRONMENT_INPUT" in
  local) ENVIRONMENT="local"; ENV_VAR_PREFIX="LOCAL" ;;
  dev|development) ENVIRONMENT="dev"; ENV_VAR_PREFIX="DEV" ;;
  staging) ENVIRONMENT="staging"; ENV_VAR_PREFIX="STAGING" ;;
  prod|production) ENVIRONMENT="prod"; ENV_VAR_PREFIX="PROD" ;;
  *) echo "Error: Unknown environment: $ENVIRONMENT_INPUT"; exit 1 ;;
esac

IS_ZIP=false
if [ -f "$PROJECT_SOURCE" ] && [[ "$PROJECT_SOURCE" == *.zip ]]; then
  IS_ZIP=true
elif [ ! -d "$PROJECT_SOURCE" ]; then
  echo "Error: Project source not found: $PROJECT_SOURCE"
  exit 1
fi

CONFIG_FILE="$PROJECT_ROOT/config/environments/${ENVIRONMENT}.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

DEPLOY_ROOT=$(grep "^deploy_root:" "$CONFIG_FILE" | sed 's/^deploy_root:[[:space:]]*//' | tr -d '"')
GATEWAY_URL_FROM_CONFIG=$(grep "url:" "$CONFIG_FILE" | head -1 | awk '{print $2}')
API_KEY_FROM_CONFIG=$(grep "api_key:" "$CONFIG_FILE" | head -1 | awk '{print $2}')

GATEWAY_URL_ENV_VAR="${ENV_VAR_PREFIX}_GATEWAY_URL"
GATEWAY_API_KEY_ENV_VAR="${ENV_VAR_PREFIX}_GATEWAY_API_KEY"
GATEWAY_URL="$(eval echo \$${GATEWAY_URL_ENV_VAR})"
API_KEY="$(eval echo \$${GATEWAY_API_KEY_ENV_VAR})"

if [ -z "$GATEWAY_URL" ]; then GATEWAY_URL="$GATEWAY_URL_FROM_CONFIG"; fi
if [ -z "$API_KEY" ]; then API_KEY="$API_KEY_FROM_CONFIG"; fi

if [ -n "$DEPLOY_ROOT" ]; then
  DEPLOY_TARGET="$DEPLOY_ROOT"
else
  DEPLOY_TARGET="$PROJECT_ROOT"
fi

echo "DEBUG: DEPLOY_TARGET=$DEPLOY_TARGET"

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

DEPLOY_DIR="$DEPLOY_TARGET/$PROJECT_NAME"
echo "Deploying to: $DEPLOY_DIR"

mkdir -p "$(dirname "$DEPLOY_DIR")"

if [ -d "$DEPLOY_DIR" ]; then
  echo "Removing existing project..."
  rm -rf "$DEPLOY_DIR"
fi

echo "Copying project files..."
cp -r "$SOURCE_DIR" "$DEPLOY_DIR"

if [ "$IS_ZIP" = true ]; then rm -rf "$TEMP_DIR"; fi

echo "Verifying gateway health..."
if ! curl -s -f "${GATEWAY_URL}/StatusPing" > /dev/null 2>&1; then
  echo "Gateway not responding at ${GATEWAY_URL}"
  exit 1
fi
echo "Gateway is healthy"

if [ -n "$API_KEY" ]; then
  curl -s -o /dev/null -w "Config scan: %{http_code}\n" \
    -H "X-Ignition-API-Token: $API_KEY" \
    -X POST "${GATEWAY_URL}/data/api/v1/scan/config"
  curl -s -o /dev/null -w "Projects scan: %{http_code}\n" \
    -H "X-Ignition-API-Token: $API_KEY" \
    -X POST "${GATEWAY_URL}/data/api/v1/scan/projects"
fi

echo ""
echo "Project deployed successfully!"
echo "  Project: $PROJECT_NAME"
echo "  Location: $DEPLOY_DIR"
echo "  Gateway: ${GATEWAY_URL}/web/home"
echo ""
