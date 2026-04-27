#!/bin/bash
set -e

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
  local)            ENVIRONMENT="local";   ENV_VAR_PREFIX="LOCAL"   ;;
  dev|development)  ENVIRONMENT="dev";     ENV_VAR_PREFIX="DEV"     ;;
  staging)          ENVIRONMENT="staging"; ENV_VAR_PREFIX="STAGING" ;;
  prod|production)  ENVIRONMENT="prod";    ENV_VAR_PREFIX="PROD"    ;;
  *)
    echo "Error: Unknown environment: $ENVIRONMENT_INPUT"
    exit 1
    ;;
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
TAGS_ROOT=$(grep "^tags_root:"    "$CONFIG_FILE" | sed 's/^tags_root:[[:space:]]*//'    | tr -d '"')
GATEWAY_URL_FROM_CONFIG=$(grep "url:" "$CONFIG_FILE" | head -1 | awk '{print $2}')
API_KEY_FROM_CONFIG=$(grep "api_key:" "$CONFIG_FILE" | head -1 | awk '{print $2}')

GATEWAY_URL="$(eval echo \$${ENV_VAR_PREFIX}_GATEWAY_URL)"
API_KEY="$(eval    echo \$${ENV_VAR_PREFIX}_GATEWAY_API_KEY)"
GATEWAY_PASS="$(eval echo \$${ENV_VAR_PREFIX}_GATEWAY_PASS)"
GATEWAY_USER="$(eval echo \$${ENV_VAR_PREFIX}_GATEWAY_USER)"

if [ -z "$GATEWAY_URL" ];  then GATEWAY_URL="$GATEWAY_URL_FROM_CONFIG"; fi
if [ -z "$API_KEY" ];      then API_KEY="$API_KEY_FROM_CONFIG";         fi
if [ -z "$API_KEY" ] && [ -f "$PROJECT_ROOT/secrets/gateway_api_key" ]; then
  API_KEY=$(tr -d '\r\n' < "$PROJECT_ROOT/secrets/gateway_api_key")
fi

if [ -n "$DEPLOY_ROOT" ]; then
  DEPLOY_TARGET="$DEPLOY_ROOT"
else
  DEPLOY_TARGET="$PROJECT_ROOT"
fi

if [ "$IS_ZIP" = true ]; then
  TEMP_DIR=$(mktemp -d)
  unzip -q "$PROJECT_SOURCE" -d "$TEMP_DIR"
  SOURCE_DIR="$TEMP_DIR"
  ZIP_BASENAME=$(basename "$PROJECT_SOURCE" .zip)
  PROJECT_NAME=$(echo "$ZIP_BASENAME" \
    | sed -E 's/-+[v]?[0-9]+\.[0-9]+\.[0-9]+(-[a-f0-9]+)?$//' \
    | sed -E 's/-+[a-f0-9]{7,}$//')
  if [ -z "$PROJECT_NAME" ] || [ "$PROJECT_NAME" = "$ZIP_BASENAME" ]; then
    PROJECT_NAME="$ZIP_BASENAME"
  fi
else
  PROJECT_NAME=$(basename "$PROJECT_SOURCE")
  SOURCE_DIR="$PROJECT_SOURCE"
fi

echo "=========================================="
echo "Deploying Project: $PROJECT_NAME"
echo "Environment:       $ENVIRONMENT"
echo "=========================================="

DEPLOY_DIR="$DEPLOY_TARGET/$PROJECT_NAME"
echo "Deploying to: $DEPLOY_DIR"

mkdir -p "$DEPLOY_DIR"

echo "Copying project files..."
cp -rf "$SOURCE_DIR/." "$DEPLOY_DIR/"
echo "  ✓ Project files updated"

if [ "$IS_ZIP" = true ]; then rm -rf "$TEMP_DIR"; fi

# ─── Tags deploy ──────────────────────────────────────────────────────────────
TAGS_SOURCE="$DEPLOY_DIR/ignition/tags/tags.json"
RESOURCE_SOURCE="$DEPLOY_DIR/ignition/tags/unary-resource.json"

