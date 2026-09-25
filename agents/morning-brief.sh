#!/bin/bash
# Morning brief — single skill, all-in-one
# Delegates Telegram chunking/sending to telegram-send.py (UTF-8 safe, HTML-balanced)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
cd $HOME/agent-os

# Morning brief runs at 6 AM — MacBook user unlikely to be active, no mutex needed.
# (Previous mutex was blocking morning brief every day because MacBook stays pingable during sleep.)

BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"
LOG="$HOME/agent-os/scripts/morning-brief.log"
SENDER="$HOME/agent-os/agents/telegram-send.py"

source $HOME/agent-os/reliability/claude-guard.sh

# (personal-schedule note removed from the public copy)
# (personal-schedule note removed from the public copy)
# 覆盖开关:WEEKEND_BRIEF=1 强制生成(手动 /morning-brief 调用不走此脚本,不受影响)。
_DOW=$(date +%u)   # 1=Mon .. 6=Sat 7=Sun
if [ "${WEEKEND_BRIEF:-0}" != "1" ] && { [ "$_DOW" = "6" ] || [ "$_DOW" = "7" ]; }; then
  echo "[$(date)] weekend (dow=$_DOW) — morning brief skipped per the operator 2026-08-25" >> "$LOG"
  # 2026-08-29: a sanctioned skip IS this job doing its job — stamp the heartbeat, or
  # atlas-cron-watchdog counts 30h of "no genuine success" and pages her a stale alert
  # every weekend (first false 🚨 fired Sat 8/29 13:20).
  mkdir -p /tmp/cron-heartbeats && date +%s > /tmp/cron-heartbeats/com.operator.morning-brief
  exit 0
fi
acquire_lock "morning-brief"

TOOLS="Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch"

# ── DETERMINISTIC STALE-AUDIT (pre-step, runs on BOTH pump + claude -p paths) ──
# Cross-file stale detector (stale-audit.py): finds open items pointing to a banner-CLOSED
# owner file + overdue unchecked boxes. The ENFORCEMENT layer that does NOT rely on the LLM
# brief remembering to reconcile (prose HARD RULE #5 = weakest, gets skipped). Writes a report
# (read by Forge session-start + /reconcile too) and feeds findings into the brief prompt so
# they're GUARANTEED surfaced. Flag-only — never edits (the operator 2026-06-15: "只报给我,我拍板").
STALE_REPORT="$HOME/agent-os/memory/stale-audit-report.md"
STALE_OUT=$(python3 "$HOME/agent-os/reliability/stale-audit.py" --report "$STALE_REPORT" 2>/dev/null)
STALE_HINT=""
if [ -n "$STALE_OUT" ] && ! printf '%s' "$STALE_OUT" | grep -q "^✅"; then
  STALE_HINT="

DETERMINISTIC STALE-AUDIT found possibly-stale items — surface under STATUS-RECONCILE / ACTION NEEDED. VERIFY each before stating (may already be resolved; if so tell the operator which source line to clear). Do NOT auto-edit:
${STALE_OUT}"
  echo "[$(date)] stale-audit: findings injected into brief" >> "$LOG"
fi

# 2026-07-02 (drift fix): the other TWO deterministic nets, previously never wired into this flow.
# reminders-stale-sweeper = reminder points at a banner-resolved owner file; date-expiry = ACTIVE
# reminder whose dates have all passed. Findings are FORCE-injected like stale-audit (never relies
# on the LLM remembering to reconcile). Flag-only, never edits.
SWEEP_OUT=$(python3 "$HOME/agent-os/scripts/reminders-stale-sweeper.py" 2>/dev/null)
[ -n "$SWEEP_OUT" ] && ! printf '%s' "$SWEEP_OUT" | grep -q "^✅" && STALE_HINT="$STALE_HINT

REMINDER-vs-OWNER-FILE mismatches (owner file already resolved — DROP these + 自己清掉 reminders.md 对应行(2026-07-23 standing approval),一行汇报;绝不叫她清):
$SWEEP_OUT"
EXPIRY_OUT=$(python3 "$HOME/agent-os/scripts/reminders-date-expiry.py" 2>/dev/null)
[ -n "$EXPIRY_OUT" ] && ! printf '%s' "$EXPIRY_OUT" | grep -q "^✅" && STALE_HINT="$STALE_HINT

