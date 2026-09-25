#!/bin/bash
# tmux-pump.sh — Pump a prompt into Atlas tmux interactive session.
#
# PATH export: ssh non-interactive shells + launchd both lack homebrew PATH.
# tmux lives at /opt/homebrew/bin. Export so this works standalone, not only
# when called by a parent that already exported (morning-brief.sh does, but
# defense-in-depth — don't assume the caller did).
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
#
# Why: 2026-06-15 Anthropic carves programmatic (`claude -p`) usage out of
# subscription into a separate $200/month credit pool. Interactive sessions
# (tmux-attached `claude`, no -p) stay on the subscription, no credit drain.
#
# This wrapper converts a cron task from `claude -p "<prompt>"` (metered)
# into `tmux send-keys -t atlas "<prompt>"` (the existing Atlas tmux interactive
# session runs the work, output reaches the operator via mcp_telegram_send inside
# Atlas's session).
#
# Usage: tmux-pump.sh "<prompt>"
# Exit codes:
#   0  — successfully pumped into Atlas session
#   99 — Atlas tmux session not found (caller should fall back to claude -p)
#   1  — usage error
#
# Per source-code-mining-roadmap (2026-05-29) + 2026-jun15-billing-architecture.

set -e

PROMPT="$1"
TMUX_SESSION="${ATLAS_TMUX_SESSION:_atlas}"
LOG="${TMUX_PUMP_LOG:-$HOME/agent-os/scripts/tmux-pump.log}"

if [ -z "$PROMPT" ]; then
  echo "Usage: $0 <prompt>" >&2
  exit 1
fi

# Use the right log path on whichever machine this runs on
case "$(hostname)" in
  *macbook*|*MacBook*)
    LOG="${TMUX_PUMP_LOG:-$HOME/agent-os/scripts/tmux-pump.log}"
    ;;
esac

echo "[$(date)] pump: '${PROMPT:0:80}' → tmux session '$TMUX_SESSION'" >> "$LOG"

# Check Atlas tmux session exists
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "[$(date)] Atlas tmux session '$TMUX_SESSION' not found — caller should fall back to claude -p" >> "$LOG"
  exit 99
fi

# Inject prompt as user input. Use load-buffer + paste-buffer to handle
# special chars cleanly (single quotes, # markers, etc — send-keys mangles those).
# 2026-08-26 FIX: clear whatever is sitting in Atlas's composer FIRST. If leftover text is
# there (a stray line someone typed, an earlier injection that never submitted), paste-buffer
# CONCATENATES onto it → Atlas receives a mangled prompt and answers conversationally instead of
# running the skill. That is exactly how the 8/26 brief died: Atlas replied "你这条消息截断了".
tmux send-keys -t "$TMUX_SESSION" C-u 2>/dev/null || true
sleep 1

TMP_BUF=$(mktemp)
printf "%s\n" "$PROMPT" > "$TMP_BUF"
tmux load-buffer -b tmux-pump "$TMP_BUF"
tmux paste-buffer -t "$TMUX_SESSION" -b tmux-pump
tmux send-keys -t "$TMUX_SESSION" Enter
rm "$TMP_BUF"

echo "[$(date)] pump: prompt sent, Atlas session will produce output via mcp_telegram_send" >> "$LOG"
exit 0
