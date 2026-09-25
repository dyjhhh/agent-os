#!/bin/bash
# Weekly brief pipeline — runs Monday 6 PM CT via launchd
# Runs 4 skills sequentially, captures output, sends each via Telegram (guaranteed delivery)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
cd $HOME/agent-os

# Catch-up guard (RunAtLoad fallback): only fire if last successful run was >5 days ago.
# Friday 22:00 cron is primary; this guard lets RunAtLoad rescue missed Fridays
# (laptop asleep) without spamming on every boot/reload.
SENTINEL=$HOME/agent-os/scripts/.weekly-brief-last-success
if [ -f "$SENTINEL" ]; then
  AGE_DAYS=$(( ( $(date +%s) - $(stat -f %m "$SENTINEL") ) / 86400 ))
  if [ "${FORCE_WEEKLY:-0}" != "1" ] && [ "$AGE_DAYS" -lt 5 ]; then
    echo "$(date) — weekly brief ran ${AGE_DAYS}d ago, skip catch-up" >> $HOME/agent-os/scripts/weekly-brief.log
    exit 0
  fi
fi

# No MacBook mutex — matches morning-brief.sh policy. Ping check is unreliable
# (MacBook stays pingable during sleep). If 429 RPM hit, run_skill catches
# exit_code 75 and the next cron/RunAtLoad cycle retries. Better silent retry
# than silent skip.

BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"
LOG="$HOME/agent-os/scripts/weekly-brief.log"

source $HOME/agent-os/reliability/claude-guard.sh
acquire_lock "weekly-brief"

TOOLS="Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch"

# Send to Telegram via the canonical telegram-send.py: it does Markdown→HTML
# (md_to_html), UTF-8-safe chunking, and HTML-tag balancing. This REPLACES the old
# inline `sed` converter + byte-based `cut -c` chunking, which split multi-byte
# Chinese mid-character (mojibake) and duplicated the converter. One source of truth.
send_to_telegram() {
  # 2026-08-29 HARD RULE #9 guard: a system-level error string is NOT a report. On 8/29 the
  # claude -p fallback died at max-turns and the raw "Error: Reached max turns (40)" was sent
  # to her Telegram as if it were the Weekly Deep Dive. Errors go to the log + handoff, never her.
  # (caller signature: send_to_telegram "$content" "$label" — content is $1, label is $2)
  if echo "$1" | head -3 | grep -qiE "^Error:|Reached max turns|rate.?limit|invalid_grant|command not found"; then
    echo "[$(date)] SUPPRESSED error-as-content send for ${2:-?}: $(echo "$1" | head -1)" >> "$LOG"
    echo "| $(date +%F) | weekly-brief→Forge | 🔴 fallback 产物是错误文本(已拦截未发她): ${2:-?} → $(echo "$1" | head -1 | cut -c1-80) | OPEN |" >> "$HOME/.claude/projects/-project/memory/agent-handoffs.md" 2>/dev/null
    return 1
  fi
  local raw="$1"
  local label="$2"
  # Prepend the label as a markdown bold header; telegram-send.py converts it to <b>.
  printf '**📋 %s**\n\n%s' "$label" "$raw" \
    | python3 $HOME/agent-os/agents/telegram-send.py "$BOT_TOKEN" "$CHAT_ID" 2>>"$LOG"
}