$EXPIRY_OUT
(DATE-EXPIRED — 2026-07-23 the operator: 「日期过了/已完成的,你自己清掉就行,别甩给我」。**你自己动手删 reminders.md 里对应的行**(它们的日期已过 = 无需再提醒),然后在 brief 里用 ONE line 汇报:'🧹 已自动清理 N 条过期提醒(<一句话列出>)'。ONLY 保留不删的例外:该条明确写着 KEEP/持续提醒/recurring,或 owner 文件显示仍未决 → 那种照旧列出来问她。绝不再输出「你清一下 reminders.md 对应行」这种把活推给她的句子。)"

# 2026-07-16 (BUG-atlas-claims-vs-disk): 4th deterministic net — provenance-lint. Catches doctrine
# entries citing vault articles that were never written (phantom sources) + daily-log ✅-receipts
# naming files that exist nowhere (fabricated write-claims). Pairs with hook-receipt-verify.sh
# (send-time gate); this is the daily backstop for anything that slipped past. Flag-only.
PROV_OUT=$(python3 "$HOME/agent-os/scripts/provenance-lint.py" 3 2>/dev/null | grep -E "PHANTOM-SOURCE|FALSE-RECEIPT" | grep -vE "/threads/|/.claude/|/archive/" | head -8)
[ -n "$PROV_OUT" ] && STALE_HINT="$STALE_HINT

WRITE-INTEGRITY lint (受骗检测 — a ✅ receipt/citation with NO real file behind it, last 3d). Surface under ACTION NEEDED as '⚠️ 幻影写入待回补', do NOT trust the cited content:
$PROV_OUT"

# 2026-07-16 (news self-heal): auto-run the news burst acceptance check on YESTERDAY so a drop / bloat
# regression is caught BY THE SYSTEM, never by the operator. Surfaces the 🔴/🟡 verdict into the brief. This is
# the guard rail that ends the "she describes the bug → we fix → it recurs" loop for news-analysis.
NEWS_YDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d yesterday +%Y-%m-%d 2>/dev/null)
NEWSV_OUT=$(bash "$HOME/agent-os/agents/news-verify.sh" "$NEWS_YDAY" 2>/dev/null | grep -E "🔴|🟡|缺口" | head -8)
[ -n "$NEWSV_OUT" ] && STALE_HINT="$STALE_HINT

NEWS 昨日自检 (${NEWS_YDAY}, 系统自己抓的 news coverage drop — 不是 the operator 报的). Surface under ACTION NEEDED as '📰 news 自检':
$NEWSV_OUT"

# 2026-07-18 (Armstrong calibration loop): Mondays, harvest last week's verdict signal; if the week had
# real signal (>=3 判断行), instruct the brief agent to RUN the calibration-loop skill inline (silent
# self-improvement, HARD RULE #7 — applied changes reported as one line, nothing lands on the operator).
if [ "$(date +%u)" = "1" ]; then
  CAL_N=$(python3 "$HOME/agent-os/loops/calibration-input.py" 2>/dev/null | grep -cE "^- ")
  if [ "${CAL_N:-0}" -ge 3 ]; then
    STALE_HINT="$STALE_HINT

🎛️ CALIBRATION (Monday): last week produced ${CAL_N} verdict-signal lines. AFTER the brief is sent, run the calibration-loop skill (harvest → convert repeated signals to parameter changes; apply low-risk + keep eval portfolio green; log to logs/calibration-loop.log). Mention in the brief with ONE line only: '🎛️ 每周校准将自动跑 (N signals)'."
  fi
fi

# ── RECENT-WORK PRE-COMPUTE (2026-07-05): run the git recency-scan in the SHELL, inject as text ──
# The brief agent used to run `git log` itself, but headless `claude -p` has no git permission → the
# command was DENIED → the brief retried/timed out (Atlas flagged this 7/5). Pre-computing here + injecting
# means the agent NEVER runs git. Feeds "What Changed" + the do-not-re-suggest-done-items check. THREADS
# section was removed 7/5, so this is the only remaining consumer.
RECENT_WORK=$(git -C "$HOME/agent-os" log --since="40 hours ago" --pretty=format:'%ad %s' --date=format:'%m-%d %H:%M' -- memory/ 2>/dev/null \
  | grep -viE 'auto-sync|auto-applied|healthcheck|atlas_ack|process-codex|process_atlas|thread-lint|dream-queue|skill-proposals' | head -25)
