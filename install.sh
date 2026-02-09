#!/bin/bash
# claude-peon installer
# Installs Peon voice lines as Claude Code hook notifications
set -euo pipefail

INSTALL_DIR="$HOME/.claude/hooks/claude-peon"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== claude-peon installer ==="
echo ""

# --- Prerequisites ---
if [ "$(uname)" != "Darwin" ]; then
  echo "Error: claude-peon requires macOS (uses afplay + AppleScript)"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is required"
  exit 1
fi

if ! command -v afplay &>/dev/null; then
  echo "Error: afplay is required (should be built into macOS)"
  exit 1
fi

if [ ! -d "$HOME/.claude" ]; then
  echo "Error: ~/.claude/ not found. Is Claude Code installed?"
  exit 1
fi

# --- Install files ---
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"/{packs,scripts}
cp -r "$SCRIPT_DIR/packs/"* "$INSTALL_DIR/packs/"
cp "$SCRIPT_DIR/scripts/download-sounds.sh" "$INSTALL_DIR/scripts/"
cp "$SCRIPT_DIR/peon.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/config.json" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/peon.sh"
chmod +x "$INSTALL_DIR/scripts/download-sounds.sh"

# --- Download sounds ---
echo ""
bash "$INSTALL_DIR/scripts/download-sounds.sh" "$INSTALL_DIR" "peon"

# --- Backup existing notify.sh ---
NOTIFY_SH="$HOME/.claude/hooks/notify.sh"
if [ -f "$NOTIFY_SH" ]; then
  cp "$NOTIFY_SH" "$NOTIFY_SH.backup"
  echo ""
  echo "Backed up notify.sh → notify.sh.backup"
fi

# --- Update settings.json ---
echo ""
echo "Updating Claude Code hooks in settings.json..."

/usr/bin/python3 -c "
import json, os, sys

settings_path = '$SETTINGS'
hook_cmd = '$INSTALL_DIR/peon.sh'

# Load existing settings
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault('hooks', {})

peon_hook = {
    'type': 'command',
    'command': hook_cmd,
    'timeout': 10
}

peon_entry = {
    'matcher': '',
    'hooks': [peon_hook]
}

# Events to register
events = ['SessionStart', 'UserPromptSubmit', 'Stop', 'Notification']

for event in events:
    event_hooks = hooks.get(event, [])
    # Remove any existing notify.sh or peon.sh entries
    event_hooks = [
        h for h in event_hooks
        if not any(
            'notify.sh' in hk.get('command', '') or 'peon.sh' in hk.get('command', '')
            for hk in h.get('hooks', [])
        )
    ]
    event_hooks.append(peon_entry)
    hooks[event] = event_hooks

settings['hooks'] = hooks

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print('Hooks registered for: ' + ', '.join(events))
"

# --- Initialize state ---
echo '{}' > "$INSTALL_DIR/.state.json"

# --- Test sound ---
echo ""
echo "Testing sound..."
PACK_DIR="$INSTALL_DIR/packs/peon"
TEST_SOUND=$(ls "$PACK_DIR/sounds/"*.wav 2>/dev/null | head -1)
if [ -n "$TEST_SOUND" ]; then
  afplay -v 0.3 "$TEST_SOUND"
  echo "Sound working!"
else
  echo "Warning: No sound files found. Sounds may not play."
fi

echo ""
echo "=== Installation complete! ==="
echo ""
echo "Config: $INSTALL_DIR/config.json"
echo "  - Adjust volume, toggle categories, switch packs"
echo ""
echo "Uninstall: bash $SCRIPT_DIR/uninstall.sh"
echo ""
echo "Zug zug. Ready to work!"
