# context-bar status line

A status line for [Claude Code](https://claude.com/claude-code) that packs your
session state, git status, account usage, and context-window consumption onto a
first line -- with a second line carrying the version, your project and working
directories, and your most recent message.

```
claude-opus-4-8 high _ T | 🏷️ my-session | 🔀 main (2 files uncommitted, synced 5m ago) | 5h:34% (5p) 7d:12% | 180k of 1m tok
2.1.193 | 🏠 /Users/me/Work/Code | 📍 my-project/subdir | 🔒 net:none fs:default esc:on auto:on | 💬 the last thing you typed shows up here
```

## What each segment shows

### First line

| Segment | Meaning |
| --- | --- |
| `claude-opus-4-8` | Active model (accent-colored). |
| `high _ T` | Mode flags: reasoning effort level, then `F` if fast mode is on (else `_`), then `T` if extended thinking is on (else `_`). |
| `🏷️ my-session` | Session name (omitted if unnamed). |
| `🔀 main (...)` | Git branch, uncommitted file count (or the filename when exactly one), and upstream sync state with time since last fetch. Truncates to fit the terminal width. |
| `5h:34% (5p)` | Rolling 5-hour usage and the local time it resets. A `(+$0.42)` appears when extra-usage charges have accrued in the current block. |
| `7d:12%` | Rolling 7-day usage. |
| `180k of 1m tok` | Context-window consumption as an absolute token count (rounded to thousands), against the window size. Computed from `context_window.current_usage` (all four token fields). Colored green (<50%), amber (<85%), red (≥85%) as it climbs. A leading `~` means it's an estimate (no usage data yet). |

### Second line

| Segment | Meaning |
| --- | --- |
| `2.1.193` | Claude Code version. |
| `🏠 /Users/me/Work/Code` | Project root (the workspace's `project_dir`). |
| `📍 my-project/subdir` | Current working directory, shown relative to the project root (`.` when at the root). |
| `🔒 net:none fs:default esc:on auto:on` | Sandbox policy detail. `net:` = allowed-domain count or `none`; `fs:` = custom writable-path count or `default`; `esc:` = `allowUnsandboxedCommands` (always shown; defaults to `on`); `auto:` = `autoAllowBashIfSandboxed`; `fail:` = `failIfUnavailable` (shown only when set). Anything other than `sandbox.enabled: true` — explicitly disabled *or* unconfigured — shows `🔓 sandbox disabled`. |
| `💬 ...` | Your most recent message. |

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

## How sandbox detection works

Claude Code does **not** include sandbox state in the status-line stdin JSON, so
the script resolves it the same way the app does: it reads `sandbox.*` from each
settings scope and merges them in precedence order (low → high, later wins):

1. User — `~/.claude/settings.json`
2. Project — `<project_dir>/.claude/settings.json`
3. Project-local — `<project_dir>/.claude/settings.local.json`
4. Managed — `/Library/Application Support/ClaudeCode/managed-settings.json`
   (macOS) or `/etc/claude-code/managed-settings.json` (Linux)

Booleans (`enabled`, `allowUnsandboxedCommands`, …) take the highest-precedence
scope that sets them; array policy (`network.allowedDomains`,
`filesystem.allowWrite`/`allowRead`) is summed across all scopes. `project_dir`
comes from stdin, so the right project `.claude/` is always used.

**Caveat:** this reflects the *configured* policy for the project, not a guarantee
about every command. Individual Bash calls can still run outside the sandbox when
`allowUnsandboxedCommands` is set or a command opts out explicitly — so read
`🔒 sandbox` as "sandbox is on for this project," not "this exact command is
sandboxed."

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
