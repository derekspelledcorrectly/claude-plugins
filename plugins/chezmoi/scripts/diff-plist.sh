#!/bin/bash
# diff-plist.sh - Compare binary plist files between chezmoi source and target
#
# Usage:
#   bash ${CLAUDE_PLUGIN_ROOT}/scripts/diff-plist.sh <relative-path-to-plist>
#   Example: bash ${CLAUDE_PLUGIN_ROOT}/scripts/diff-plist.sh Library/Preferences/com.knollsoft.Rectangle.plist
#
# This script:
# 1. Resolves the source plist file via chezmoi source-path
# 2. Converts both source and target plists to XML format
# 3. Shows a unified diff of the changes

set -euo pipefail

if [[ $# -ne 1 ]]; then
	printf "Usage: %s <relative-path-to-plist>\n" "$0"
	printf "Example: %s Library/Preferences/com.knollsoft.Rectangle.plist\n" "$0"
	exit 1
fi

TARGET_PATH="$1"
HOME_DIR="$HOME"
TARGET_FULL="$HOME_DIR/$TARGET_PATH"

# Check if target file exists
if [[ ! -f "$TARGET_FULL" ]]; then
	printf "Error: Target file not found at %s\n" "$TARGET_FULL"
	exit 1
fi

# Resolve the source file using chezmoi's canonical path resolution
if ! SOURCE_FILE=$(chezmoi source-path "$TARGET_FULL" 2>/dev/null); then
	printf "Error: %s is not managed by chezmoi\n" "$TARGET_PATH"
	printf "Try running: chezmoi managed | grep -i %s\n" "$(basename "$TARGET_PATH")"
	exit 1
fi

printf "Comparing plist files:\n"
printf "  Source: %s\n" "$SOURCE_FILE"
printf "  Target: %s\n" "$TARGET_FULL"
printf "\n"

# Create temporary directory for XML conversions
TEMP_DIR="${TMPDIR:-/tmp}/plist-diff-$$"
mkdir -p "$TEMP_DIR"

# Convert both files to XML
SOURCE_XML="$TEMP_DIR/source.xml"
TARGET_XML="$TEMP_DIR/target.xml"

plutil -convert xml1 -o "$SOURCE_XML" "$SOURCE_FILE"
plutil -convert xml1 -o "$TARGET_XML" "$TARGET_FULL"

# Show diff
printf "Differences (- source, + target):\n"
printf '%s\n' "================================="
diff -u "$SOURCE_XML" "$TARGET_XML" || true

# Cleanup
rm -rf "$TEMP_DIR"
