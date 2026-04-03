#!/bin/bash
# chezmoi-guard.sh - PreToolUse hook that warns when editing chezmoi-managed files
#
# Intercepts Edit and Write tool calls targeting files under $HOME.
# If the file is managed by chezmoi, warns Claude and asks it to confirm
# with the user before proceeding (suggesting the source file instead).
# If the file is an unmanaged dotfile/config, suggests chezmoi add.
#
# Exit codes:
#   0 - Allow (with optional warning in stdout)
#   2 - Block (not used; we warn instead)

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract file_path from tool_input JSON
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# No file_path? Nothing to check.
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Resolve to absolute path
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(pwd)/$FILE_PATH"
fi

# Only care about files under $HOME
if [[ "$FILE_PATH" != "$HOME"/* && "$FILE_PATH" != "$HOME" ]]; then
  exit 0
fi

# Skip if we're already editing inside the chezmoi source directory
CHEZMOI_SOURCE=$(chezmoi source-path 2>/dev/null || echo "")
if [[ -n "$CHEZMOI_SOURCE" && "$FILE_PATH" == "$CHEZMOI_SOURCE"/* ]]; then
  exit 0
fi

# Check if this file is managed by chezmoi
# Use chezmoi source-path which is faster than listing all managed files
SOURCE_PATH=$(chezmoi source-path "$FILE_PATH" 2>/dev/null || echo "")

if [[ -n "$SOURCE_PATH" ]]; then
  # File IS managed by chezmoi -- warn strongly
  cat <<WARN
CHEZMOI GUARD: The file you are about to edit is managed by chezmoi!

  Target file: $FILE_PATH
  Source file: $SOURCE_PATH

Editing the target file directly means changes will be OVERWRITTEN on the
next "chezmoi apply". You should edit the chezmoi source file instead.

ACTION REQUIRED: Before proceeding, you MUST ask the user which they prefer:
  1. Edit the source file at: $SOURCE_PATH
     (then remind them to run "chezmoi apply" afterward)
  2. Edit the target file directly (the user accepts the risk of overwrite)

Do NOT silently proceed with editing the target file.
WARN
  exit 0
fi

# File is NOT managed by chezmoi. Check if it looks like a dotfile or config.
BASENAME=$(basename "$FILE_PATH")
RELATIVE="${FILE_PATH#"$HOME"/}"

IS_DOTFILE=false
IS_CONFIG=false

# Check for dotfiles
if [[ "$BASENAME" == .* ]]; then
  IS_DOTFILE=true
fi

# Check for common config directories
if [[ "$RELATIVE" == .config/* || "$RELATIVE" == .local/* || \
      "$RELATIVE" == .ssh/* || "$RELATIVE" == Library/Preferences/* || \
      "$RELATIVE" == Library/Application\ Support/* ]]; then
  IS_CONFIG=true
fi

if [[ "$IS_DOTFILE" == true || "$IS_CONFIG" == true ]]; then
  cat <<SUGGEST
CHEZMOI NOTICE: You are editing a dotfile/config that is NOT managed by chezmoi.

  File: $FILE_PATH

If the user wants this file tracked across machines, suggest:
  chezmoi add $FILE_PATH

This will create a managed copy in the chezmoi source directory. No action
needed if the user only wants a local change.
SUGGEST
fi

exit 0
