# Skills

A skill is a markdown file that an agent loads when a trigger matches: a slash command, a phrase, a schedule, an incoming message type. It is a contract, not a prompt. The parts that matter:

- **Trigger and scope** in the front matter, so the wrong skill does not fire.
- **Rules with their incident date.** A rule reads like "LAST-BULLET-WINS (2026-09-05 incident): an append-only section is a timeline, not a fact; a grep hit is a pointer". The date is the link to the postmortem and the reason the rule is not up for debate in the moment.
- **A deterministic gate at the end.** The briefs, news cards and email drafts finish with an explicit call to `evals/skill-eval.py --gate` from [agent-eval-gates](https://github.com/dyjhhh/agent-eval-gates). The model cannot skip the check because the check is not a suggestion.
- **Non-negotiables** listed separately, so a calibration run that edits the skill knows what it may not touch.

## What is published, and what is not

**No production skill file is published.** The index below names the system-facing ones, out of 97 in total, one line each, and that index is the whole of what leaves the private repository.

They were briefly published in full on 2026-09-15 and withdrawn on 2026-09-21. A life-operations contract is made of the life it operates, and a sanitizer that renames people still leaves enough shape to identify them. The failure is row 19 of the [incident log](incidents.md).

What is published instead are two contracts written from scratch for this repository, carrying the real structure with synthetic subject matter:

- [`skills/section-contract`](../skills/section-contract/SKILL.md): per-section length budgets, a reconcile pass, and an advisory scorer.
- [`skills/outbound-draft`](../skills/outbound-draft/SKILL.md): a skill wired to a gate that can refuse its output, with the two calibration changes that made the gate bite.

The index below is a list, not a set of links.

| Skill | What it does |
|---|---|
| `calibration-loop` | Turns my verdicts into parameter changes, weekly; a portable example of its approval boundary is [self-improving-loops](https://github.com/dyjhhh/self-improving-loops) |
| `work-trace` | Appends a structured trace of a session's decisions to the trace log; feeds calibration and the playbooks |
| `dream` | Saturday memory hygiene: stale, duplicate and orphan proposals, at most twenty, dated |
| `handoff` | Writes a cross-agent handoff row: status, artifact, next owner, tripwire |
| `architecture-verify` | Checks that a new artifact is registered everywhere it must be (architecture doc, index, sync layer) |
| `os-audit` | Quarterly drift audit of the whole system |
| `memory-prune-stale` | Guided pruning of the memory tree with a copy-to-archive rule instead of deletion |
| `reconcile` | Resolves a pending item against its owning file: clear it or keep it, with the reason |
| `review-proposals` | Consumes proposals from other agents with an apply-or-decline receipt |
| `verify` | Cross-checks a claim against canonical files and primary sources before it is stated |
| `adversarial-gate` | The cross-model argument for red-stakes outputs |
| `create-skill` | The template and checklist for a new skill, including its gate and its non-negotiables |
| `skill-quality-eval` | Runs the LLM-judge rubric over a sample of a skill's outputs |
| `news-analysis` | The news card contract: one link, one card, one message; fixed sections; density caps; signal colours; an auto-archive |
| `draft-email` | External email drafting in the operator's voice with the deterministic fingerprint gate |
| `deep-content-summarizer` | Long-content distillation with source citations |
| `research-verdict` | A bounded research pass that ends in a verdict, not a list |
| `delegate-task` | How to hand work to another agent with acceptance criteria |
| `ambient-capture` | The save-or-route rule: capture anything at sixty percent confidence, never ask whether to save |
| `route-signal` | Routes an incoming signal to the file or agent that owns it |
| `process-this` | The generic "process this content" entry point that dispatches to the right skill |
| `rambo` | Mirrors a stream-of-consciousness dump back as a structured plan, and takes no action on it |
| `remind` | The reminder format and its stale-sweeping rules |
| `heartbeat` | The always-on agent's periodic check: what to look at, what counts as signal, when to stay silent |
| `atlas-doctor` | Self-diagnosis for the always-on agent: session, auth, listener, plists, model and effort settings |
