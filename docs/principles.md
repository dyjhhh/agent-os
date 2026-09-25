# Principles

These rules came out of daily use of my personal system. Each one has an incident behind it; most of those incidents are in the [incident log](incidents.md).

## 1. Humans sit at explicit gates

| Gate | Triggers on | Who waits | Shape of the wait |
|---|---|---|---|
| G1 outbound | anything that leaves the machine: email, external messages, form submissions, publishing | me, per item | a draft plus one line asking to send; no reply means no send, there is no timeout |
| G2 money and contracts | any amount, contract terms, accepting a quote, credit pulls, financing submissions | me | the adversarial gate runs first (a second model argues against), then I decide |
| G3 legal and identity | legal filings, tax positions | me and my advisers | the agents lay out facts and gaps and do not judge |
| G4 destructive | delete, overwrite, permission or sharing changes, bulk moves | me | a hook blocks selected patterns; only my own explicit instructions count as authorisation. The hook is not a complete security boundary |
| G5 one-way doors | signing, ordering, going public | me, after a negotiation-coach pass | the coach runs before I see the draft |
| G6 structural | changing another agent's future behaviour (a skill, a system prompt, an automation prompt) | nobody | reported after the fact, but it is only "staged" until that agent's first real output has been checked |
| no gate | maintenance that self-heals: stale audits, index repairs, cron reruns, config rollbacks | nobody | fix silently; escalate only after repeated failure that genuinely needs a person |

The gates sit before the action, not after the output. A human as the last wall is a human as the only wall.

## 2. A proxy signal never carries the heaviest conclusion

Every false alarm in the first months had the same shape: one cheap intermediate signal was allowed to draw the most expensive conclusion.

| Proxy | What it was taken to mean | What it actually means |
|---|---|---|
| process alive | agent responding | the process exists |
| prompt injected into the session | task done | text arrived in an input box |
| chat log modified | brief delivered | something was written |
| SSH key connects | account unlocked | key auth works |
| plist loaded | job fires | launchd knows the job exists |

The rule now: the heaviest conclusion needs an end-to-end artifact. A brief is delivered when a receipt exists after a confirmed send. An agent is responding when a probe message gets an answer. A fix is done when the thing that was broken produces a correct output.

## 3. Single source of truth is a citation discipline

A rule that is copied into a hook, a cron prompt or a replay template becomes a frozen copy that sits closer to the model than the canonical file. When the canon moves and the copy does not, the model follows the copy. One contract lives in one file; every injection point may only say "read that file, it wins on conflict". A private six-hourly guard fails if contract text appears anywhere outside its owner.

## 4. No automation without a goal card

Before a job ships, five fields: objective, output, a done-when that a machine can check, a failure cap and the gate row it belongs to. The morning brief once defined done as "the job started". The card forces done to mean "the operator received it".

## 5. One gate for alerts

In the private system most system alerts pass through one gate script: a white signal never pages; nothing pages in the first twenty minutes after boot or while the host has more than 12,000 sockets in TIME_WAIT; a red or yellow alert needs two confirming runs at least three minutes apart within six hours; the same alert is not repeated for six hours unless it escalates from yellow to red. Suppressed alerts are written to the handoff file so an agent fixes the cause. The person is paged only when a person must act. A few older watchdogs still message me directly. [agent-reliability](https://github.com/dyjhhh/agent-reliability) reimplements this policy as a tested demo with synthetic data; it is not the deployed script.

## 6. Done is an artifact, not a sentence

A scorer (`anticipatory_claim` in [agent-eval-gates/evals/scorers.py](https://github.com/dyjhhh/agent-eval-gates/blob/main/evals/scorers.py)) blocks the phrases that pre-pay a conclusion ("should be fine now", "won't happen again") unless the same line names an acceptance point. The allowed form is: deployed, the acceptance point is X, I will confirm at X.

## 7. Maintenance is silent

Transient failures (timeouts, network, token refresh) are retried and never reported. A job that gives me a message asserts that I need to do something. One older self-heal watchdog still reports its restarts; it predates this rule. If nothing is needed from me, the correct amount of notification is none. Cutting or downgrading a class of notification is itself reported, once, in the next brief.

## 8. A loop needs a landing place that is guaranteed to be read

Generating suggestions is cheap. Three self-improvement loops died the same death: they wrote into files nobody opened. Every loop now has exactly one consumer, the Monday brief, which quotes each loop's first line verbatim and lists what needs my decision. The private loops are not published; [self-improving-loops](https://github.com/dyjhhh/self-improving-loops) has a synthetic example of the approval and regression step.
