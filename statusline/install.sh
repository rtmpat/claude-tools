#!/bin/bash
#
# install.sh -- install the context-bar status line into Claude Code
# Part of: github.com/RTMPAT/claude-tools (statusline/)
#
# Copies context-bar.sh and color-preview.sh into ~/.claude/scripts/ and wires
# statusLine into ~/.claude/settings.json. Existing settings are preserved
# (only the statusLine key is set) and a timestamped backup is written first.
# Safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
SETTINGS="$CLAUDE_DIR/settings.json"
TARGET="$SCRIPTS_DIR/context-bar.sh"

# --- dependency checks ---
if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required. Install with: brew install jq" >&2
    exit 1
fi
for dep in curl git; do
    command -v "$dep" >/dev/null 2>&1 || \
        echo "warning: '$dep' not found -- related segments will be blank" >&2
done

# --- copy scripts ---
mkdir -p "$SCRIPTS_DIR"
cp "$SCRIPT_DIR/context-bar.sh" "$TARGET"
cp "$SCRIPT_DIR/color-preview.sh" "$SCRIPTS_DIR/color-preview.sh"
chmod +x "$TARGET" "$SCRIPTS_DIR/color-preview.sh"
echo "installed: $TARGET"

# --- wire settings.json ---
# Store the path in ~ form so the settings file stays portable; Claude Code
# tilde-expands the statusLine command at render time.
settings_cmd="${TARGET/#$HOME/~}"

if [[ -f "$SETTINGS" ]]; then
    backup="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$backup"
    tmp="$(mktemp)"
    jq --arg cmd "$settings_cmd" \
        '.statusLine = {type: "command", command: $cmd}' \
        "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "updated: $SETTINGS (backup: $backup)"
else
    mkdir -p "$CLAUDE_DIR"
    jq -n --arg cmd "$settings_cmd" \
        '{statusLine: {type: "command", command: $cmd}}' \
        > "$SETTINGS"
    echo "created: $SETTINGS"
fi

echo
echo "Done. The status line appears on the next render -- start or continue a"
echo "Claude Code session to see it."
echo "Change the accent color: edit COLOR in $TARGET"
echo "Preview themes:           bash $SCRIPTS_DIR/color-preview.sh"
