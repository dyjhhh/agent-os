#!/usr/bin/env python3
"""
telegram-send.py — safe multi-part Telegram sender.

Usage:
    cat message.html | python3 telegram-send.py <bot_token> <chat_id> [--plain] [--silent]

Features:
- Splits on paragraph boundaries (double \\n\\n) — not char count, not mid-HTML-tag
- UTF-8 safe (Python str, not bash `cut -c`)
- Balances HTML tags within each chunk (closes open <b>/<code>/<i> at chunk end)
- Adds "(i/N) " prefix when multi-part
- Per-chunk fallback to plain text if HTML parse fails
- Exits 0 on full success, 1 if any part failed entirely

Drop-in replacement for the sed-based chunking in morning-brief.sh /
intelligent-heartbeat.sh.
"""
import sys, re, json, urllib.parse, urllib.request

MAX_LEN = 3900  # Telegram limit 4096, leave headroom for "(N/M) " prefix

# Telegram-supported HTML tags. If input already contains any of these, we assume
# the caller pre-formatted it as HTML (morning-brief/heartbeat inline sed, monitor
# scripts) and pass it through untouched — never double-convert / double-escape.
_TG_HTML_TAGS = re.compile(r'</?(b|strong|i|em|u|ins|s|strike|del|code|pre|a|tg-spoiler|blockquote)\b', re.I)


def md_to_html(text):
    """Convert standard Markdown → Telegram HTML so `**bold**` / `### head` /
    `- bullet` render instead of showing literal `**` junk.

    Why this lives HERE (not per-script): every cron/digest sender pipes through
    telegram-send.py, but only some had their own fragile inline `sed` converter
    (morning-brief, heartbeat) — others (hourly-email-check, store2-reeval,
    review-proposals, personal finances) sent RAW markdown with parse_mode=HTML, so
    Telegram showed literal `**`. Centralizing the converter fixes all of them at
    once and makes the inline seds redundant (idempotent: already-HTML → passthrough).
    """
    if _TG_HTML_TAGS.search(text):
        return text  # already HTML — leave it (avoids double-escape/double-convert)

    # 1) Protect inline-code spans so their contents survive the other rules.
    code_spans = []
    def _stash(m):
        code_spans.append(m.group(1))
        return f"\x00C{len(code_spans)-1}\x00"
    text = re.sub(r'`([^`\n]+)`', _stash, text)
    # drop fenced-code fences (```lang) but keep the inner lines
    text = re.sub(r'```[a-zA-Z0-9]*\n?', '', text)

    # 2) Escape HTML metachars BEFORE inserting our own tags (so our tags survive).
    text = text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

    # 3) Headers (#..###### at line start) → bold. Strip trailing #'s.
    text = re.sub(r'(?m)^[ \t]{0,3}#{1,6}[ \t]+(.*?)[ \t]*#*[ \t]*$', r'<b>\1</b>', text)
    # 4) Bold **x** / __x__ (before italic so the doubles are consumed first).
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    text = re.sub(r'(?<!\w)__(.+?)__(?!\w)', r'<b>\1</b>', text)
    # 5) Italic *x* (single asterisk, not touching a word/asterisk, no inner newline).
    text = re.sub(r'(?<![\*\w])\*(?!\s)([^\*\n]+?)(?<!\s)\*(?![\*\w])', r'<i>\1</i>', text)
    # 6) Bullets (-, *, + at line start) → • . Bold/italic already consumed their *.
    text = re.sub(r'(?m)^([ \t]*)[-*+][ \t]+', r'\1• ', text)
    # 7) Links [text](url) → <a href>.
    text = re.sub(r'\[([^\]]+)\]\((https?://[^\s)]+)\)', r'<a href="\2">\1</a>', text)

    # 8) Restore code spans (escape their inner metachars too).
    def _unstash(m):
        c = code_spans[int(m.group(1))]
        c = c.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        return f"<code>{c}</code>"
    text = re.sub(r'\x00C(\d+)\x00', _unstash, text)
    return text

