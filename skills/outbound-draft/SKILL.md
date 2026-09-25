---
name: outbound-draft
trigger: on request — "draft a reply to X"
gate: BLOCKING (ai_fingerprint ≥ 0.65, forbidden_terms, markdown_leak)
status: synthetic example, written for this repository
---

# outbound-draft

> **This is not a redaction of a production skill.** It is a contract written from scratch to show
> how a skill is wired to a gate that can refuse its output. The subject matter is invented; the
> gate wiring, the thresholds and the two calibration changes described at the bottom are real and
> are visible in `evals/`. See [skills/README.md](../README.md) for why the real set is not published.

## What this skill produces

A draft of an outbound message, for a human to read, edit and send. **It never sends.** Sending is
outside the agent's authority regardless of how the request is phrased, and the deny hook in
`security/` enforces that independently of anything written here.

## The voice contract

The operator's written voice is the specification, and it is narrow enough to check mechanically:

- **No em dash.** Not one. The rule is absolute in the style guide, which is what makes it
  gate-able — a rule with exceptions cannot be a gate.
- **No bullet lists** in an outbound message. Prose, in flowing sentences.
- **No markdown syntax.** The destination renders none of it; `**bold**` arrives as four literal
  asterisks.
- **Length 250–300 words** for a substantive reply, four paragraphs.
- **No enthusiasm verbs** (*thrilled, excited, delighted*), no *I hope this finds you well*, no
  sign-off that promises follow-up the operator has not agreed to.

When revising a draft the operator has already touched, her sentence structure is copied, not
merely her word choices. A revision that reads better but sounds like someone else is a failed
revision.

## How the gate works

```
draft → skill-eval.py --gate outbound-draft
          ├── ai_fingerprint   threshold 0.65   → BLOCK below
          ├── forbidden_terms  regex list       → BLOCK on any hit
          └── markdown_leak    threshold 0.60   → BLOCK below
```

A blocked draft is never delivered as a suggestion with a warning attached. It goes back to the
generator. The reason is that a warning attached to a draft is a decision handed to the reader, and
handing the reader a decision they did not ask for is the cost the gate exists to avoid.

## The two calibration changes that made this gate bite

Both came out of the weekly calibration loop in `loops/`, which compares what the agent drafted
against what the operator actually sent.

1. **`forbidden_terms` was advisory and is now blocking.** The style guide said *never use em
   dashes*; the scorer measured them; nothing enforced them. A draft carrying two went out for
   review and was rewritten by hand. The scorer was moved into `GATE_SCORERS`, and the em-dash
   pattern uses a lookaround so that a CJK double dash is not caught by an English rule:
   `(?<!—)—(?!—)`.

2. **The comparison was `<` and the score landed exactly on the threshold.** A draft scoring
   `ai_fingerprint = 0.6` against `DEFAULT_THRESHOLD = 0.6` is not less than the threshold, so it
   passed. Rather than change the comparison globally — which would tighten every gate in the
   portfolio at once — this one skill got its own entry in `SKILL_THRESHOLDS` at 0.65. The narrow
   fix was chosen over the general one because only one skill had evidence behind it.

The second change is the more instructive of the two. The tempting fix was `<=`. It would have been
one character, it would have been defensible, and it would have silently raised the strictness of
every other gated skill without a single supporting observation for any of them.

## How this is checked

Regression cases in `evals/cases/` hold a matched pair: the draft that slipped through, and the
version the operator actually sent. The pair is the ground truth — not a rubric, not a judge model,
but the difference between what the machine wrote and what the human was willing to put their name
on.