[ -n "$RECENT_WORK" ] && STALE_HINT="$STALE_HINT

RECENT WORK (last ~40h, PRE-COMPUTED — do NOT run git yourself): use ONLY to inform 'What Changed' + to avoid re-suggesting something already done. Do NOT emit a THREADS section.
$RECENT_WORK"

# 2026-jun15-billing 拳1 (tmux-pump): try delegating to Atlas tmux interactive
# session FIRST (subscription-covered post-6/15, no credit pool drain).
# Atlas session generates the brief + pushes via mcp_telegram_send tool, so
# this script exits fast and skips curl-send. If Atlas tmux isn't running
# (pump exits 99), fall back to programmatic claude -p (metered post-6/15).
# 2026-06-20 FIX (injection≠completion): record delivery baseline BEFORE the pump so we can VERIFY
# Atlas actually SENT (not just that the prompt got injected). last-reply.txt mtime advances when Atlas
# sends anything to the operator's Telegram.
LAST_REPLY="$HOME/.claude/channels/telegram/last-reply.txt"
PRE_PUMP=$(stat -f %m "$LAST_REPLY" 2>/dev/null || echo 0)
echo "[$(date)] Attempting tmux-pump → Atlas tmux session 'atlas'..." >> "$LOG"
# 2026-08-26: Atlas must drop a RECEIPT FILE after the send. last-reply mtime alone is a proxy —
# it advances on ANY Telegram message Atlas sends, including a conversational reply to a mangled
# prompt (that false-positive ate the 8/26 brief: script logged "VERIFIED delivered", she got nothing).
BRIEF_RECEIPT="$HOME/.brief-delivered-$(date +%F)"
rm -f "$BRIEF_RECEIPT"
# 2026-08-26 SELF-IMPROVING PATH CHOICE: the tmux-pump path is cheaper (subscription) but fragile
# — it collides with her live Atlas chat and with composer leftovers. Track consecutive pump failures;
# after 2 in a row, skip the pump entirely for a week and go straight to the deterministic claude -p
# path. The system stops re-learning the same lesson every morning.
PUMP_FAIL_STATE="$HOME/.brief-pump-failstreak"
PUMP_FAILS=$(cat "$PUMP_FAIL_STATE" 2>/dev/null || echo 0)
case "$PUMP_FAILS" in ''|*[!0-9]*) PUMP_FAILS=0 ;; esac
if [ "${FORCE_DIRECT:-0}" = "1" ] || [ "$PUMP_FAILS" -ge 2 ]; then
  echo "[$(date)] skipping tmux-pump (FORCE_DIRECT=${FORCE_DIRECT:-0}, failstreak=$PUMP_FAILS) — going straight to claude -p" >> "$LOG"
  PUMP_EXIT=99
fi
PUMP_PROMPT="[cron-trigger 6am morning-brief] Run /morning-brief skill. After generating, push the complete brief to the operator's Telegram via the mcp__plugin_telegram_telegram__send tool (chat_id ${CHAT_ID}). the operator is on phone, NOT watching this tmux pane. ONLY after the send tool returns success, run this exact command as your receipt: date +%s > ${BRIEF_RECEIPT} — the cron verifies that file and re-runs the brief a second time if it is missing.${STALE_HINT}"
if [ "${PUMP_EXIT:-}" != "99" ]; then
  $HOME/agent-os/agents/tmux-pump.sh "$PUMP_PROMPT" >>"$LOG" 2>&1
  PUMP_EXIT=$?
fi

