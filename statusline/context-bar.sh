#!/bin/bash
#
# context-bar.sh -- Claude Code status line
# Part of: github.com/RTMPAT/claude-tools (statusline/)
#
# Renders one status line:
#   model | session | dir | git branch + status | usage % + resets + overage $ | context tokens
# plus a second line echoing your most recent message.
#
# Requirements: macOS, jq, curl, git. Install and customization: see README.md.

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
# Preview all options: bash color-preview.sh
COLOR="blue"

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'  # explicit gray for default text
C_BAR_EMPTY='\033[38;5;238m'
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;  # gray: all same color
esac

# Force UTF-8 character handling so ${#var} counts code points (not bytes) and
# the display-width math below stays correct regardless of the caller's locale.
# Only affects character classification, not number/time formatting. macOS
# always ships this locale.
export LC_CTYPE=en_US.UTF-8

input=$(cat)

# Extract model, directory, cwd, session name, and rate-limit resets
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')

# Mode indicators shown right after the model name:
#   effort level (e.g. "high"), then F if fast_mode is on (else _),
#   then T if extended thinking is on (else _).
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
[[ "$(echo "$input" | jq -r '.fast_mode // false')" == "true" ]] && fast_char="F" || fast_char="_"
[[ "$(echo "$input" | jq -r '.thinking.enabled // false')" == "true" ]] && think_char="T" || think_char="_"
mode_flags=""
[[ -n "$effort_level" ]] && mode_flags+=" ${effort_level}"
mode_flags+=" ${fast_char} ${think_char}"

# Claude Code version, prepended to the second (last-message) line.
version=$(echo "$input" | jq -r '.version // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Project root and the cwd expressed relative to it, for the second line.
# When cwd IS the project root, show "."; if cwd is outside the project
# (e.g. an added dir), fall back to the absolute cwd.
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
if [[ -n "$project_dir" && "$cwd" == "$project_dir"* ]]; then
    rel_cwd="${cwd#"$project_dir"}"
    rel_cwd="${rel_cwd#/}"
    [[ -z "$rel_cwd" ]] && rel_cwd="."
else
    rel_cwd="$cwd"
fi
session_name=$(echo "$input" | jq -r '.session_name // .session.name // .name // empty')
reset_5h_raw=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
# used_percentage can exceed 100 when in overage — the gate for showing
# overage cost. The /oauth/usage API caps utilization at 100.
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

# Format a reset timestamp (epoch seconds OR ISO 8601) as "5p" or "9a",
# rendered in the user's local timezone. Returns empty on parse failure so
# the caller can omit the parenthetical.
format_reset() {
    local raw="$1" epoch ts
    [[ -z "$raw" ]] && return 1
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        epoch="$raw"
    else
        # ISO 8601 is conventionally UTC; strip sub-second + 'Z' and parse
        # with an explicit +0000 offset so BSD date treats it as UTC.
        local clean="${raw%.*}"
        clean="${clean%Z}"
        epoch=$(date -jf '%Y-%m-%dT%H:%M:%S%z' "${clean}+0000" +%s 2>/dev/null)
    fi
    [[ -z "$epoch" ]] && return 1
    ts=$(date -r "$epoch" +'%-I%p' 2>/dev/null)
    [[ -z "$ts" ]] && return 1
    ts=$(echo "$ts" | tr '[:upper:]' '[:lower:]')
    printf '%s' "${ts%m}"
}

# Display-column width of an ANSI-free UTF-8 string. With UTF-8 LC_CTYPE set
# above, ${#s} counts code points; the emoji this script emits render two
# columns wide but count as a single code point, so add one per occurrence.
# (🏷️ is base + U+FE0F variation selector = two code points already spanning
# its two columns, so it is intentionally absent here.) A slight miscount for
# exotic emoji in a session name only nudges the git_status truncation point,
# which carries its own margin — it cannot reintroduce rendering corruption.
dwidth() {
    local s="$1" w=${#1} rest g
    for g in '📁' '🔀' '💬'; do
        rest="$s"
        while [[ "$rest" == *"$g"* ]]; do
            rest="${rest#*"$g"}"
            ((w++))
        done
    done
    printf '%s' "$w"
}

# Get git branch, uncommitted file count, and sync status
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        # Count uncommitted files
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')

        # Check sync status with upstream
        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            # Get last fetch time
            fetch_head="$cwd/.git/FETCH_HEAD"
            fetch_ago=""
            if [[ -f "$fetch_head" ]]; then
                fetch_time=$(stat -f %m "$fetch_head" 2>/dev/null || stat -c %Y "$fetch_head" 2>/dev/null)
                if [[ -n "$fetch_time" ]]; then
                    now=$(date +%s)
                    diff=$((now - fetch_time))
                    if [[ $diff -lt 60 ]]; then
                        fetch_ago="<1m ago"
                    elif [[ $diff -lt 3600 ]]; then
                        fetch_ago="$((diff / 60))m ago"
                    elif [[ $diff -lt 86400 ]]; then
                        fetch_ago="$((diff / 3600))h ago"
                    else
                        fetch_ago="$((diff / 86400))d ago"
                    fi
                fi
            fi

            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)
            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                if [[ -n "$fetch_ago" ]]; then
                    sync_status="synced ${fetch_ago}"
                else
                    sync_status="synced"
                fi
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead} ahead"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind} behind"
            else
                sync_status="${ahead} ahead, ${behind} behind"
            fi
        else
            sync_status="no upstream"
        fi

        # Build git status string
        if [[ "$file_count" -eq 0 ]]; then
            git_status="(0 files uncommitted, ${sync_status})"
        elif [[ "$file_count" -eq 1 ]]; then
            # Show the actual filename when only one file is uncommitted
            single_file=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | head -1 | sed 's/^...//')
            git_status="(${single_file} uncommitted, ${sync_status})"
        else
            git_status="(${file_count} files uncommitted, ${sync_status})"
        fi
    fi
