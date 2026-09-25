---
name: section-contract
trigger: scheduled, the daily brief job at 06:00 local
gate: stale_leak blocks; section_caps is advisory (cases in agent-eval-gates/evals/cases/)
status: synthetic example, written for this repository
---

# section-contract

> **This is not a redaction of a production skill.** It is a contract written from scratch to show
> the shape the real ones have: a trigger, rules that each carry the date of the failure that
> produced them, hard per-section budgets, and a named scorer that measures compliance. The subject
> matter is invented. See [skills/README.md](../README.md) for why the real set is not published.

## What this skill produces

One message, delivered once per day, that the reader finishes. Everything below exists because a
version of it was not finished.

## Sections, in order, with hard caps

| section | cap (chars) | dropped when |
| --- | --- | --- |
| `ACTION NEEDED` | 480 | nothing is due; the header is omitted, not printed empty |
| `WHAT CHANGED` | 700 | no delta since the previous run |
| `INBOX` | 450 | no unread from a watched sender |
| `LEDGER` | 200 | never; repetition here is intentional, see rule 4 |
| `AGENDA` | 300 | the reader has no session planned |
| `SERENDIPITY` | 420 | nothing surfaced above the relevance floor |
| **total** | **3000** | n/a |

Caps are measured in characters, not tokens or words, because the reader's complaint was about
screen height on a phone and characters are what predicts it. The total is not the sum of the parts:
a run may spend its budget unevenly, but never exceed 3000.

## Rules

1. **(2026-08-26) The finish line is delivery, not dispatch.** A run that produced correct content
   and failed to deliver it is a failed run. The job's success condition reads the delivery receipt,
   not the generator's exit code. This one rule invalidated an entire class of green-but-silent runs.

2. **(2026-06-13) Reconcile before surfacing.** Before printing any item as pending, open the
   canonical file it points at and look for a terminal state: done, cancelled, sent, paid, booked.
   A reminder file is a copy, and copies go stale. The item is dropped if the canonical file says it
   closed, and no note is printed about the drop.

3. **(2026-09-05) Last bullet wins.** An append-only section is a timeline, not a fact. A `grep` hit
   inside one is a pointer, not an answer: read to the end of the section and take the most recent
   dated entry. The failure was reporting as outstanding something whose third bullet recorded it
   done the previous afternoon.

4. **(2026-09-18) Repetition is allowed until told otherwise.** The `LEDGER` section may repeat
   yesterday's content verbatim. Suppressing repeats was a de-duplication instinct that silently
   dropped standing items the reader wanted to keep seeing.

5. **(2026-09-18) State what is missing.** The last line names the one input this run could not
   resolve, phrased as a question the reader can answer in a sentence. An empty answer is an
   acceptable output; a silent omission is not.

## Anti-patterns

- A standing section that reprints the same checklist daily. Periodic items appear only inside
  `ACTION NEEDED`, and only when they come due.
- Printing a header with no content under it. An empty section is removed, header included.
- Quoting a source at length to prove the item is real. One clause of quotation, or a path.
- Any rule added here without the date and description of the failure that motivated it.

## How this is checked

`section_caps` is registered in
[evals/scorers.py](https://github.com/dyjhhh/agent-eval-gates/blob/main/evals/scorers.py)
in agent-eval-gates and runs **advisory**: it reports which sections exceeded their budget and by
how much, and never blocks a run. It is advisory on purpose: a brief that is 40 characters long in
one section is worse withheld than delivered. `stale_leak` covers rules 2 and 3 and is one of the
blocking gate scorers, because a confidently-wrong status is the failure mode the reader names as
the most expensive.

Cases live in the evals/cases/ directory of
[agent-eval-gates](https://github.com/dyjhhh/agent-eval-gates/tree/main/evals/cases). Some
regression cases are real failures rewritten with synthetic subject matter; others are constructed
guards for the same failure types. Each is paired with a corrected output.
