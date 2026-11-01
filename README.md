# Personal Agent OS

**Problem:** a new agent session cannot tell from chat history alone what earlier sessions actually finished.\
**What it shows:** the state layer of the agent harness I run daily: state and its handoff receipt commit together, and a stale revision cannot overwrite a newer one. The [incident log](docs/incidents.md) records 25 failures with their root causes.\
**Run it in about 60 seconds:** clone, then `make test` (Python 3.10+ and Make; no model, account or network).

[![tests](https://github.com/dyjhhh/agent-os/actions/workflows/test.yml/badge.svg)](https://github.com/dyjhhh/agent-os/actions/workflows/test.yml)

## Applying this on an engineering team

- **Several agents on one task.** Each task has one owner and a versioned state row; an agent that started from an old revision must reload instead of overwriting newer work.
- **Handoffs between agents or sessions.** The state change and its handoff receipt commit in one SQLite transaction, so the next session resumes from what was committed, not from a chat summary.
- **Retries from schedulers or people.** Each turn is keyed, so an exact retry returns the original receipt and writes nothing.
- **Incident review.** One row per failure with its root cause and the guard it left behind, as in [docs/incidents.md](docs/incidents.md).

I build and operate a three-agent harness for my own work, with shared state,
evaluation checks, human review and recovery workflows. It runs across two Macs
for research, documents and daily operations. The agents run on Claude Code and
Codex, which I also use to write this code; I review the changes myself.

This repository makes part of that work runnable without access to my accounts
or private data.

## Run the continuity example

```sh
make demo
make test
```

The [example](examples/continuity/) saves versioned task state and a handoff
receipt in one SQLite transaction. A new session resumes that state. Two workers
can start from the same revision, but only one can commit. The other must reload.
An exact retry returns its original receipt without another write.

| Behavior | What the test checks |
|---|---|
| Resume a task | A new store instance reads the committed state and next step |
| Reject stale work | An old revision cannot overwrite a newer one |
| Retry safely | The same turn and payload return the same receipt |
| Keep state and receipt together | A failed receipt write rolls back the state change |
| Separate tasks | A turn cannot be reused for another task |

[Read the design and limitations](examples/continuity/README.md) ·
[Read the implementation](examples/continuity/continuity.py) ·
[Read the tests](examples/continuity/test_continuity.py)

This is a new, simplified extraction of the private system's design. It uses
synthetic data and SQLite in place of the private Git transaction adapter.
It is a personal-project example, not an employer system or a claim of
enterprise deployment.

## Parts of the portfolio

| Repository | Focus | Start with |
|---|---|---|
| **This repository** | Shared state, task handoffs and recovery | [Continuity demo](examples/continuity/) |
| [Agent Eval Gates](https://github.com/dyjhhh/agent-eval-gates) | Output checks and evidence-bound review | [Artifact preflight demo](https://github.com/dyjhhh/agent-eval-gates/tree/main/examples/evidence-release) |
| [Agent Security Hooks](https://github.com/dyjhhh/agent-security-hooks) | Bounded tool guards and input screening | [Coverage and limitations](https://github.com/dyjhhh/agent-security-hooks/blob/main/docs/security.md) |
| [Agent Reliability](https://github.com/dyjhhh/agent-reliability) | Alert decisions, delivery state, successful-work evidence and calendar replay | [Offline demo](https://github.com/dyjhhh/agent-reliability/blob/main/demo.py) |
| [Self-Improving Loops](https://github.com/dyjhhh/self-improving-loops) | Feedback, explicit approval and regression checks | [Synthetic demo](https://github.com/dyjhhh/self-improving-loops/blob/main/demo.py) |
| [Award Alert Bridge](https://github.com/dyjhhh/award-alert-bridge) | Time-critical alerts: one event key, a wake ceiling and gated re-arming | [Offline demo](https://github.com/dyjhhh/award-alert-bridge/blob/main/demo.py) |
| [Careers Watch](https://github.com/dyjhhh/careers-watch) | Feed monitoring with exact identity and a zero-token prefilter before any model call | [Offline demo](https://github.com/dyjhhh/careers-watch/blob/main/demo.py) |

The artifact-preflight demo asks a second question: **is this still the exact
artifact and evidence the reviewer approved?** An edited source, changed artifact
or missing approval blocks the preflight. Exact quotes and hashes establish
traceability; they do not replace a reviewer's judgment about whether a claim
is supported.

## The larger system

The private system uses shared Markdown state, serialized writes, scheduled
workers and delivery receipts. These design notes explain the organization:

- [Architecture](docs/architecture.md): task ownership, shared state and delivery.
- [Principles](docs/principles.md): explicit action gates and observable outcomes.
- [Skills](docs/skills.md): reusable procedures and how corrections become checks.
- [Incidents](docs/incidents.md): failures that changed how the system is built,
  one row each.
- [Synthetic skill examples](skills/README.md): two contracts written for this
  repository, rather than copies of personal operating instructions.

The `agents/` and `launchd/` directories contain sanitized reference excerpts.
They assume a private runtime layout and are **not installed by the quickstart**.
The continuity example is the self-contained entry point. Agent Reliability and
Self-Improving Loops, listed above, now provide portable reliability and
feedback-loop examples.
The machine-specific monitoring and self-improvement deployment remains private.

## What the checks do not prove

A successful test run validates the included scenarios, not the entire private
system or the quality of a particular model. Tokens and hashes in the demo
correlate state; they are not authenticated identities. A real deployment needs
appropriate storage permissions and independent approval controls.

`make scan` looks for configured credential, contact and home-path patterns.
It does not establish complete privacy. This public repository starts from a
reviewed snapshot with a fresh history. Earlier private operating files and Git
history are not included.

## About me

I am an engineering manager who still builds. I design and run this harness
myself, and these repositories show the engineering choices behind it.

## License

MIT. See [LICENSE](LICENSE).
