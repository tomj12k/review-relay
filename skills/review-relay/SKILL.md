---
name: review-relay
description: Run a multi-model adversarial review of a PR, diff, or detection rules as a relay — Claude reviews first with trevor-review, hands off to Perplexity's subscription models, then Antigravity/Gemini, then Codex as final adjudicator, then back to Claude to reproduce every claim, decide what ships, and prepare the commit and PR comment. Each stage critiques the previous stages rather than re-reviewing from scratch. Times every stage, skips exhausted providers, and concentrates thinking budget in Claude and Codex. Use when asked to review a PR with multiple models, run the review relay, or get cross-model verification before merging.
---

# Review Relay

```
0 CLAUDE        trevor-review first pass — establish object, find + PROVE     [deepest]
1 PERPLEXITY    GLM / Grok / Kimi / Nemotron — attack stage 0                 [cheap, broad]
2 ANTIGRAVITY   gemini-family review of the accumulated ledger                [cheap]
3 CODEX         gpt-family FINAL adjudication — resolve what is still open    [deep]
4 CLAUDE        reproduce everything, decide, commit + comment (approval gate) [deepest]
```

**A relay, not a fan-out.** Every stage receives the accumulated ledger and attacks
it. Stage 3 overturning stage 0 is the product, not noise — in the run that validated
this, stages 2 and 3 overturned Claude twice and the most serious defect surfaced at
stage 2.

**Only stages 0 and 4 have tools.** Stages 1–3 cannot read the repo, run a probe, or
fetch a URL. Everything they need is inline; everything they return is a *claim* until
Claude reproduces it.

Composes two other skills, neither of which this one replaces:
- **`trevor-review`** — the review *method* (stages 0 and 4). Use it standalone for an
  ordinary single-model review.
- **`perplexity-panel`** — the *capability* for driving Perplexity models (stage 1).
  Use it standalone for a one-off second opinion.

## Thinking budget

Depth is not spread evenly. Claude is the biggest thinker; Codex is the deep
adjudicator; the middle stages are broad and cheap.

| Stage | Effort | Why |
|---|---|---|
| 0 Claude | maximum | Only stage that can run probes. Findings it proves here need no re-litigation later. |
| 1 Perplexity | low | Breadth across families. Prefer **non-Thinking** models (Grok 4.5, Sonar 2) — Thinking variants cost 2–3 min each for marginal gain at this stage. Use GLM/Kimi/Nemotron Thinking only when stage 0 found little. |
| 2 Antigravity | low–medium | `--effort low` by default; raise to `medium` only if stage 1 was skipped. |
| 3 Codex | high | Final adjudicator; its ruling shapes what ships. Worth the time. |
| 4 Claude | maximum | Reproduces every claim and owns the decision. |

If the relay is running long, cut stages 1 and 2 first — never 0, 3 or 4.

## Timing and skipping

Wrap every non-Claude stage:

```bash
scripts/run-stage.sh "$RUN" pplx-grok -- <command...>
scripts/run-stage.sh "$RUN" agy       -- agy -p "$(cat arbitration.md)" ...
scripts/run-stage.sh "$RUN" codex     -- scripts/codex-stage.sh "$RUN/adjudication.md" "$RUN"
scripts/report-timings.sh "$RUN"
```

It records `stage / status / seconds / note` to `timings.tsv` and exits 0 on both OK
and SKIPPED so the chain continues past a dead provider.

**Exhaustion is a skip, not a stop.** Quota, credit, rate-limit, auth, and refusal
patterns are detected and the stage is marked `SKIPPED` — the relay moves on. Empty
output with a zero exit is marked `FAILED`, because a silent no-op reads downstream as
"this model found nothing", which is the single most dangerous failure in a review
pipeline.

**Always report skipped stages.** A three-stage relay reported as four is a false
claim about how much scrutiny the code received. Say which families actually ran.

Report the per-stage table and wall-clock total at the end via
`report-timings.sh`. Measured reference points: Perplexity Thinking model ≈150s,
`agy` ≈2–60s depending on effort, Codex adjudication ≈1–5 min.

## Working directory

```
<run>/frozen-context.md   self-contained artifact (built once, byte-identical to every stage)
<run>/ledger.jsonl        every finding from every stage, accumulating
<run>/arbitration.md      Claude's verdicts + evidence, regenerated per stage
<run>/timings.tsv         stage / status / seconds / note
<run>/raw-<stage>.*       each stage's unmodified output
```

## Stage 0 — Claude (trevor-review)

Invoke `trevor-review` for the method. Establish the object first: exact head SHA,
base SHA, changed files, and the **pinned** analyzer version read from the binary, not
the path. Never review a moving branch.