def split_safe(text):
    """Return list of chunks each <= MAX_LEN, split on natural boundaries."""
    chunks = []
    current = ""
    paragraphs = re.split(r'\n\n+', text)

    for para in paragraphs:
        addition = ("\n\n" + para) if current else para
        if len(current) + len(addition) <= MAX_LEN:
            current += addition
            continue
        if current:
            chunks.append(current)
            current = ""
        # Single paragraph may itself exceed MAX_LEN — split it further.
        while len(para) > MAX_LEN:
            split_at = -1
            # Try newline, then sentence endings
            for sep, offset in [('\n', 0), ('。', 1), ('. ', 2), ('! ', 2), ('? ', 2)]:
                pos = para.rfind(sep, 0, MAX_LEN)
                if pos > MAX_LEN // 2:
                    split_at = pos + offset
                    break
            if split_at < MAX_LEN // 2:
                split_at = MAX_LEN  # hard cut (UTF-8 safe via str)
            chunks.append(para[:split_at])
            para = para[split_at:].lstrip()
        current = para

    if current:
        chunks.append(current)
    return [balance_html(c) for c in chunks]


def balance_html(chunk):
    """Balance HTML tags within chunk: re-open orphan closers at start, close
    any remaining opens at end. Handles chunks that start mid-<b> block
    (orphan </b>) or end mid-<b> block (dangling <b>)."""
    open_tags = []         # currently open at this position
    orphan_closes = []     # closes with no matching open → need prepend
    for m in re.finditer(r'<(/?)(\w+)[^>]*>', chunk):
        is_close = bool(m.group(1))
        tag = m.group(2).lower()
        if is_close:
            if open_tags and open_tags[-1] == tag:
                open_tags.pop()
            else:
                orphan_closes.append(tag)
        else:
            open_tags.append(tag)
    # Prepend openers for any orphan closers (in order they appeared)
    prefix = "".join(f"<{t}>" for t in orphan_closes)
    # Append closers for any still-open
    suffix = "".join(f"</{t}>" for t in reversed(open_tags))
    return prefix + chunk + suffix


def strip_html(text):
    return re.sub(r'<[^>]+>', '', text)


def send(bot_token, chat_id, text, parse_mode=None, silent=False):
    data = {'chat_id': chat_id, 'text': text}
    if parse_mode:
        data['parse_mode'] = parse_mode
    if silent:
        data['disable_notification'] = 'true'
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{bot_token}/sendMessage",
        data=urllib.parse.urlencode(data).encode('utf-8'),
        method='POST'
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            body = json.loads(resp.read().decode('utf-8'))
            return body.get('ok', False), body
    except Exception as e:
        return False, {'error': str(e)}


def main():
    if len(sys.argv) < 3:
        print("usage: telegram-send.py <bot_token> <chat_id> [--plain] [--silent]", file=sys.stderr)
        sys.exit(2)
    bot_token, chat_id = sys.argv[1], sys.argv[2]
    force_plain = '--plain' in sys.argv[3:]
    silent = '--silent' in sys.argv[3:]

    text = sys.stdin.read().rstrip()
    if not text:
        print("[empty input, nothing to send]", file=sys.stderr)
        sys.exit(0)

    # Convert any Markdown → Telegram HTML so `**bold**`/`### head` render (not literal).
    # Skipped for --plain (caller wants raw text, no parse mode). Already-HTML passes through.
    if not force_plain:
        text = md_to_html(text)

    chunks = split_safe(text)
    total = len(chunks)
    all_ok = True

    for i, chunk in enumerate(chunks, 1):
        msg = f"({i}/{total}) {chunk}" if total > 1 else chunk
        parse_mode = None if force_plain else 'HTML'

        ok, resp = send(bot_token, chat_id, msg, parse_mode=parse_mode, silent=silent)
        if not ok and not force_plain:
            err = resp.get('description', str(resp))
            print(f"[part {i}/{total} HTML failed: {err}] retrying plain", file=sys.stderr)
            plain = strip_html(chunk)
            msg_plain = f"({i}/{total}) {plain}" if total > 1 else plain
            ok, resp = send(bot_token, chat_id, msg_plain, silent=silent)

        if not ok:
            print(f"[part {i}/{total} FAILED: {resp}]", file=sys.stderr)
            all_ok = False

    sys.exit(0 if all_ok else 1)


if __name__ == '__main__':
    main()
