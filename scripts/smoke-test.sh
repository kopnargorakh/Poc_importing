#!/bin/bash
set -e

# Smoke Test for Ignition Gateway
# Usage: ./scripts/smoke-test.sh <environment>
# Example: ./scripts/smoke-test.sh dev

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT=$1

if [ -z "$ENVIRONMENT" ]; then
  echo "Error: Environment not specified"
  echo "Usage: ./scripts/smoke-test.sh <environment>"
  exit 1
fi

CONFIG_FILE="$PROJECT_ROOT/config/environments/${ENVIRONMENT}.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found: $CONFIG_FILE"
  exit 1
fi

# Parse configuration
GATEWAY_URL=$(grep "url:" "$CONFIG_FILE" | head -1 | awk '{print $2}')

echo "=========================================="
echo "Smoke Test - $ENVIRONMENT"
echo "=========================================="
echo "Gateway: $GATEWAY_URL"
echo ""

# Wait for gateway to be responsive (in case it was just restarted)
echo "Waiting for gateway to be ready..."
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
  if curl -s -f "${GATEWAY_URL}/StatusPing" > /dev/null 2>&1; then
    echo "Gateway is ready (waited ${WAIT_COUNT}s)"
    break
  fi
  sleep 1
  WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
  echo "⚠ Warning: Gateway did not become ready within ${MAX_WAIT}s"
fi
echo ""

EXIT_CODE=0

# Test 1: Gateway Status Ping
echo "Test 1: Gateway Status Ping"
if curl -s -f "${GATEWAY_URL}/StatusPing" > /dev/null; then
  echo "  ✓ Gateway is responding"
else
  echo "  ✗ Gateway is not responding"
  EXIT_CODE=1
fi

# Test 2: Gateway Home Page
echo "Test 2: Gateway Home Page"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${GATEWAY_URL}/web/home")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
  echo "  ✓ Home page accessible (HTTP $HTTP_CODE)"
else
  echo "  ✗ Home page not accessible (HTTP $HTTP_CODE)"
  EXIT_CODE=1
fi

# Test 3: Check if gateway is licensed (optional)
echo "Test 3: Gateway Status Check"
STATUS_RESPONSE=$(curl -s "${GATEWAY_URL}/StatusPing")
if echo "$STATUS_RESPONSE" | grep -i "running" > /dev/null; then
  echo "  ✓ Gateway status is healthy"
else
  echo "  ⚠ Warning: Could not verify gateway status"
fi

# Test 4: Database connectivity (if configured)
echo "Test 4: Database Connectivity"
# This would require access to Ignition's system API
# For now, we'll skip this test
echo "  ⚠ Database test not implemented (requires gateway API access)"

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo "✓ All smoke tests passed"
else
  echo "✗ Some smoke tests failed"
fi

exit $EXIT_CODE
