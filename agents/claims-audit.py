#!/usr/bin/env python3
# claims-audit.py — FULL claims-vs-disk audit of Atlas's outbound receipts for a given day (2026-07-18,
# the operator: "他说他归档/做了的东西,你确保他真的有做"). Reads every send in outbound-ledger.jsonl for the
# date, extracts every claim (已归档 X / 已执行 file[:line] [「quote」] / 已交接), verifies each against
# disk: vault file exists; cited quote really in the cited file; handoff noted. Prints TRUE/FALSE lists.
# Exit 1 if any claim is false (so a wrapper/cron can act). Zero LLM tokens.
# Usage: claims-audit.py [YYYY-MM-DD]   (default today)
import json, re, os, sys, glob, time, subprocess

HOME = os.path.expanduser("~")
ROOTS = [f"{HOME}/agent-os/memory", f"{HOME}/.claude/projects/-project/memory", f"{HOME}/agent-os"]
LEDGER = f"{HOME}/.claude/channels/telegram/outbound-ledger.jsonl"


def find(base):
    for r in ROOTS:
        hits = glob.glob(f"{r}/**/{base}", recursive=True)
        if hits:
            return hits[0]
    return None


def norm(s):
    return re.sub(r"[\s\*\`\|>#\-•「」\"'“”]+", "", s)


def main():
    day = sys.argv[1] if len(sys.argv) > 1 else time.strftime("%Y-%m-%d")
    ok, bad = [], []
    try:
        lines = open(LEDGER, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        print("no ledger"); return 0
    for l in lines:
        try:
            d = json.loads(l)
        except Exception:
            continue
        if day not in d.get("iso", ""):
            continue
        # 2026-07-23 fix: the ✅ receipt lines live in the `receipts` field (full lines), NOT `preview`
        # (which is truncated at 160 chars → receipt lines got cut off → audit found 0). Read receipts.
        pv = "\n".join(d.get("receipts") or []) or d.get("preview", "")
        # claim: 已归档 [articles/]X.md  (vault card = file must exist)
        for m in re.finditer(r"已归档[::]?\s*(?:articles/)?([A-Za-z0-9._\-]+\.md)", pv):
            base = m.group(1)
            p = find(base)
            (ok if p else bad).append(f"归档 {base}" + ("" if p else "  ← 文件不存在"))
        # claim: 已执行 file[:line] [— 「quote」]  (topic commit = content must be in file)
        for m in re.finditer(r"已执行[::]?\s*([A-Za-z0-9._/\-]+\.md)(?::(\d+))?", pv):
            base = os.path.basename(m.group(1))
            p = find(base)
            if not p:
                bad.append(f"执行 {base}  ← 文件不存在")
                continue
            tail = pv[m.end(): m.end() + 90]
            qm = re.search(r"[「\"“']([^」\"”']{4,50})", tail)
            if qm:
                q = norm(qm.group(1))[:12]
                content = norm(open(p, encoding="utf-8", errors="ignore").read())
                hit = q and q in content
                (ok if hit else bad).append(
                    f"执行 {base}:{m.group(2) or '?'} 引用「{qm.group(1)[:22]}…」" + ("" if hit else "  ← 引用内容不在文件里"))
            else:
                fresh = time.time() - os.path.getmtime(p) < 21600
                (ok if fresh else bad).append(f"执行 {base}(无引用,按 mtime)" + ("" if fresh else "  ← 6h 无写入"))
        # claim: 已交接 Forge (handoff must appear in Forge-notes today)
        if re.search(r"已交接\s*Forge", pv):
            notes = f"{HOME}/agent-os/memory/Forge-notes.md"
            head = open(notes, encoding="utf-8", errors="ignore").read(4000) if os.path.exists(notes) else ""
            hit = day in head or "Atlas →" in head[:1500]
            (ok if hit else bad).append("交接 Forge-notes" + ("" if hit else "  ← notes 顶部无今日交接"))
    print(f"═══ 全量 claims-vs-disk 审计 ({day}) ═══")
    print(f"✅ 验证为真: {len(ok)} 条")
    for x in ok:
        print(f"   ✓ {x}")
    print(("🔴" if bad else "✅") + f" 验证为假: {len(bad)} 条")
    for x in bad:
        print(f"   ✗ {x}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
