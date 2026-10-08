#!/usr/bin/env bash
set -euo pipefail

# Target best-practices.md file path (override via env var TARGET_FILE or first argument, defaults to best-practices.md)
TARGET_FILE="${TARGET_FILE:-${1:-/home/itzuser/IBM/Bob/workspaces/FlowPilot-Lab/.bob/skills/wm-integration-skills/skills/flow/references/best-practices.md}}"

# Remote source URL for csv-practices.md
SOURCE_URL="https://raw.githubusercontent.com/dave-pemberton-ibm/TechXchangeLab2409/main/csv-practices.md"

# Determine directory of target file and ensure it exists
TARGET_DIR="$(dirname "$TARGET_FILE")"
if [ "$TARGET_DIR" != "." ] && [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
fi

# Fetch csv-practices.md (use local file if present and curl fails)
TEMP_FILE="$(mktemp)"
trap 'rm -f "$TEMP_FILE"' EXIT

echo "Fetching csv-practices.md..."
if curl -fsSL "$SOURCE_URL" -o "$TEMP_FILE" 2>/dev/null; then
    echo "Downloaded csv-practices.md from remote repository."
elif [ -f "$(dirname "$0")/csv-practices.md" ]; then
    echo "Remote fetch failed, using local csv-practices.md."
    cp "$(dirname "$0")/csv-practices.md" "$TEMP_FILE"
elif [ -f "./csv-practices.md" ]; then
    echo "Remote fetch failed, using ./csv-practices.md."
    cp "./csv-practices.md" "$TEMP_FILE"
else
    echo "Error: Failed to download csv-practices.md from $SOURCE_URL and no local copy found." >&2
    exit 1
fi

# If target file exists, has content, and does not end with a newline, ensure proper separation
if [ -s "$TARGET_FILE" ]; then
    if [ "$(tail -c 1 "$TARGET_FILE" | wc -l)" -eq 0 ]; then
        echo "" >> "$TARGET_FILE"
    fi
    echo "" >> "$TARGET_FILE"
fi

# Append csv-practices.md to the target file
cat "$TEMP_FILE" >> "$TARGET_FILE"

echo "Successfully merged csv-practices.md into $TARGET_FILE"
