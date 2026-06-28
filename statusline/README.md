# context-bar status line

A status line for [Claude Code](https://claude.com/claude-code) that packs your
session state, git status, account usage, and context-window consumption onto a
single line -- with a second line echoing your most recent message.

```
claude-opus-4-7 | 🏷️ my-session | 📁 my-project | 🔀 main (2 files uncommitted, synced 5m ago) | 5h:34% (5p) 7d:12% | 180k of 1m tok
💬 the last thing you typed shows up here
```

## What each segment shows

| Segment | Meaning |
| --- | --- |
| `claude-opus-4-7` | Active model (accent-colored). |
| `🏷️ my-session` | Session name (omitted if unnamed). |
| `📁 my-project` | Current working directory (basename). |
| `🔀 main (...)` | Git branch, uncommitted file count (or the filename when exactly one), and upstream sync state with time since last fetch. Truncates to fit the terminal width. |
| `5h:34% (5p)` | Rolling 5-hour usage and the local time it resets. A `(+$0.42)` appears when extra-usage charges have accrued in the current block. |
| `7d:12%` | Rolling 7-day usage. |
| `180k of 1m tok` | Context-window consumption as an absolute token count (rounded to thousands), against the window size. Colored green (<50%), amber (<85%), red (≥85%) as it climbs. A leading `~` means it's an estimate (no transcript yet). |
| `💬 ...` | Your most recent message, on a second line. |

## Requirements

- **macOS.** The script uses the macOS keychain (`security`) for the usage token
  and BSD `date`/`stat` flags. See [Linux](#linux) below.
- **[`jq`](https://jqlang.github.io/jq/)** -- required. `brew install jq`
- **`curl`**, **`git`** -- for the usage and git segments respectively. Missing
  either just blanks that segment.
- **Claude Code**, which provides the status-line JSON on stdin.

## Install

```bash
bash statusline/install.sh
```

The installer copies `context-bar.sh` and `color-preview.sh` into
`~/.claude/scripts/`, then sets the `statusLine` key in `~/.claude/settings.json`
(preserving every other setting, with a timestamped backup written first). It's
safe to re-run.

The status line appears on the **next render** -- start or continue a Claude Code
session to see it.

### Manual install

1. Copy `context-bar.sh` to `~/.claude/scripts/context-bar.sh` and `chmod +x` it.
2. Add this to `~/.claude/settings.json`:
   ```json
   {
     "statusLine": { "type": "command", "command": "~/.claude/scripts/context-bar.sh" }
   }
   ```

## Customization

Set the accent color near the top of `context-bar.sh`:

```bash
COLOR="blue"   # gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
```

Preview every theme:

```bash
bash ~/.claude/scripts/color-preview.sh
```

## How usage and overage work

- Usage percentages come from the `/api/oauth/usage` endpoint, authenticated with
  your Claude Code OAuth token (read from the keychain, falling back to
  `~/.claude/.credentials.json`). Responses are cached for 60s under
  `~/.claude/cache/` so each render stays fast.
- Reset times are taken from the status-line stdin (`rate_limits.*.resets_at`) and
  rendered in your local timezone.
- The **overage** figure (`+$X.XX`) is the delta in extra-usage credits since the
  current 5-hour block began. The block baseline is tracked in
  `~/.claude/block-state.json`, keyed by the block's reset timestamp, and re-snapshots
  automatically on rollover.

## Troubleshooting

- **Status line is blank or shows an error:** confirm `jq` is installed and on
  `PATH`, then start a fresh session.
- **No usage segment:** the OAuth token couldn't be read, or the request timed out
  (3s budget). The git and context segments still render.
- **Session name shows the old value right after `/rename`:** expected. `/rename`
  doesn't force a re-render; the new name appears on the next turn.
- **Non-default config dir:** the installer honors `CLAUDE_CONFIG_DIR`, but the
  script's internal cache/state paths assume the default `~/.claude`.

### Linux

The script targets macOS and won't run unmodified on Linux: `security` (keychain)
has no equivalent, and the BSD `date -jf`/`date -r` invocations differ from GNU
`date`. A Linux port would need a non-keychain token source and GNU date handling.
Contributions welcome.

## Uninstall

Remove the `statusLine` key from `~/.claude/settings.json` (restore one of the
`settings.json.bak.*` backups the installer made), and optionally delete
`~/.claude/scripts/context-bar.sh` and `~/.claude/scripts/color-preview.sh`.
