#!/usr/bin/env bash
set -euo pipefail

# Target best-practices.md file path (override via env var TARGET_FILE or first argument, defaults to best-practices.md)
TARGET_FILE="${TARGET_FILE:-${1:-/home/itzuser/IBM/Bob/workspaces/FlowPilot-Lab/.bob/skills/wm-integration-skills/skills/flow/references/best-practices.md}}"

# Remote source URL for upd-practices.md
SOURCE_URL="https://raw.githubusercontent.com/dave-pemberton-ibm/TechXchangeLab2409/main/upd-practices.md"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║        📄 Best Practices Update Script           ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  🎯 Target file : $TARGET_FILE"
echo "  🌐 Source URL  : $SOURCE_URL"
echo ""

# Determine directory of target file and ensure it exists
TARGET_DIR="$(dirname "$TARGET_FILE")"
if [ "$TARGET_DIR" != "." ] && [ ! -d "$TARGET_DIR" ]; then
    echo "  📁 Creating directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

# Fetch csv-practices.md (use local file if present and curl fails)
TEMP_FILE="$(mktemp)"
trap 'rm -f "$TEMP_FILE"' EXIT

echo "  ⬇️  Fetching updates..."
if curl -fsSL "$SOURCE_URL" -o "$TEMP_FILE" 2>/dev/null; then
    echo "  ✅ Downloaded updates from remote repository."
elif [ -f "$(dirname "$0")/csv-practices.md" ]; then
    echo "  ⚠️  Remote fetch failed — falling back to local copy next to script."
    cp "$(dirname "$0")/csv-practices.md" "$TEMP_FILE"
elif [ -f "./csv-practices.md" ]; then
    echo "  ⚠️  Remote fetch failed — falling back to ./csv-practices.md."
else
    echo ""
    echo "  ❌ Error: Failed to download csv-practices.md from:"
    echo "     $SOURCE_URL"
    echo "     No local copy found either. Cannot continue." >&2
    echo ""
    exit 1
fi

# If target file exists, has content, and does not end with a newline, ensure proper separation
if [ -s "$TARGET_FILE" ]; then
    echo "  📝 Target file exists — appending with proper separation."
    if [ "$(tail -c 1 "$TARGET_FILE" | wc -l)" -eq 0 ]; then
        echo "" >> "$TARGET_FILE"
    fi
    echo "" >> "$TARGET_FILE"
else
    echo "  📝 Target file is new or empty — writing fresh content."
fi

# Append csv-practices.md to the target file
cat "$TEMP_FILE" >> "$TARGET_FILE"

echo ""
echo "  ✅ Successfully merged csv-practices.md into $TARGET_FILE"
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║                  🎉 All done!                    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