if [ -f "$TAGS_SOURCE" ] && [ -n "$TAGS_ROOT" ]; then
  echo ""
  echo "Deploying tags to file system..."
  mkdir -p "$TAGS_ROOT"
  cp "$TAGS_SOURCE" "$TAGS_ROOT/tags.json"
  echo "  ✓ tags.json copied"

  if [ -f "$RESOURCE_SOURCE" ]; then
    cp "$RESOURCE_SOURCE" "$TAGS_ROOT/unary-resource.json"
    echo "  ✓ unary-resource.json copied"
  else
    cat > "$TAGS_ROOT/unary-resource.json" << 'EOF'
{
  "scope": "G",
  "version": 1,
  "restricted": false,
  "overridable": true,
  "files": ["tags.json"],
  "attributes": { "config": {} }
}
EOF
    echo "  ✓ unary-resource.json created (default)"
  fi

  # ─── Tags reload: pehle scan API, phir WebDev fallback ───────────────────
  echo ""
  echo "Reloading tags..."
  TAGS_RELOAD_SUCCESS=false

  # Option 1: Scan API
  if [ -n "$API_KEY" ]; then
    echo "  - Trying scan API..."
    TAGS_SCAN_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "X-Ignition-API-Token: $API_KEY" \
      -X POST "${GATEWAY_URL}/data/api/v1/scan/config")

    if [ "$TAGS_SCAN_CODE" = "200" ]; then
      echo "  ✓ Tags reloaded via scan API (HTTP 200)"
      TAGS_RELOAD_SUCCESS=true
    else
      echo "  ⚠ Scan API failed (HTTP $TAGS_SCAN_CODE) — trying WebDev fallback..."
    fi
  fi

  # Option 2: WebDev fallback
  if [ "$TAGS_RELOAD_SUCCESS" = false ]; then
    echo "  - Trying WebDev reload..."
    if [ -z "$GATEWAY_USER" ] || [ -z "$GATEWAY_PASS" ]; then
      echo "  ⚠ GATEWAY_USER or GATEWAY_PASS not set — skipping WebDev reload"
    else
      TAGS_RELOAD_CODE=$(curl -s -o /tmp/tags_reload_response.txt -w "%{http_code}" \
        -u "${GATEWAY_USER}:${GATEWAY_PASS}" \
        -X GET \
        "${GATEWAY_URL}/system/webdev/${PROJECT_NAME}/api/reloadTags")

      if [ "$TAGS_RELOAD_CODE" = "200" ]; then
        echo "  ✓ Tags reloaded via WebDev (HTTP 200)"
        TAGS_RELOAD_SUCCESS=true
      else
        TAGS_RESPONSE_BODY=$(cat /tmp/tags_reload_response.txt 2>/dev/null || echo "no response")
        echo "  ⚠ WebDev reload failed (HTTP $TAGS_RELOAD_CODE): $TAGS_RESPONSE_BODY"
        echo "  ⚠ tags.json copied — Ignition will auto-detect changes shortly"
      fi
    fi
  fi
  # ─────────────────────────────────────────────────────────────────────────

else
  echo "  ℹ No tags file or tags_root not configured — skipping tags"
fi

# ─── Gateway health check ─────────────────────────────────────────────────────
echo ""
echo "Verifying gateway health..."
if ! curl -s -f "${GATEWAY_URL}/StatusPing" > /dev/null 2>&1; then
  echo "✗ Gateway not responding at ${GATEWAY_URL}"
  exit 1
fi
echo "✓ Gateway is healthy"

# ─── Ignition reload ──────────────────────────────────────────────────────────
echo ""
echo "Reloading Ignition resources..."
SCAN_SUCCESS=false

# Option 1: Scan API
if [ -n "$API_KEY" ]; then
  echo "  - Trying scan API..."

  CONFIG_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Ignition-API-Token: $API_KEY" \
    -X POST "${GATEWAY_URL}/data/api/v1/scan/config")

  PROJECTS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Ignition-API-Token: $API_KEY" \
    -X POST "${GATEWAY_URL}/data/api/v1/scan/projects")

  if [ "$CONFIG_CODE" = "200" ] && [ "$PROJECTS_CODE" = "200" ]; then
    echo "    ✓ Config scan triggered (HTTP 200)"
    echo "    ✓ Projects scan triggered (HTTP 200)"
    SCAN_SUCCESS=true
  else
    echo "    ⚠ Scan API failed (config: HTTP $CONFIG_CODE, projects: HTTP $PROJECTS_CODE)"
    echo "    ⚠ Trying WebDev fallback..."
  fi
fi

# Option 2: WebDev fallback
if [ "$SCAN_SUCCESS" = false ]; then
  echo "  - Trying WebDev reload..."
  if [ -z "$GATEWAY_USER" ] || [ -z "$GATEWAY_PASS" ]; then
    echo "    ⚠ GATEWAY_USER or GATEWAY_PASS not set — skipping WebDev reload"
  else
    RELOAD_CODE=$(curl -s -o /tmp/webdev_response.txt -w "%{http_code}" \
      -u "${GATEWAY_USER}:${GATEWAY_PASS}" \
      -X GET \
      "${GATEWAY_URL}/system/webdev/${PROJECT_NAME}/api/reload")

    if [ "$RELOAD_CODE" = "200" ]; then
      echo "    ✓ WebDev reload successful (HTTP 200)"
      SCAN_SUCCESS=true
    else
      RESPONSE_BODY=$(cat /tmp/webdev_response.txt 2>/dev/null || echo "no response")
      echo "    ⚠ WebDev reload failed (HTTP $RELOAD_CODE): $RESPONSE_BODY"
      echo "    ⚠ Files are copied — Ignition will auto-detect changes shortly"
    fi
  fi
fi

echo ""
echo "=========================================="
echo "✓ Project deployed successfully!"
echo "  Project:  $PROJECT_NAME"
echo "  Location: $DEPLOY_DIR"
echo "  Gateway:  ${GATEWAY_URL}/web/home"
echo "=========================================="
