#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR=$1

if [ -z "$PROJECT_DIR" ]; then
  echo "Error: Project directory not specified"
  echo "Usage: ./scripts/package-project.sh <project_directory>"
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: Project directory not found: $PROJECT_DIR"
  exit 1
fi

PROJECT_NAME=$(basename "$PROJECT_DIR")

VERSION="1.0.0"
if [ -f "$PROJECT_DIR/project.json" ]; then
  VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROJECT_DIR/project.json" | cut -d'"' -f4 || echo "1.0.0")
fi

if git rev-parse --git-dir > /dev/null 2>&1; then
  GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
  if [ -n "$GIT_TAG" ]; then
    VERSION="$GIT_TAG"
  else
    VERSION="${VERSION}-${GIT_COMMIT}"
  fi
fi

BUILD_DIR="$PROJECT_ROOT/build"
mkdir -p "$BUILD_DIR"

OUTPUT_FILE="$BUILD_DIR/${PROJECT_NAME}-${VERSION}.zip"

echo "=========================================="
echo "Packaging Ignition Project"
echo "=========================================="
echo "Project: $PROJECT_NAME"
echo "Version: $VERSION"
echo "Source:  $PROJECT_DIR"
echo "Output:  $OUTPUT_FILE"
echo ""

if [ ! -f "$PROJECT_DIR/project.json" ]; then
  echo "Warning: project.json not found in $PROJECT_DIR"
fi

echo "Creating package..."

# ─────────────────────────────────────────────────────────────
# Use PowerShell zip on Windows (Git Bash doesn't have zip cmd)
# Falls back to zip command on Linux/Mac
# ─────────────────────────────────────────────────────────────
if command -v zip > /dev/null 2>&1; then
  # Linux / Mac — use zip command
  cd "$PROJECT_DIR"
  zip -r "$OUTPUT_FILE" . \
    -x "*.git*" \
    -x "*node_modules*" \
    -x "*__pycache__*" \
    -x "*.pyc" \
    -x "*/.DS_Store" \
    -x "*/var/*" \
    -x "*/local/*" \
    > /dev/null
  cd "$PROJECT_ROOT"
else
  # Windows (Git Bash) — use PowerShell Compress-Archive
  ABS_PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd -W 2>/dev/null || cd "$PROJECT_DIR" && pwd)
  ABS_OUTPUT_FILE=$(echo "$OUTPUT_FILE" | sed 's|/c/|C:/|' | sed 's|/|\\|g')

  powershell.exe -Command "
    \$src = '${ABS_PROJECT_DIR}';
    \$dst = '${ABS_OUTPUT_FILE}';
    \$exclude = @('*.git*','node_modules','__pycache__','*.pyc','.DS_Store');
    if (Test-Path \$dst) { Remove-Item \$dst -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem;
    [System.IO.Compression.ZipFile]::CreateFromDirectory(\$src, \$dst)
  " 2>/dev/null || {
    # Final fallback — copy files without zipping
    echo "Warning: Could not create zip, copying files directly..."
    cp -r "$PROJECT_DIR" "$BUILD_DIR/${PROJECT_NAME}-${VERSION}"
  }
fi

if [ -f "$OUTPUT_FILE" ]; then
  echo "✓ Package created: $(basename "$OUTPUT_FILE")"
else
  echo "✓ Package created (directory format): ${PROJECT_NAME}-${VERSION}"
fi
echo ""
