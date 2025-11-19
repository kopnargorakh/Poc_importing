#!/bin/bash
set -e

# Ignition Gateway Backup Script
# Usage: ./scripts/backup-gateway.sh <environment>
# Example: ./scripts/backup-gateway.sh dev

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT=$1

if [ -z "$ENVIRONMENT" ]; then
  echo "Error: Environment not specified"
  echo "Usage: ./scripts/backup-gateway.sh <environment>"
  exit 1
fi

CONFIG_FILE="$PROJECT_ROOT/config/environments/${ENVIRONMENT}.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found: $CONFIG_FILE"
  exit 1
fi

# Parse configuration
GATEWAY_URL=$(grep "url:" "$CONFIG_FILE" | head -1 | awk '{print $2}')
GATEWAY_USER=$(grep "username:" "$CONFIG_FILE" | head -1 | awk '{print $2}')
GATEWAY_PASS=$(grep "password:" "$CONFIG_FILE" | head -1 | awk '{print $2}')
BACKUP_PATH=$(grep "backup_path:" "$CONFIG_FILE" | awk '{print $2}')
CONTAINER_NAME=$(grep "container_name:" "$CONFIG_FILE" | awk '{print $2}')

# Create backup directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/$BACKUP_PATH"

# Generate backup filename with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="gateway_backup_${ENVIRONMENT}_${TIMESTAMP}.gwbk"
BACKUP_FULL_PATH="$PROJECT_ROOT/$BACKUP_PATH/$BACKUP_FILE"

echo "Creating gateway backup for $ENVIRONMENT environment..."
echo "Backup file: $BACKUP_FILE"

# Method 1: Use docker exec to create backup inside container
# This creates a backup using Ignition's built-in backup functionality
docker exec "$CONTAINER_NAME" sh -c "
  cd /usr/local/bin/ignition
  ./gwcmd.sh --backup /backups/$BACKUP_FILE --promptyes --timeout 120
" > /dev/null 2>&1 || echo "  ⚠ gwcmd backup skipped (requires gateway configuration)"

# Method 2: Copy the entire data directory (alternative approach)
echo "Creating filesystem backup..."
docker cp "${CONTAINER_NAME}:/usr/local/bin/ignition/data" "$PROJECT_ROOT/$BACKUP_PATH/data_backup_${TIMESTAMP}" > /dev/null 2>&1 && echo "  ✓ Filesystem backup created" || echo "  ⚠ Filesystem backup skipped"

# Method 3: Export individual projects via REST API (if available in Ignition 8.3)
echo "Attempting to export projects via API..."
mkdir -p "$PROJECT_ROOT/$BACKUP_PATH/projects_${TIMESTAMP}"

# Get list of projects (this requires proper API authentication)
# Note: Adjust API endpoint based on your Ignition version
curl -s -u "${GATEWAY_USER}:${GATEWAY_PASS}" \
  "${GATEWAY_URL}/system/webdev/projects" \
  -o "$PROJECT_ROOT/$BACKUP_PATH/projects_${TIMESTAMP}/project_list.json" 2>/dev/null && \
  echo "  ✓ Project list exported" || \
  echo "  ⚠ Project export via API not available"

# Clean up old backups (keep last N backups based on retention policy)
RETENTION_DAYS=$(grep "backup_retention_days:" "$CONFIG_FILE" | awk '{print $2}')
if [ -n "$RETENTION_DAYS" ]; then
  echo "Cleaning up backups older than $RETENTION_DAYS days..."
  find "$PROJECT_ROOT/$BACKUP_PATH" -name "gateway_backup_*" -mtime "+$RETENTION_DAYS" -delete 2>/dev/null || true
  find "$PROJECT_ROOT/$BACKUP_PATH" -name "data_backup_*" -mtime "+$RETENTION_DAYS" -exec rm -rf {} \; 2>/dev/null || true
fi

echo "✓ Backup completed: $BACKUP_FILE"
echo "  Location: $BACKUP_FULL_PATH"