run_skill() {
  local skill="$1"
  local label="$2"
  local turns="$3"
  local file_pattern="$4"  # NEW: glob for cron-results file fallback (e.g. "weekly-deep-dive-*")

  # 2026-jun15-billing 拳1 (tmux-pump): try delegating to Atlas tmux interactive
  # session FIRST (subscription pool, no credit drain). Atlas will mcp_telegram_send
  # the result. Skip the safe_claude -p path if pump succeeds.
  # 2026-06-20 FIX (injection≠completion): baseline BEFORE pump so we can VERIFY Atlas actually delivered.
  local last_reply="$HOME/.claude/channels/telegram/last-reply.txt"
  local pre_pump=$(stat -f %m "$last_reply" 2>/dev/null || echo 0)
  echo "[$(date)] Attempting tmux-pump → Atlas tmux session 'atlas' for ${skill}..." >> "$LOG"
  local SEND_CLAUSE_TEXT="After generating, push the complete output (clearly labeled '${label}') to the operator's Telegram via the mcp__plugin_telegram_telegram__send tool (chat_id ${CHAT_ID})."
  # 2026-08-29 FIX (stale-prompt conflict): the claude -p path below already honors the operator's
  # 2026-08-22 ruling (sub-task outputs are SILENT — folded into the deep dive), but this pump
  # prompt still ordered a Telegram send. Atlas hit the contradiction on 8/29 and correctly followed
  # the ruling + the skill's own "DO NOT send Telegram" delivery rule, which then made the
  # send-gated receipt unwritable and forced a pointless claude -p re-run. Make the pump prompt
  # match the ruling per skill.
  local silent=0
  echo "$label" | grep -qi "competitor" && silent=1
  local delivery_clause receipt_clause
  if [ "$silent" = 1 ]; then
    delivery_clause="DELIVERY (the operator 2026-08-22 ruling — this is a SILENT sub-task): do NOT send this to Telegram. Its content is folded into the Weekly Deep Dive main report; an independent message = the same content hitting her two or three times. Save the full report to ~/agent-os/memory/cron-results/ and log a one-line receipt in the daily log. The ONLY reason to message her is a scan failure or a genuine 🔴/🟡 she must act on."
  else
    delivery_clause="${SEND_CLAUSE_TEXT} the operator is on phone, NOT watching this tmux pane. FORMATTING (HARD RULE #6): send as CLEAN PLAIN TEXT — do NOT use markdown (**bold**, ### headers, - bullets). The plugin sends plain text, so markdown shows as literal '**' junk. Structure with emoji (•, ✅, 🔴, 📌), line breaks, and ALL-CAPS labels instead. End by confirming delivery."
  fi
  local pump_prompt="[cron-trigger weekly-brief] Run ${skill} skill. ⏱️ TIME-BOX (2026-07-18, from the 7/18 double-run): SINGLE-PASS ONLY, deliver within 6 minutes — do NOT fan out to parallel research subagents during this pump. This cron falls back to claude -p at the 6-min mark, so a slow fan-out = DOUBLE full run (2x tokens) + a competing variant (exactly what happened 7/18; the single-pass fallback version scored 10/10 with the operator, so fan-out buys nothing here). If you finish delivery early and genuinely have additive research ideas, do them AFTER delivery is confirmed, silently, per HARD RULE #7. ${delivery_clause}"
  # 2026-08-29 FIX (same family as the 8/26 morning-brief false positive): last-reply mtime is a
  # PROXY that advances on ANY message Atlas sends, including a one-line ACK. On 8/29 both skills were
  # marked "VERIFIED delivered" 11 and 12 seconds after injection (a deep dive cannot finish in 12s)
  # and no cron-results file was ever written. Require a RECEIPT Atlas writes only after a real send.
  local receipt="$HOME/.weekly-delivered-$(echo "$skill" | tr -cd 'a-z-')-$(date +%F)"
  : > "$receipt" 2>/dev/null; /bin/rm -f "$receipt" 2>/dev/null
  if [ "$silent" = 1 ]; then
    pump_prompt="${pump_prompt} ONLY after the cron-results report file is written, run this exact command as your receipt: date +%s > ${receipt} — the cron verifies that file and re-runs this via claude -p if it is missing. (No Telegram send is expected for this skill.)"
  else
    pump_prompt="${pump_prompt} ONLY after the send tool returns success, run this exact command as your receipt: date +%s > ${receipt} — the cron verifies that file and re-runs this via claude -p if it is missing."
  fi
  $HOME/agent-os/agents/tmux-pump.sh "$pump_prompt" >>"$LOG" 2>&1
  local pump_exit=$?
  if [ $pump_exit -eq 0 ]; then
    # VERIFY Atlas delivered (last-reply advances OR the cron-results file appears fresh) within 6min —
    # the old code returned on INJECTION alone, so the weekly deep-dive silently failed for 3 WEEKS.
    # Loop early-exits the moment delivery is detected; 6min is just the max-wait before claude -p fallback.
    local delivered=0
    for _w in $(seq 1 36); do
      sleep 10
      # BOTH must hold: Atlas wrote the receipt (skill ran AND send succeeded) AND last-reply
      # advanced (something actually reached her Telegram). Either alone is a proxy.
      if [ "$silent" = 1 ]; then
        # Silent sub-task: nothing reaches Telegram by design, so last-reply can never advance.
        # Real completion = Atlas wrote the receipt AND a fresh cron-results report exists.
        if [ -f "$receipt" ] && [ -n "$file_pattern" ] && \
           [ -n "$(find "$HOME"/agent-os/memory/cron-results -name "${file_pattern}.md" -mmin -60 2>/dev/null | head -1)" ]; then
          delivered=1; break
        fi
      elif [ -f "$receipt" ] && [ "$(stat -f %m "$last_reply" 2>/dev/null || echo 0)" -gt "$pre_pump" ]; then
        delivered=1; break
      fi
    done
    if [ "$delivered" = 1 ]; then
      echo "[$(date)] ${skill} delegated + VERIFIED delivered via Atlas tmux. Done." >> "$LOG"
      return 0
    fi
    echo "[$(date)] ${skill} injected but Atlas did NOT deliver within 6min — falling back to claude -p." >> "$LOG"
  fi
  echo "[$(date)] tmux-pump exit=$pump_exit (or no delivery) for ${skill} — falling back to programmatic claude -p." >> "$LOG"

  echo "[$(date)] Running ${skill}..." >> "$LOG"
  local output=$(safe_claude -p "${skill}" --allowedTools "$TOOLS" --max-turns "$turns" 2>&1)
  local exit_code=$?

  echo "=== ${label} ===" >> "$LOG"
  echo "$output" >> "$LOG"
  echo "[$(date)] ${skill} exit=$exit_code output_len=${#output}" >> "$LOG"

  if [ $exit_code -eq 75 ]; then
    echo "[$(date)] ${skill}: Rate limited — skipped, will retry next cycle." >> "$LOG"
    return
  fi

  if [ $exit_code -ne 0 ]; then
    # HARD RULE #9 (2026-08-29): a system-level failure is not hers to fix — log + handoff,
    # let brief-delivery-watchdog / the next catch-up retry. No ❌ ping to her phone.
    echo "| $(date +%F) | weekly-brief→Forge | 🔴 ${label} fallback exit=$exit_code(未发她,待重试/人修) | OPEN |" >> "$HOME/.claude/projects/-project/memory/agent-handoffs.md" 2>/dev/null
    return
  fi

  # If output is short (<1500 chars) AND file_pattern given, prefer reading the file.
  # This handles skills that save full content to disk and only print a path/confirmation.
  local content="$output"
  if [ -n "$file_pattern" ] && [ ${#output} -lt 1500 ]; then
    local latest_file=$(ls -t ~/agent-os/memory/cron-results/${file_pattern}.md 2>/dev/null | head -1)
    if [ -n "$latest_file" ] && [ -f "$latest_file" ]; then
      local file_age_min=$(( ($(date +%s) - $(stat -f %m "$latest_file" 2>/dev/null || stat -c %Y "$latest_file")) / 60 ))
      if [ "$file_age_min" -lt 60 ]; then
        echo "[$(date)] ${skill}: output short (${#output}c), reading file $latest_file (${file_age_min}min old)" >> "$LOG"
        content=$(cat "$latest_file")
      fi
    fi
  fi

  # ── EVAL FRESHNESS GATE (2026-06-21, SHADOW) — only the dated Weekly Deep Dive ──
  # Same as morning-brief: run the deterministic eval on the produced brief; log PASS/BLOCK +
  # flag stale to live-pulse, but NEVER alter the send (false-block must not cost her the brief).
  # Scoped to weekly-deep-dive (the dated deliverable); competitor-intel is not freshness-gated.
  if [ -n "$content" ] && echo "$skill" | grep -q "weekly-deep-dive"; then
    local _ga; _ga=$(mktemp /tmp/wb-gate.XXXXXX)
    printf '%s\n' "$content" > "$_ga"
    local _go; _go=$(python3 "$HOME/agent-os/evals/skill-eval.py" --gate --skill weekly-brief --artifact "$_ga" 2>&1)
    local _grc=$?
    echo "[$(date)] EVAL GATE rc=$_grc :: $(echo "$_go" | grep -E 'BLOCK|PASS' | tr '\n' ' ')" >> "$LOG"
    [ "$_grc" -eq 2 ] && echo "$(date '+%F %T') weekly deep-dive eval gate FLAGGED (shadow, still sent): $(echo "$_go" | grep -i block | head -1)" >> "$HOME/agent-os/memory/live-pulse.md" 2>/dev/null
    rm -f "$_ga"
  fi
  # 2026-08-22 the operator ruling: intermediate/sub-task outputs are SILENT — their content is
  # already folded into the main Weekly Deep Dive report. Independent Telegram messages
  # only on failure / needs-human (the failure branch above already logs; main report still sends).
  if [ -n "$content" ]; then
    if echo "$label" | grep -qi "competitor"; then
      echo "[$(date)] ${label}: silent mode — content saved to cron-results, folded into deep dive, NOT sent separately" >> "$LOG"
    else
      if send_to_telegram "$content" "$label"; then
        # The claude -p fallback path must ALSO leave a delivery receipt, or the sentinel
        # never gets stamped and the RunAtLoad catch-up re-runs (and re-sends) a good week.
        date +%s > "$receipt"
      fi
    fi
  fi
}

# 2026-09-12 (Atlas handoff 9/12): the fixed `sleep 60` between the two pumps was a guess. When
# competitor-intel keeps Atlas busy past its receipt (it talks after writing it), the deep-dive prompt
# lands mid-turn and is lost — the 8/29 failure shape again, one minute later. Wait for Atlas's pane to
# be genuinely idle instead: the same "esc to interrupt" working indicator atlas-stuck-detector trusts,
# 2 consecutive idle polls (15s apart), capped. ATLAS_PANE_CMD overrides the capture for tests.
wait_atlas_idle() {
  local max="${1:-1200}" waited=0 idle_streak=0 tail8
  local cmd="${ATLAS_PANE_CMD:-tmux capture-pane -t ${ATLAS_TMUX_SESSION:-atlas} -p}"
  if [ -z "$ATLAS_PANE_CMD" ] && ! tmux has-session -t "${ATLAS_TMUX_SESSION:-atlas}" 2>/dev/null; then
    echo "[$(date)] wait_atlas_idle: no Atlas tmux session — nothing to wait for" >> "$LOG"; return 0
  fi
  while [ "$waited" -lt "$max" ]; do
    tail8=$(eval "$cmd" 2>/dev/null | tail -8)
    if echo "$tail8" | grep -qiE "esc to interrupt|Thinking…|Running…|Do you want to proceed"; then
      idle_streak=0
    else
      idle_streak=$((idle_streak + 1))
      if [ "$idle_streak" -ge 2 ]; then echo "[$(date)] wait_atlas_idle: Atlas idle after ${waited}s" >> "$LOG"; return 0; fi
    fi
    sleep 15; waited=$((waited + 15))
  done
  echo "[$(date)] wait_atlas_idle: Atlas still busy after ${max}s — proceeding anyway (receipt check catches a lost pump)" >> "$LOG"
  return 1
}

# Run pipeline sequentially
# 4th arg = file pattern in ~/agent-os/memory/cron-results/ for content fallback when stdout is short
# 2026-08-29 FIX: pattern was "venue-competitor-intel-*", but the skill writes
# competitor-intel-YYYY-MM-DD.md (21 files on disk, 0 matching the old glob), so the
# short-output file fallback silently never fired for this skill. Match reality.
run_skill "/venue-competitor-intel" "VENUE Competitor Intel" 20 "competitor-intel-*"
# 2026-08-29: never inject the second skill on top of a session still working the first.
# On 8/29 both were pumped 12s apart; the deep-dive prompt landed mid-turn and was lost.
# 2026-09-12: fixed 60s → poll for a genuinely idle pane (see wait_atlas_idle above).
wait_atlas_idle 1200
# Flagship in-flight marker: hook-telegram-verbosity.sh exempts long messages while this is fresh
# (<120 min), so deep-dive chunks 2..n (no header) are not mistaken for an over-long news card.
touch "$HOME/.weekly-flagship-in-flight"
run_skill "/weekly-deep-dive" "Weekly Deep Dive" 150 "weekly-deep-dive-*"
/bin/rm -f "$HOME/.weekly-flagship-in-flight"

echo "[$(date)] Weekly pipeline complete." >> "$LOG"
# 2026-08-29 FIX: the sentinel used to be touched UNCONDITIONALLY. On 8/29 a phantom run
# (both skills "VERIFIED delivered" in ~11s, nothing actually produced) still stamped it —
# which then made the RunAtLoad catch-up refuse to retry for 5 days. Only a run that produced
# a real delivery receipt may claim success.
if ls "$HOME"/.weekly-delivered-*-"$(date +%F)" >/dev/null 2>&1; then
  touch "$SENTINEL"
  echo "[$(date)] sentinel stamped (a real delivery receipt exists)" >> "$LOG"
else
  echo "[$(date)] sentinel NOT stamped — no delivery receipt this run; catch-up stays armed" >> "$LOG"
fi

# Completion notice RETIRED 2026-08-22 (the operator: pure system-level success messages don't reach her).
# Replaced by a silent connectivity probe so NOTICE_EXIT keeps its "pipeline finished + Telegram
# reachable" semantics for the liveness heartbeat below. Failures still surface via claude-guard/log.
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" > /dev/null 2>&1
NOTICE_EXIT=$?
# Liveness heartbeat (2026-06-20) — emit ok ONLY after the completion notice is
# confirmed delivered (reached end of pipeline = it genuinely ran), mirroring
# morning-brief's confirmed-delivery gate. curl exit 0 = Telegram accepted POST.
_HB="$HOME/agent-os/reliability/cron-heartbeat.sh"
if [ "$NOTICE_EXIT" -eq 0 ]; then
  bash "$_HB" ok com.operator.weekly-brief 2>/dev/null
else
  bash "$_HB" fail com.operator.weekly-brief "completion-notice curl exit=$NOTICE_EXIT" 2>/dev/null
fi