if [ $PUMP_EXIT -eq 0 ]; then
  # pump injected OK — now VERIFY Atlas delivered within 3min (last-reply mtime advances). The old code
  # treated injection as completion → silent failures (brief never arrived). Verify-or-fall-back.
  DELIVERED=0
  for _w in $(seq 1 30); do   # 5 min — brief generation legitimately takes minutes
    sleep 10
    # BOTH must hold: Atlas wrote the receipt file (it ran the skill AND the send succeeded)
    # AND last-reply advanced (something actually went out to her Telegram).
    if [ -f "$BRIEF_RECEIPT" ] && [ "$(stat -f %m "$LAST_REPLY" 2>/dev/null || echo 0)" -gt "$PRE_PUMP" ]; then
      DELIVERED=1; break
    fi
  done
  if [ "$DELIVERED" = 1 ]; then
    echo "[$(date)] Morning brief delegated + VERIFIED delivered via Atlas tmux (receipt file + last-reply). Done." >> "$LOG"
    date +%s > /tmp/cron-heartbeats/com.operator.morning-brief 2>/dev/null || true   # 8/25 gap: success path never wrote the marker → stale alerts
    echo 0 > "$PUMP_FAIL_STATE"   # pump worked → reset the streak
    # ⛔ dashboard DISABLED 2026-07-23 (the operator: 不再看彩色版, 省资源). Re-enable = uncomment + un-⛔ the skill section.
    # # ⛔ dashboard DISABLED 2026-07-23 (the operator 不再看). python3 "$HOME/agent-os/scripts/brief-dashboard-gen.py" >> "$LOG" 2>&1 || true
    exit 0
  fi
  echo "[$(date)] tmux-pump injected but Atlas did NOT deliver — falling back to claude -p." >> "$LOG"
  echo $((PUMP_FAILS + 1)) > "$PUMP_FAIL_STATE"
fi

echo "[$(date)] tmux-pump exit=$PUMP_EXIT (or no delivery) — falling back to programmatic claude -p." >> "$LOG"

# Retry up to 3 times — NEVER silently skip morning brief
MAX_RETRY=3
RETRY=0
SUCCESS=false

while [ $RETRY -lt $MAX_RETRY ]; do
  ATTEMPT=$((RETRY + 1))
  echo "[$(date)] Running morning-brief (attempt ${ATTEMPT}/${MAX_RETRY})..." >> "$LOG"
  OUTPUT=$(safe_claude -p "/morning-brief${STALE_HINT}

CRITICAL — GENERATE-ONLY MODE (2026-07-06 dedup fix): Output the complete brief as your final text response ONLY. Do NOT send it to Telegram, do NOT call telegram-send.py, do NOT use any send tool. THIS wrapper script delivers the brief (line 163) — if you send it yourself, the operator gets it twice (the 7/3 double-send). This instruction OVERRIDES the skill's 'Delivery' section." --allowedTools "$TOOLS" --max-turns 45 2>&1)
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ] && [ -n "$OUTPUT" ]; then
    SUCCESS=true
    break
  fi

  RETRY=$((RETRY + 1))
  if [ $RETRY -lt $MAX_RETRY ]; then
    echo "[$(date)] Attempt ${ATTEMPT} failed (exit=$EXIT_CODE), retrying in 60s..." >> "$LOG"
    sleep 60
  fi
done

echo "$OUTPUT" > "$LOG"
echo "[$(date)] exit=$EXIT_CODE (attempt $ATTEMPT)" >> "$LOG"

if $SUCCESS; then
  # ── EVAL FRESHNESS GATE (2026-06-21, SHADOW mode) ──────────────────────────────────────────
  # Runs the deterministic eval (evals/skill-eval.py) on the produced brief BEFORE send.
  # references_current_date enforces the operator's ULTIMATE TEST: a brief with no today/yesterday date =
  # stale/cached = the "stale-memory" bug. SHADOW = log PASS/BLOCK only, NEVER alter the send (a false
  # block must never cost her the brief). Flip to enforcing (--scrub / regenerate) after a soak
  # proves no false-positives. Pairs the existing stale-audit PRE-step (which hints the model).
  GATE_ART=$(mktemp /tmp/mb-gate.XXXXXX)
  printf '%s\n' "$OUTPUT" > "$GATE_ART"
  GATE_OUT=$(python3 "$HOME/agent-os/evals/skill-eval.py" --gate --skill morning-brief --artifact "$GATE_ART" 2>&1)
  GATE_RC=$?
  echo "[$(date)] EVAL GATE rc=$GATE_RC :: $(echo "$GATE_OUT" | grep -E 'BLOCK|PASS' | tr '\n' ' ')" >> "$LOG"
  if [ "$GATE_RC" -eq 2 ]; then
    # 2026-07-02: ENFORCE (was shadow since 6/21 = never blocked anything). Enforcement mode =
    # visible-flag: never lose the brief, but stale can no longer masquerade as clean.
    echo "$(date '+%F %T') ☀️ morning-brief eval gate FLAGGED (enforced, warning prepended): $(echo "$GATE_OUT" | grep -i block | head -1)" >> "$HOME/agent-os/memory/live-pulse.md" 2>/dev/null
    GFLAG=$(echo "$GATE_OUT" | grep -i block | head -1)
    OUTPUT="⚠️ EVAL GATE: 本 brief 被质量门标记 (${GFLAG:-possible stale/no-date}) — 若下面有已完成/已取代事项, 回我一句, 我去清源头。