Produce `frozen-context.md` (everything a tool-less model needs — artifact in full,
fixtures, exposure objective, what "correct" means, measured behaviour so far) and
`ledger.jsonl` (Claude's findings, each with probe, paired control, verdict).

Claude's findings enter the relay as claims too. Invite later stages to refute them.

## Stage 1 — Perplexity

Follow `perplexity-panel` for the mechanics — provenance gating, sticky selection,
streaming detection, and the slurp step are all documented there and are easy to get
silently wrong.

Assign families the relay lacks: Codex covers gpt, Antigravity covers gemini, you are
claude — so spend this stage on **GLM, Grok, Kimi, Nemotron**. Keep effort low; this
is the breadth stage.

## Stage 2 — Antigravity / Gemini

```bash
agy -p "$(cat arbitration.md)" --model gemini-3.1-pro-high --effort low \
    --output-format json --json-schema assets/verdict.schema.json \
    --print-timeout 300s
```

Parse `.structured_output`; gate on `.status == "SUCCESS"`. Prompt goes as an argument
(unlike Codex). Ask what the arbiter missed and whether any stage-1 finding was
accepted or dismissed too readily.

`agy model` needs a TTY and fails headless — pass `--model` directly. All agy-backed
models share one quota, so when it is exhausted every one fails at once; `run-stage.sh`
catches that and skips.

## Stage 3 — Codex (final adjudicator)

Last before hand-back, so its job is **resolving what is still open**, not a fourth
opinion. Give it the artifact, Claude's arbitration, Perplexity's findings, and
Gemini's adjudication, and ask it to rule on every disagreement plus what *all* stages
missed.

```bash
scripts/codex-stage.sh "$RUN/adjudication.md" "$RUN"
```

**Feed the prompt on stdin.** Passing it as an argument while stdin stays open makes
`codex exec` block forever on "Reading additional input from stdin..." — it looks like
a slow model and is a hang. `codex-stage.sh` does this correctly; if you invoke
`codex exec` by hand and must pass an argument, redirect `< /dev/null`.

`assets/verdict.schema.json` is the output schema, and the same one stage 2 uses — one
shape for both adjudication stages so their rulings collate without translation.

Its ruling is still a claim. Stage 4 reproduces it like any other — a final
adjudicator that is never checked just relocates the trust problem to the last model
in the chain.

## Stage 4 — Claude final

Reproduce every claim not already reproduced. Run each probe against the real artifact
on the pinned engine:

- `CONFIRMED` — reproduced. Only this ships as a finding.
- `REFUTED` — did not reproduce; keep it with the reason. It calibrates the panel.
- `UNPROVEN` — plausible from reading, not executed.

**Reading is not reproducing.** State which verdicts came from a live run.

**Pair every probe with a control** differing in exactly one variable, and check the
control isolates what you think. A probe firing proves the rule matched *something*;
only the control proves it matched the thing you blame. The subtler trap: a control
whose silence you read as "correct" may itself be a second defect. A verdict resting
on what an identifier *probably* means is UNPROVEN, not CONFIRMED.

**Adjudicate against the artifact, not by vote.** Cross-family agreement is
corroboration, not proof — models share assumptions. Collapse findings sharing one
root cause, but keep severities separate when one root cause produces both a minor
false positive and a serious miss.

Then apply trevor-review's stop condition and P1/P2 bar and write up: verdict, which
stage raised it, live-run vs inspection, probe and control. Report what was refuted and
why. Report the timing table. Name the stages that actually ran.

### Approval gate

Committing, pushing, and posting a PR comment are outward-facing and irreversible.
**Prepare them, show the user, and stop.** Never push or post without explicit approval
in this session; approval for one PR never carries to the next.

When approved: branch off the base rather than committing to `main`, never
`--no-verify`, run the repo's build gate first, and post one consolidated comment in
trevor-review's structure — exact head SHA, pinned tool versions, ranked findings with
probes and controls, disposition of refuted claims, and the verification matrix.
Attribute the review only to models that actually ran.

## Failure modes

| Symptom | Meaning |
|---|---|
| Stage marked SKIPPED | provider exhausted/unauthenticated — report as non-participating |
| Empty output, exit 0 | silent no-op — FAILED, never "found nothing" |
| `codex exec` hangs on "Reading additional input from stdin" | prompt passed as arg with stdin open |
| `agy` empty or refusing | quota exhausted, or prompt asked for exploit strings |
| Every finding UNPROVEN | stage 4 didn't really run |
| All stages agree instantly | check they received the ledger, not just the artifact |
| Relay running long | cut stages 1–2, never 0/3/4 |

## Files

- `scripts/run-stage.sh` — time a stage, detect exhaustion, skip vs fail.
- `scripts/codex-stage.sh` — stage 3 invoked the one way that does not hang.
- `scripts/report-timings.sh` — per-stage table + wall-clock total.
- `assets/verdict.schema.json` — structured-output schema for stages 2 and 3.
