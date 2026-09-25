# Personal Agent OS

[![tests](https://github.com/dyjhhh/agent-os/actions/workflows/test.yml/badge.svg)](https://github.com/dyjhhh/agent-os/actions/workflows/test.yml)

I build and operate a personal agent system with shared state, evaluation checks,
human review and recovery workflows. Three agents use it across two Macs for
research, documents and daily operations. I use Claude Code and Codex as coding
tools and review the changes myself.

This repository makes part of that work runnable without access to my accounts
or private data. The question behind the first example is simple:
**when a new session picks up a task, how does it know what actually happened?**

## Run the continuity example

Python 3.10 or newer and Make are enough. No model, account or network required.

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
[Read the tests](examples/continuity/test_continuity.py)

This is a new, simplified extraction of the private system's design. It uses
synthetic data and SQLite in place of the private Git transaction adapter.
It is a personal-project example, not an employer system or a claim of
enterprise deployment.

## Three parts of the portfolio

| Repository | Focus | Start with |
|---|---|---|
| **This repository** | Shared state, task handoffs and recovery | [Continuity demo](examples/continuity/) |
| [Agent Eval Gates](https://github.com/dyjhhh/agent-eval-gates) | Output checks and evidence-bound review | [Artifact preflight demo](https://github.com/dyjhhh/agent-eval-gates/tree/main/examples/evidence-release) |
| [Agent Security Hooks](https://github.com/dyjhhh/agent-security-hooks) | Bounded tool guards and input screening | [Coverage and limitations](https://github.com/dyjhhh/agent-security-hooks/blob/main/docs/security.md) |

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
- [Synthetic skill examples](skills/README.md): two contracts written for this
  repository, rather than copies of personal operating instructions.

The `agents/` and `launchd/` directories contain sanitized reference excerpts.
They assume a private runtime layout and are **not installed by the quickstart**.
The continuity example is the self-contained entry point. Additional monitoring
and self-improvement modules remain private.

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

I am an engineering manager interested in AI products, developer tools and
reliable platforms. These projects are a way to stay hands-on and make the
engineering choices behind my own AI workflows visible.

## License

MIT. See [LICENSE](LICENSE).
