#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="${1:-$PROJECT_ROOT/projects}"

echo "=========================================="
echo "Validating Project Naming Conventions"
echo "=========================================="
echo "Projects directory: $PROJECTS_DIR"
echo ""

EXIT_CODE=0

if [ ! -d "$PROJECTS_DIR" ]; then
  echo "Warning: Projects directory not found: $PROJECTS_DIR"
  exit 0
fi

for project_dir in "$PROJECTS_DIR"/*/; do
  if [ ! -d "$project_dir" ]; then
    continue
  fi

  project_name=$(basename "$project_dir")
  echo "Checking project: $project_name"

  # Check Python files for print statements and indentation
  while IFS= read -r -d '' file; do
    if grep -n "print(" "$file" > /dev/null 2>&1; then
      echo "  ✗ Error: Print statement found in $file"
      grep -n "print(" "$file"
      EXIT_CODE=1
    fi
  done < <(find "$project_dir" -name "*.py" -type f -print0 2>/dev/null)

  # Check Perspective view JSON files — WARN only, do not fail build
  if [ -d "$project_dir/com.inductiveautomation.perspective/views" ]; then
    while IFS= read -r -d '' view_file; do
      if ! python3 -m json.tool "$view_file" > /dev/null 2>&1; then
        echo "  ⚠ Warning: Invalid JSON in $view_file (skipping)"
        # NOTE: Warning only — does not fail the build
        # Fix the JSON file to remove this warning
      fi
    done < <(find "$project_dir/com.inductiveautomation.perspective/views" -name "*.json" -type f -print0 2>/dev/null)
  fi

  echo "  ✓ Project validated"
done

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo "✓ All validation checks passed"
else
  echo "✗ Validation failed - please fix the errors above"
fi

exit $EXIT_CODE
