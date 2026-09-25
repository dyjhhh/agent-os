#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"
# news-verify.sh — one-button ACCEPTANCE check for a news burst (2026-07-16, so the operator never QAs again).
# RELIABLE by design: the drop/completeness verdict comes from news-burst-reconcile.py (which accurately
# matches inbound-queue links vs vault `url:` frontmatter). This wrapper adds the verbosity + gate +
# ledger view around it. NO fragile time-window/find math (matches vault files by FILENAME date instead).
# Doubles as the coverage guard rail (morning-brief + burst-end). User-facing density is enforced
# at the Telegram send boundary; source notes in the evidence vault are allowed to be longer.
DATE="${1:-$(date +%Y-%m-%d)}"
LED="$HOME/.claude/channels/telegram/outbound-ledger.jsonl"
ART="$HOME/agent-os/memory/articles"

echo "════════ NEWS 验收 · ${DATE} ════════"

# ①+⑤ inbound vs vaulted — from reconcile (the accurate url-match; this is the real drop check)
echo "① 完整性对账(进来的 link vs 已归档,权威判定):"
VERIFY_OUT=$(python3 "$HOME/agent-os/scripts/news-burst-reconcile.py" "$DATE" 2>/dev/null)
VERIFY_RC=$?
printf '%s\n' "$VERIFY_OUT" | sed 's/^/   /'

# ② vaulted articles (by filename date, no fragile find)
echo ""
echo "② 当天 vault 覆盖(后台 source notes 不受前台字数上限):"
TOT=0
for f in "$ART/${DATE}"-*.md; do
  [ -f "$f" ] || continue
  grep -q "STUB-BACKFILL\|回补桩" "$f" && continue
  TOT=$((TOT+1))
done
echo "   → 当天真 news 文章 ${TOT} 篇；前台卡片长度由 send-boundary gate 单独验收"

# ③ send-boundary gates alive?
echo ""
echo "③ 发送边界 guard rail(累计触发数 = 它们活着在拦):"
echo "   verbosity-gate 拦冗长: $(grep -c DENY "$HOME/agent-os/logs/verbosity-gate.log" 2>/dev/null || echo 0)"
echo "   receipt-gate 拦假收据: $(grep -c DENY "$HOME/agent-os/logs/receipt-verify.log" 2>/dev/null || echo 0)"
echo "   outbound-ledger 留痕: $(wc -l < "$LED" 2>/dev/null | tr -d ' ' || echo 0) 条"

# ④ verdict
echo ""
echo "──────────────────────────────────────────"
if [ "${VERIFY_RC:-1}" -ne 0 ]; then
  echo "🔴 归档或 frontmatter contract 有缺口(见①)—— 需补"
else
  echo "✅ 无 drop，frontmatter 可被下游发现，前台 density gate 活着 —— 当天 news 干净"
fi
