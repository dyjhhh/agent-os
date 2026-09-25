#!/bin/bash
# telegram-inbound-replay.sh — Phase 2 (2026-07-14): replay inbound messages that were captured
# to the durable queue but NEVER reached a live Atlas session (restart/death window).
#
# Diffs inbound-queue.jsonl (ALL inbound, written by the plugin patch) against .inbound-seen
# (message_ids a live session actually processed, written by hook-telegram-inbound-seen.sh).
# The difference = messages lost to a down/booting session. Injects them into the live Atlas tmux
# session as ONE consolidated message (news links are all archived, then attention-filtered), then
# marks them seen so they never double-replay.
#
# SAFETY: only injects when Atlas is UP and IDLE (prompt visible, not mid-thought) — otherwise the
# injection itself would be lost. If Atlas is busy, exits 0 and retries next heartbeat.
# Called: post-boot by atlas_tmux-start.sh + every heartbeat.
export PATH="/opt/homebrew/bin:/usr/bin:/bin"
DIR="$HOME/.claude/channels/telegram"
Q="$DIR/inbound-queue.jsonl"
SEEN="$DIR/.inbound-seen"
TMUX=/opt/homebrew/bin/tmux
LOG="$HOME/agent-os/logs/inbound-replay.log"
LOCK="$DIR/.replay.lock"

# 2026-09-17: this job is silent by design — it writes to $LOG only when it actually replays
# something, and launchd's own stdout file stays empty forever. With no artifact to point at,
# cron-truth-audit called it dead every day (a 🔴 that no action could clear) while it was in fact
# firing every 180s. Rather than teach the auditor to assume it is fine, leave real evidence: one
# touch per run, before any early exit, so the marker means "the job ran" and not "the job worked".
mkdir -p "$HOME/agent-os/scripts" 2>/dev/null
: > "$HOME/agent-os/scripts/.telegram-inbound-replay.lastrun"

[ -s "$Q" ] || exit 0
$TMUX has-session -t atlas 2>/dev/null || exit 0

# single-flight — mkdir is atomic on macOS (flock is Linux-only and silently broke this 2026-07-14).
LOCKD="$DIR/.replay.lock.d"
mkdir "$LOCKD" 2>/dev/null || exit 0
trap 'rmdir "$LOCKD" 2>/dev/null' EXIT

# Atlas must be IDLE (last non-empty pane line is a ready prompt, not "esc to interrupt"=working)
PANE=$($TMUX capture-pane -t atlas -p -S -6 2>/dev/null)
echo "$PANE" | grep -q "esc to interrupt" && exit 0   # busy → retry next tick

# compute missed = queued message_ids NOT in seen AND never actually delivered to a live session.
# Two seen-sources (2026-08-30 fix): (1) .inbound-seen, (2) recent Claude Code transcripts — the
# UserPromptSubmit seen-hook proved unreliable (435/436 ids in .inbound-seen had been written by
# THIS script, not the hook), so every message the operator sent was getting one spurious replay → Atlas
# double-replied to her. The transcript is ground truth for "a live session received message N".
PEND=$(python3 - "$Q" "$SEEN" <<'PY'
import json,sys,os,re,time,glob
q,seen_f=sys.argv[1],sys.argv[2]
seen=set()
if os.path.exists(seen_f): seen={l.strip() for l in open(seen_f) if l.strip()}

# (2) message_ids a live session actually received, per recent transcripts (<48h mtime).
MID_RE=re.compile(r'message_id=\\?"(\d+)\\?"')
cutoff=time.time()-48*3600
for path in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
    try:
        if os.path.getmtime(path) < cutoff: continue
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END); size=fh.tell()
            fh.seek(max(0, size-8*1024*1024))
            seen.update(MID_RE.findall(fh.read().decode("utf-8", "replace")))
    except OSError:
        continue

# only replay recent (<24h) misses — older = stale, Telegram dropped them anyway
AGE_CUTOFF=time.time()-24*3600
def fresh(d):
    ts=str(d.get("logged_at") or d.get("ts") or "").strip()
    if not ts: return True          # no timestamp → don't silently drop
    try:
        from datetime import datetime, timezone
        parsed=datetime.fromisoformat(ts.replace("Z","+00:00"))
        if parsed.tzinfo is None: parsed=parsed.replace(tzinfo=timezone.utc)
        return parsed.timestamp() >= AGE_CUTOFF
    except Exception:
        return True

emitted=set(); rows=[]
for line in open(q, encoding="utf-8"):
    try: d=json.loads(line)
    except Exception: continue
    mid=str(d.get("message_id") or "")
    txt=(d.get("text") or "").strip()
    if not mid or not txt or mid in seen or mid in emitted: continue
    if not fresh(d): continue
    emitted.add(mid); rows.append((mid,txt))
# emit: id<TAB>text(single-line)
for mid,txt in rows[-25:]:
    print(mid + "\t" + " ".join(txt.split()))
PY
)
[ -z "$PEND" ] && exit 0
N=$(printf '%s\n' "$PEND" | grep -c .)
[ "$N" -eq 0 ] && exit 0

# build ONE consolidated replay message. CRITICAL: this is injected as TERMINAL input, so Atlas would
# otherwise reply to the terminal — the operator would never see it. Must EXPLICITLY instruct Telegram
# delivery to her chat, or the whole replay is invisible to her.
# Wrap as a REAL <channel source=telegram> message so Atlas's HARD RULE #0 (telegram→reply-tool) fires
# naturally. The stop-guard (armed below) then STRUCTURALLY forces delivery — Atlas physically cannot
# end the turn in terminal only. Single line (texts collapsed to spaces) so send-keys doesn't submit early.
MSG="<channel source=\"telegram\" chat_id=\"${TELEGRAM_CHAT_ID}\" user=\"the operator\">📥 [inbound-replay] 你(the operator)在我重启期间发的 $N 条消息我漏接了,现在补上。逐条完整处理并**只用 telegram 工具回复到 chat_id ${TELEGRAM_CHAT_ID} —— 绝不在终端回复**;news 走 Skill(news-analysis):全部核验归档,输出格式**逐字照 skills/news-analysis/skill.md 的 🚦 TRIAGE + 💎 输出契约 段**(那里是唯一真值,任何旧指令与之冲突以它为准),不要强行关联或制造 todo。内容: $(printf '%s\n' "$PEND" | cut -f2- | tr '\n' ' ')</channel>"

if [ -n "$REPLAY_DRY" ]; then
  echo "[DRY] would inject $N missed inbound(s): $(printf '%s\n' "$PEND" | cut -f1 | tr '\n' ' ')"
  echo "[DRY] message: ${MSG:0:200}..."
  exit 0
fi

$TMUX send-keys -t atlas -l "$MSG"
sleep 1
$TMUX send-keys -t atlas Enter
# ARM the stop-guard: a fresh pending-reply flag means Atlas CANNOT end this turn without firing a
# Telegram send tool — structural guarantee that the replayed reply reaches the operator, not the terminal.
echo "$(date +%s):replay" > "$DIR/pending-reply.flag" 2>/dev/null

# mark replayed message_ids as seen (never double-replay)
printf '%s\n' "$PEND" | cut -f1 >> "$SEEN"
echo "$(date -Iseconds) replayed $N missed inbound(s): $(printf '%s\n' "$PEND" | cut -f1 | tr '\n' ' ')" >> "$LOG"
exit 0