fi

# Get transcript path (used only for the last-message echo at the bottom now).
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Context window size and current occupancy both come straight from stdin's
# .context_window object (Claude Code computes these itself). current_usage's
# cache_read_input_tokens already includes the cached system prompt, tools, and
# memory, so this is accurate and needs no transcript parsing.
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

# Format context size: "1m" for >=1M (one-decimal if not exact), "Nk" otherwise.
if [[ $max_context -ge 1000000 ]]; then
    if (( max_context % 1000000 == 0 )); then
        max_label="$((max_context / 1000000))m"
    else
        whole=$((max_context / 1000000))
        tenth=$(( (max_context % 1000000) / 100000 ))
        max_label="${whole}.${tenth}m"
    fi
else
    max_label="$((max_context / 1000))k"
fi

# 20k baseline: system prompt + tools + memory + dynamic framing
baseline=20000

# Current context occupancy = sum of all four current_usage token fields.
# current_usage is null before the first API call and right after /compact;
# in that case fall back to the baseline estimate (flagged with a "~").
context_length=$(echo "$input" | jq -r '
    .context_window.current_usage // {} |
    ((.input_tokens // 0) + (.output_tokens // 0) +
     (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
')
context_length=${context_length:-0}

if [[ "$context_length" -gt 0 ]]; then
    pct=$((context_length * 100 / max_context))
    pct_prefix=""
else
    pct=$((baseline * 100 / max_context))
    pct_prefix="~"
fi

[[ $pct -gt 100 ]] && pct=100

# Absolute used-token count in thousands (rounded) for display, e.g. "123k".
# Falls back to the baseline estimate when no transcript tokens are available
# (pct_prefix already carries the "~" estimate marker in that case).
used_tokens=${context_length:-0}
[[ "$used_tokens" -gt 0 ]] || used_tokens=$baseline
used_label="$(( (used_tokens + 500) / 1000 ))k"

# Glanceable threshold coloring on the token text: green <50%, yellow
# <85%, red >=85% of the context window. Muted hues to match the palette.
if [[ $pct -lt 50 ]]; then
    C_PCT='\033[38;5;71m'
elif [[ $pct -lt 85 ]]; then
    C_PCT='\033[38;5;179m'
else
    C_PCT='\033[38;5;167m'
fi

ctx="${C_PCT}${pct_prefix}${used_label}${C_GRAY} of ${max_label} tok"

# Fetch usage/quota (cached for 60s to avoid slowdowns).
# Cache format (v3): "PCT_5H|PCT_7D|USED_CREDITS" — percentages + extra-usage
# monthly credits (cents, float). Reset times resolved at render time from
# stdin-provided resets_at, so cache stays valid across window rollovers.
# Kept under ~/.claude/cache/ (not /tmp/) so it survives reboots and sits
# alongside the block-state file — keeping all status-line state co-located.
usage_cache="$HOME/.claude/cache/usage-v3"
usage_raw=""
cache_max_age=60

fetch_usage() {
    local token response five_hour seven_day used_credits
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    [[ -z "$token" ]] && token=$(jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null)
    [[ -z "$token" ]] && return 1
    response=$(curl -s --max-time 3 \
        -H "Authorization: Bearer ${token}" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Content-Type: application/json" \
        -H "User-Agent: claude-code-statusline" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || return 1
    five_hour=$(printf '%s' "$response" | jq -r '
        if .five_hour then "\(.five_hour.utilization | round)%" else empty end
    ' 2>/dev/null)
    seven_day=$(printf '%s' "$response" | jq -r '
        if .seven_day then "\(.seven_day.utilization | round)%" else empty end
    ' 2>/dev/null)
    used_credits=$(printf '%s' "$response" | jq -r '
        if (.extra_usage.is_enabled // false) and (.extra_usage.used_credits != null)
        then (.extra_usage.used_credits | tostring) else empty end
    ' 2>/dev/null)
    if [[ -n "$five_hour" || -n "$seven_day" ]]; then
        printf '%s|%s|%s' "$five_hour" "$seven_day" "$used_credits"
    fi
}

# Use fresh cache if available. Always keep the last known cache content as
# a fallback so a transient OAuth failure doesn't make usage blink off for
# the whole cache window.
cached_content=""
[[ -f "$usage_cache" ]] && cached_content=$(cat "$usage_cache")

cache_fresh=false
if [[ -f "$usage_cache" ]]; then
    cache_time=$(stat -f %m "$usage_cache" 2>/dev/null || stat -c %Y "$usage_cache" 2>/dev/null)
    now_ts=$(date +%s)
    [[ $((now_ts - cache_time)) -lt $cache_max_age ]] && cache_fresh=true
fi

if $cache_fresh; then
    usage_raw="$cached_content"
else
    usage_raw=$(fetch_usage)
    if [[ -n "$usage_raw" ]]; then
        printf '%s' "$usage_raw" > "$usage_cache" 2>/dev/null
    else
        # Fetch failed — fall back to last cached value (may be stale, but
        # usage numbers change slowly enough that this is preferable to
        # showing nothing).
        usage_raw="$cached_content"
    fi
fi

# Overage-this-block indicator. Uses the only reliable "billing occurred"
# signal: the delta in extra_usage.used_credits (cents) since the current
# 5h block started. State persisted in ~/.claude/block-state.json, keyed by
# the stdin five_hour.resets_at (an epoch int that identifies the block).
#
# On block rollover (resets_at changed), snapshot current credits as the new
# baseline. Within a block, overage = used_credits - credits_at_block_start.
# First-ever run initializes baseline to current credits so delta reads 0
# until the next fetch registers new charges.
overage_text=""
IFS='|' read -r _p5h _p7d used_credits_now <<< "$usage_raw"
if [[ -n "$reset_5h_raw" && -n "$used_credits_now" ]]; then
    state_file="$HOME/.claude/block-state.json"
    stored_resets=""
    stored_baseline=""
    if [[ -f "$state_file" ]]; then
        stored_resets=$(jq -r '.block_resets_at // empty' "$state_file" 2>/dev/null)
        stored_baseline=$(jq -r '.credits_at_block_start // empty' "$state_file" 2>/dev/null)
    fi
    if [[ "$reset_5h_raw" != "$stored_resets" ]]; then
        # New block (or first run): snapshot current credits as baseline.
        jq -nc --arg r "$reset_5h_raw" --arg c "$used_credits_now" \
            '{block_resets_at: ($r | tonumber), credits_at_block_start: ($c | tonumber)}' \
            > "$state_file" 2>/dev/null
        stored_baseline="$used_credits_now"
    fi
    if [[ -n "$stored_baseline" ]]; then
        overage_text=$(awk -v cur="$used_credits_now" -v base="$stored_baseline" \
            'BEGIN {
                delta_cents = cur - base;
                if (delta_cents <= 0) exit 0;
                printf "+$%.2f", delta_cents / 100
            }')
    fi
fi

# Assemble the display string, annotating each bucket with its reset time
# when stdin provides one: "5h:34% (5p) 7d:12% (9a)"
usage_text=""
if [[ -n "$usage_raw" ]]; then
    IFS='|' read -r p5h p7d _ <<< "$usage_raw"
    parts=()
    if [[ -n "$p5h" ]]; then
        label=$(format_reset "$reset_5h_raw")
        seg="5h:${p5h}"
        [[ -n "$label" ]] && seg+=" (${label})"
        [[ -n "$overage_text" ]] && seg+=" (${overage_text})"
        parts+=("$seg")
    fi
    [[ -n "$p7d" ]] && parts+=("7d:${p7d}")
    usage_text="${parts[*]}"
fi

# ---------- Dynamic truncation of git_status to fit terminal width ----------
# Reconstructs the visible-width equivalent of every OTHER segment, subtracts
# from terminal width, and caps git_status to what is left. If the output
# composition changes below, update plain_fixed/plain_tail to match so the
# budget stays accurate.
plain_fixed="${model}${mode_flags}"
[[ -n "$session_name" ]] && plain_fixed+=" | 🏷️ ${session_name}"
[[ -n "$branch" ]] && plain_fixed+=" | 🔀 ${branch} "

plain_tail=""
[[ -n "$usage_text" ]] && plain_tail+=" | ${usage_text}"
plain_tail+=" | ${pct_prefix}${used_label} of ${max_label} tok"

# Terminal width: prefer live $COLUMNS, fall back to tput, then a safe default.
term_cols="${COLUMNS:-}"
[[ -z "$term_cols" ]] && term_cols=$(tput cols 2>/dev/null || true)
[[ -z "$term_cols" ]] && term_cols=120

# Budget for git_status, measured in true display columns via dwidth() so the
# emoji are accounted for instead of guessed at. Safety of 3 is a small
# edge-wrap margin (was 8 to absorb emoji undercounting, now handled directly).
budget=$((term_cols - $(dwidth "$plain_fixed") - $(dwidth "$plain_tail") - 3))

if [[ -n "$branch" && ${#git_status} -gt $budget ]]; then
    if [[ $budget -ge 4 ]]; then
        git_status="${git_status:0:$((budget - 2))}…)"
    else
        git_status=""
    fi
fi

# Build output: Model | SessionName | Branch (uncommitted) | Usage | Context
# (cwd moved to the second line, shown relative to the project root)
output="${C_ACCENT}${model}${C_GRAY}${mode_flags}"
[[ -n "$session_name" ]] && output+=" | 🏷️ ${session_name}"
if [[ -n "$branch" ]]; then
    output+=" | 🔀 ${branch}"
    [[ -n "$git_status" ]] && output+=" ${git_status}"
fi
[[ -n "$usage_text" ]] && output+=" | ${usage_text}"
output+=" | ${ctx}${C_RESET}"

printf '%b\n' "$output"

# Get user's last message (text only, not tool results, skip unhelpful messages)
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    # Calculate visible length (without ANSI codes) - 10 chars for bar + content
    plain_output="${model}${mode_flags}"
    [[ -n "$session_name" ]] && plain_output+=" | 🏷️ ${session_name}"
    if [[ -n "$branch" ]]; then
        plain_output+=" | 🔀 ${branch}"
        [[ -n "$git_status" ]] && plain_output+=" ${git_status}"
    fi
    [[ -n "$usage_text" ]] && plain_output+=" | ${usage_text}"
    plain_output+=" | ${pct_prefix}${used_label} of ${max_label} tok"
    max_len=${#plain_output}
    last_user_msg=$(jq -rs '
        # Messages to skip (not useful as context)
        def is_unhelpful:
            startswith("[Request interrupted") or
            startswith("[Request cancelled") or
            . == "";

        [.[] | select(.type == "user") |
         select(.message.content | type == "string" or
                (type == "array" and any(.[]; .type == "text")))] |
        reverse |
        map(.message.content |
            if type == "string" then .
            else [.[] | select(.type == "text") | .text] | join(" ") end |
            gsub("\n"; " ") | gsub("  +"; " ")) |
        map(select(is_unhelpful | not)) |
        first // ""
    ' < "$transcript_path" 2>/dev/null)

    if [[ -n "$last_user_msg" ]]; then
        # Second-line prefix: version | project_dir | cwd-relative-to-project
        prefix_parts=()
        [[ -n "$version" ]] && prefix_parts+=("$version")
        [[ -n "$project_dir" ]] && prefix_parts+=("🏠 $project_dir")
        prefix_parts+=("📍 $rel_cwd")
        line2_prefix=""
        for p in "${prefix_parts[@]}"; do
            [[ -n "$line2_prefix" ]] && line2_prefix+=" | "
            line2_prefix+="$p"
        done
        line2_prefix+=" | "
        avail=$((max_len - ${#line2_prefix}))
        if [[ $avail -gt 3 && ${#last_user_msg} -gt $avail ]]; then
            echo "${line2_prefix}💬 ${last_user_msg:0:$((avail - 3))}..."
        else
            echo "${line2_prefix}💬 ${last_user_msg}"
        fi
    fi
fi
