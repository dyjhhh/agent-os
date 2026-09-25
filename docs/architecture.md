# Architecture

## Agents and machines

| Agent | Where | Role | How it runs |
|---|---|---|---|
| Atlas, chief of staff | Mac mini, always on | Telegram front door, morning and weekly briefs, mailbox triage, news analysis, scheduled monitoring | An interactive Claude Code session inside tmux, with the Telegram channel plugin. Scheduled jobs inject prompts into that session (subscription pricing) and fall back to a headless `claude -p` call (metered) only if delivery is not confirmed. |
| Forge, deep work | Laptop, on demand | Analysis, coding, financial models, canonical memory writes, the tooling in this repo | Claude Code sessions started by me, plus a smaller set of laptop launchd jobs |
| Codex | Laptop | Long-running project threads | OpenAI Codex CLI with its own scheduled tasks; writes to the same canon through a transaction script |

All three read and write one brain: a git repository of markdown files. There is no vector store. Retrieval is `grep`, a curated index file that every session loads first, and a derived SQLite full-text index for history search.

## The shared brain

- **Canonical files own facts.** Each topic has one file that is the source of truth. Other files may point to it but never copy its status. The morning brief has a reconcile pass that opens the owning file before surfacing any pending item. The incident that created the rule is row 1 of the [incident log](incidents.md).
- **Append-only with provenance.** Agents append dated bullets tagged with a provenance label (`USER-STATED`, `PRIMARY-SOURCE`, `LOCAL-VERIFIED`, `INFERRED`). Later bullets win. A hook shows the tail of a canonical file before an agent is allowed to append to it for the first time in a session.
- **One writer at a time.** A transaction script serialises writes with a lock, commits with a scoped message and pushes. A five-minute auto-sync job on each machine pulls, rebases and pushes. When GitHub is unreachable from one machine, a private bridge script relays commits over Tailscale in both directions.
- **Handoffs, not chat.** Cross-agent work lands as one row in a handoff file: date, from, to, one-line status, OPEN. Each agent reads the tail of that file at session start as its inbox. Long-running sessions do not always restart, so I still relay some handoffs by hand, pointing to the file instead of pasting its content.

## Scheduling

Everything scheduled is a macOS launchd job, one plist per job and the plist is the only source of truth for cadence. Two lessons cost me days and are documented in `launchd/README.md`:

1. Without a GUI login, launchd does not fire calendar-interval jobs at all. A private dispatcher script runs every five minutes on an interval trigger, reads every plist and replays any calendar slot that passed within the last two hours, at most once per slot, yielding when a GUI session appears.
2. Over SSH the user launchd domain does not exist at the login window. Jobs can only be bootstrapped remotely if the plist declares `LimitLoadToSessionType = Background`. Every plist now does, which is what lets the private reboot chain work without sudo and without auto-login.

The dispatcher itself is private. [agent-reliability](https://github.com/dyjhhh/agent-reliability) has a tested, synthetic version of the replay and job-audit logic in [schedule.py](https://github.com/dyjhhh/agent-reliability/blob/main/schedule.py), and these launchd lessons are written up with other operating notes in [operations-notes.md](https://github.com/dyjhhh/agent-reliability/blob/main/docs/operations-notes.md).

## Delivery

Telegram is the only channel I read. Every message the always-on agent sends goes through a chain of hooks: a delivery enforcement hook (a channel message must be answered through the channel tool, never as terminal text), a density gate that blocks over-long news cards, a receipt hook that records what was sent and a memory-first hook that injects the canonical files most relevant to an inbound message before the model answers.

Delivery is verified with receipts, not proxies. A brief counts as delivered only when the agent writes a receipt file after the send tool returns success. Modification times of chat logs were the earlier proxy and produced a false "delivered" 12 seconds after injection. Row 6 of the [incident log](incidents.md) has the details.

## Layers

```
operator (Telegram)
  └─ channel plugin ── hooks (enforce, density, receipt, memory-inject)
       └─ Atlas session (tmux)  ◄── tmux-pump ◄── launchd jobs
            ├─ skills (markdown contracts) ── deterministic gates (evals/ in agent-eval-gates)
            ├─ shared brain (git)  ◄── auto-sync 5 min ◄── laptop (Forge, Codex)
            └─ alert gate ── watchdogs, audits, health checks ── handoff file
```
