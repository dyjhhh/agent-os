# agents

The runtime around the always-on agent: how prompts get into its session, how messages get out, and the two brief pipelines with their delivery receipts. These are sanitized reference excerpts: they assume private paths and hooks, are not run by `make test` or CI, and have no tests in this repository.

| File | What it does |
|---|---|
| `tmux-pump.sh` | Injects a prompt into the agent's interactive tmux session (subscription pricing) instead of spawning a metered headless call; clears the composer first so a stray line cannot mangle the prompt |
| `telegram-send.py` | Multi-part sender: markdown to HTML, UTF-8-safe chunking, balanced tags |
| `morning-brief.sh` | The daily pipeline: pump first, verify delivery by receipt, fall back to a headless call, run the freshness gate before send, heartbeat on confirmed delivery |
| `weekly-brief.sh` | The weekly pipeline: two skills in sequence with an idle-pane wait between them, receipts per skill, silent sub-tasks folded into the main report, sentinel stamped only on a real delivery |
| `telegram-inbound-replay.sh` | Replays inbound messages queued while the session was down (last 24 hours, at most 25 per run) once the session is idle, and marks them seen to avoid a double replay |
| `news-verify.sh` | One-button acceptance check for a news batch: cards promised versus cards on disk versus cards sent |
| `claims-audit.py` | Full claims-versus-disk audit of a day's outbound receipts |