$OUTPUT"
  fi
  rm -f "$GATE_ART"
  # ────────────────────────────────────────────────────────────────────────────────────────────
  # Markdown → HTML (same as before; telegram-send.py handles chunk-boundary tag balance)
  CLEAN=$(echo "$OUTPUT" | \
    sed 's/&/\&amp;/g' | \
    sed 's/</\&lt;/g' | \
    sed 's/>/\&gt;/g' | \
    sed 's/^### \(.*\)/<b>\1<\/b>/' | \
    sed 's/^## \(.*\)/<b>━━ \1 ━━<\/b>/' | \
    sed 's/^# \(.*\)/<b>\1<\/b>/' | \
    sed 's/\*\*\([^*]*\)\*\*/<b>\1<\/b>/g' | \
    sed 's/`\([^`]*\)`/<code>\1<\/code>/g' | \
    sed 's/```[a-z]*//g' | \
    sed 's/```//g' | \
    sed 's/^- /• /g' | \
    sed '/^$/N;/^\n$/d')

  # Delegate chunking + send to Python helper (UTF-8 safe, HTML-balance, per-chunk plain fallback)
  echo "$CLEAN" | python3 "$SENDER" "$BOT_TOKEN" "$CHAT_ID" 2>>"$LOG"
  SEND_EXIT=$?
  _HB="$HOME/agent-os/reliability/cron-heartbeat.sh"   # DELIVERY RECEIPT + heartbeat (2026-06-20)
  if [ $SEND_EXIT -eq 0 ]; then
    echo "[$(date)] Sent successfully." >> "$LOG"
    # 2026-08-26: the DIRECT path must write the same receipt the tmux path writes —
    # otherwise brief-delivery-watchdog sees no receipt and re-fires forever on a day
    # the brief actually went out. Receipt = "she has it", regardless of which path won.
    date +%s > "$BRIEF_RECEIPT" 2>/dev/null || true
    date +%s > /tmp/cron-heartbeats/com.operator.morning-brief 2>/dev/null || true
    bash "$_HB" ok com.operator.morning-brief 2>/dev/null   # ✅ heartbeat ONLY on CONFIRMED delivery (not just cron-ran)
  else
    echo "[$(date)] Send had partial failures (exit=$SEND_EXIT). See log above." >> "$LOG"
    bash "$_HB" fail com.operator.morning-brief "send exit=$SEND_EXIT" 2>/dev/null
  fi
else
  # All retries failed — alert the operator
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    --data-urlencode "text=☀️ ❌ Morning Brief 生成失败 (${MAX_RETRY} 次尝试全部失败, last exit=$EXIT_CODE). 检查 Mac Mini logs。" > /dev/null 2>&1
  echo "[$(date)] All ${MAX_RETRY} attempts failed." >> "$LOG"
  bash "$HOME/agent-os/reliability/cron-heartbeat.sh" fail com.operator.morning-brief "gen failed exit=$EXIT_CODE" 2>/dev/null
fi

# ⛔ dashboard DISABLED 2026-07-23 (the operator 不再看彩色版) — python3 "$HOME/agent-os/scripts/brief-dashboard-gen.py" >> "$LOG" 2>&1 || true
echo "[$(date)] Complete." >> "$LOG"
