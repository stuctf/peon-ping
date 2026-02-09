#!/bin/bash
# claude-peon: Warcraft III Peon voice lines for Claude Code hooks
# Replaces notify.sh — handles sounds, tab titles, and notifications
set -uo pipefail

PEON_DIR="${CLAUDE_PEON_DIR:-$HOME/.claude/hooks/claude-peon}"
CONFIG="$PEON_DIR/config.json"
STATE="$PEON_DIR/.state.json"

INPUT=$(cat)

# Debug log (comment out for quiet operation)
# echo "$(date): peon hook — $INPUT" >> /tmp/claude-peon-debug.log

# --- Load config ---
eval "$(/usr/bin/python3 -c "
import json, sys
try:
    c = json.load(open('$CONFIG'))
except:
    c = {}
print('ENABLED=' + repr(str(c.get('enabled', True)).lower()))
print('VOLUME=' + repr(str(c.get('volume', 0.5))))
print('ACTIVE_PACK=' + repr(c.get('active_pack', 'peon')))
print('ANNOYED_THRESHOLD=' + repr(str(c.get('annoyed_threshold', 3))))
print('ANNOYED_WINDOW=' + repr(str(c.get('annoyed_window_seconds', 10))))
cats = c.get('categories', {})
for cat in ['greeting','acknowledge','complete','error','permission','resource_limit','annoyed']:
    print('CAT_' + cat.upper() + '=' + repr(str(cats.get(cat, True)).lower()))
" 2>/dev/null)"

[ "$ENABLED" = "false" ] && exit 0

# --- Resolve TTY for this session ---
resolve_tty() {
  local pid=$$
  while [ "$pid" -gt 1 ] 2>/dev/null; do
    local tty_info
    tty_info=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -n "$tty_info" ] && [ "$tty_info" != "??" ]; then
      echo "$tty_info"
      return 0
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  return 1
}

MY_TTY=$(resolve_tty)

# --- Parse event fields ---
eval "$(/usr/bin/python3 -c "
import sys, json
d = json.load(sys.stdin)
print('EVENT=' + repr(d.get('hook_event_name', '')))
print('NTYPE=' + repr(d.get('notification_type', '')))
print('CWD=' + repr(d.get('cwd', '')))
" <<< "$INPUT" 2>/dev/null)"

PROJECT="${CWD##*/}"
[ -z "$PROJECT" ] && PROJECT="claude"

# --- Check annoyed state (rapid prompts) ---
check_annoyed() {
  /usr/bin/python3 -c "
import json, time, sys, os

state_file = '$STATE'
now = time.time()
window = float('$ANNOYED_WINDOW')
threshold = int('$ANNOYED_THRESHOLD')

try:
    state = json.load(open(state_file))
except:
    state = {}

timestamps = state.get('prompt_timestamps', [])
timestamps = [t for t in timestamps if now - t < window]
timestamps.append(now)

state['prompt_timestamps'] = timestamps
os.makedirs(os.path.dirname(state_file) or '.', exist_ok=True)
json.dump(state, open(state_file, 'w'))

if len(timestamps) >= threshold:
    print('annoyed')
else:
    print('normal')
" 2>/dev/null
}

# --- Pick random sound from category, avoiding immediate repeats ---
pick_sound() {
  local category="$1"
  /usr/bin/python3 -c "
import json, random, sys, os

pack_dir = '$PEON_DIR/packs/$ACTIVE_PACK'
manifest = json.load(open(os.path.join(pack_dir, 'manifest.json')))
state_file = '$STATE'

try:
    state = json.load(open(state_file))
except:
    state = {}

category = '$category'
sounds = manifest.get('categories', {}).get(category, {}).get('sounds', [])
if not sounds:
    sys.exit(1)

last_played = state.get('last_played', {})
last_file = last_played.get(category, '')

# Filter out last played (if more than one option)
candidates = sounds if len(sounds) <= 1 else [s for s in sounds if s['file'] != last_file]
pick = random.choice(candidates)

# Update state
last_played[category] = pick['file']
state['last_played'] = last_played
json.dump(state, open(state_file, 'w'))

sound_path = os.path.join(pack_dir, 'sounds', pick['file'])
print(sound_path)
" 2>/dev/null
}

# --- Determine category and tab state ---
CATEGORY=""
STATUS=""
MARKER=""
NOTIFY=""
MSG=""

case "$EVENT" in
  SessionStart)
    CATEGORY="greeting"
    STATUS="ready"
    ;;
  UserPromptSubmit)
    # No sound normally — user just hit enter, they know.
    # Exception: annoyed easter egg fires if they're spamming prompts.
    if [ "$CAT_ANNOYED" = "true" ]; then
      MOOD=$(check_annoyed)
      if [ "$MOOD" = "annoyed" ]; then
        CATEGORY="annoyed"
      fi
    fi
    STATUS="working"
    ;;
  Stop)
    # No sound — Stop fires after each completion step in multi-tool chains.
    # Notification(idle_prompt) is the real "Claude is done" signal.
    STATUS="done"
    MARKER="● "
    ;;
  Notification)
    if [ "$NTYPE" = "permission_prompt" ]; then
      CATEGORY="permission"
      STATUS="needs approval"
      MARKER="● "
      NOTIFY=1
      MSG="$PROJECT — A tool is waiting for your permission"
    elif [ "$NTYPE" = "idle_prompt" ]; then
      CATEGORY="complete"
      STATUS="done"
      MARKER="● "
      NOTIFY=1
      MSG="$PROJECT — Ready for your next instruction"
    else
      exit 0
    fi
    ;;
  # PostToolUseFailure — no sound. Claude retries on its own.
  *)
    exit 0
    ;;
esac

# --- Check if category is enabled ---
CAT_VAR="CAT_$(echo "$CATEGORY" | tr '[:lower:]' '[:upper:]')"
CAT_ENABLED="${!CAT_VAR:-true}"
[ "$CAT_ENABLED" = "false" ] && CATEGORY=""

# --- Build tab title ---
TITLE="${MARKER}${PROJECT}: ${STATUS}"

# --- Set tab title via TTY-matched AppleScript ---
if [ -n "$MY_TTY" ] && [ -n "$TITLE" ]; then
  osascript <<EOF &
tell application "Terminal"
  set targetTTY to "/dev/$MY_TTY"
  repeat with w in windows
    repeat with t in tabs of w
      if tty of t is targetTTY then
        set custom title of t to "$TITLE"
        set title displays custom title of t to true
        set title displays device name of t to false
        set title displays shell path of t to false
        set title displays window size of t to false
        set title displays file name of t to false
      end if
    end repeat
  end repeat
end tell
EOF
fi

# --- Play sound ---
if [ -n "$CATEGORY" ]; then
  SOUND_FILE=$(pick_sound "$CATEGORY")
  if [ -n "$SOUND_FILE" ] && [ -f "$SOUND_FILE" ]; then
    afplay -v "$VOLUME" "$SOUND_FILE" &
  fi
fi

# --- Smart notification: only when Terminal is NOT frontmost ---
if [ -n "$NOTIFY" ]; then
  FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
  if [ "$FRONTMOST" != "Terminal" ]; then
    osascript -e "display notification \"$MSG\" with title \"$TITLE\"" &
  fi
fi

wait
exit 0
