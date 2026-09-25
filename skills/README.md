# skills/

A skill is a markdown contract the agent loads before it does a particular kind of work: what
triggers it, what the output must contain, what it must never contain, and which deterministic
check runs against the result. The interesting property is that every rule carries the date of
the failure that produced it, so a rule can be audited against the incident it claims to prevent
rather than taken on faith.

## What is and is not in this directory

The operator's own system runs 97 of these, and they are **not published here**. They are
life-operations contracts: they name real people, real counterparties, real medical and financial
state. No amount of regular-expression redaction makes a document safe when its subject matter is
the private life it was written to run — a sanitizer that renames people still leaks the shape of
who they are and what happened to them. Publishing them was tried on 2026-09-15 and reversed six
days later; the incident is row 19 of docs/incidents.md (private reference, not included in this snapshot).

What is published instead are the two contracts below, written from scratch for this repository.
They carry the real structure — the trigger block, the dated rules, the per-section caps, the gate
wiring — with synthetic subject matter. Treat them as the shape of the thing, not as a redaction
of it.

| file | what it demonstrates |
| --- | --- |
| [section-contract/SKILL.md](section-contract/SKILL.md) | a length-and-content contract with per-section caps, a reconcile pass, and an advisory scorer |
| [outbound-draft/SKILL.md](outbound-draft/SKILL.md) | a skill wired to a **blocking** gate, including the two calibration changes that made the gate actually bite |

The architecture of the real set — how skills are registered, how they are evaluated, how a rule
gets added — is in [docs/skills.md](../docs/skills.md).
