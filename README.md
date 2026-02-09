# claude-peon

Warcraft III Peon voice lines as Claude Code notifications. "Work work."

## What it does

Replaces default system sounds with Peon voice lines for Claude Code hook events:

| Event | Sound Category | Example Lines |
|---|---|---|
| Session starts | Greeting | "Ready to work?", "Something need doing?" |
| You send a prompt | Acknowledge | "Work, work.", "Zug zug.", "Dabu." |
| Claude finishes | Complete | "Ready to work?", "Something need doing?" |
| Permission needed | Permission | "Hmm?", "What?" |
| Tool fails | Error | "My tummy feels funny." |
| Rapid prompts (3+ in 10s) | Annoyed | "Me not that kind of orc!", "No time for play." |

Also handles Terminal tab titles and macOS notifications (carried over from the default `notify.sh`).

## Install

```bash
git clone https://github.com/tonysheng/claude-peon.git
cd claude-peon
bash install.sh
```

The installer will:
1. Copy files to `~/.claude/hooks/claude-peon/`
2. Download Peon WAV files (~29 MB ZIP, extracts only Peon sounds)
3. Back up your existing `notify.sh`
4. Register hooks in `~/.claude/settings.json`

## Uninstall

```bash
bash uninstall.sh
```

Removes all hooks and offers to restore your original `notify.sh`.

## Configuration

Edit `~/.claude/hooks/claude-peon/config.json`:

```json
{
  "active_pack": "peon",
  "volume": 0.5,
  "enabled": true,
  "categories": {
    "greeting": true,
    "acknowledge": true,
    "complete": true,
    "error": true,
    "permission": true,
    "resource_limit": true,
    "annoyed": true
  },
  "annoyed_threshold": 3,
  "annoyed_window_seconds": 10
}
```

- **volume**: 0.0–1.0 (passed to `afplay -v`)
- **enabled**: Master kill switch
- **categories**: Toggle individual sound categories
- **annoyed_threshold/window**: How many prompts in N seconds triggers annoyed lines

## Adding character packs

The system supports swappable character packs. To add one:

1. Create `packs/<name>/manifest.json` following the format in `packs/peon/manifest.json`
2. Set `"active_pack": "<name>"` in config.json
3. Run `bash scripts/download-sounds.sh ~/.claude/hooks/claude-peon <name>`

Future pack ideas: Human Peasant ("Job's done!"), Night Elf Wisp, Undead Acolyte.

## Requirements

- macOS (uses `afplay` and AppleScript)
- Claude Code with hooks support
- python3 (for JSON parsing)

## How it works

`peon.sh` is registered as a Claude Code hook for 5 events. On each event it:
1. Reads the JSON event from stdin
2. Maps the event to a sound category
3. Picks a random sound (avoiding immediate repeats)
4. Plays it via `afplay` in the background
5. Updates Terminal tab title via AppleScript
6. Shows macOS notification if Terminal isn't focused

Sound files are not included in the repo — they're downloaded at install time from [The Sounds Resource](https://www.sounds-resource.com/).

## License

MIT — see [LICENSE](LICENSE). Sound files are property of Blizzard Entertainment and are downloaded separately.
