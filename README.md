# Review Relay

Three Claude Code skills that turn a PR review into a **relay across model families**:
Claude reviews first and proves what it can, then each later stage attacks the
accumulated ledger rather than re-reviewing from scratch, and Claude reproduces
everything at the end before anything ships.

```
0 CLAUDE        trevor-review first pass — establish object, find + PROVE     [deepest]
1 PERPLEXITY    GLM / Grok / Kimi / Nemotron — attack stage 0                 [cheap, broad]
2 ANTIGRAVITY   gemini-family review of the accumulated ledger                [cheap]
3 CODEX         gpt-family FINAL adjudication — resolve what is still open    [deep]
4 CLAUDE        reproduce everything, decide, commit + comment (approval gate) [deepest]
```

## Why a relay and not a fan-out

A fan-out asks five models the same question and counts votes. Models share
assumptions, so agreement is corroboration, not proof — and the vote hides the one
model that saw further than the rest.

In the relay, every stage receives what the previous stages concluded and is asked to
break it. **A later stage overturning Claude is the product, not noise.** In the run
that shaped these skills, stages 2 and 3 overturned Claude twice, and the most serious
defect surfaced at stage 2.

Two structural rules make it trustworthy:

- **Only stages 0 and 4 have tools.** Stages 1–3 cannot read the repo, run a probe, or
  fetch a URL — everything they need is inline, and everything they return is a *claim*
  until Claude reproduces it against the real artifact on the pinned engine.
- **A skipped provider is reported as skipped.** A three-stage relay described as four
  is a false claim about how much scrutiny the code received.

## The three skills

| Skill | What it is | Standalone use |
|---|---|---|
| `review-relay` | the five-stage **pipeline** — timing, skipping, hand-off, approval gate | run the whole relay |
| `trevor-review` | the review **method** used at stages 0 and 4 — adversarial, exact-head, customer-impact | an ordinary single-model review |
| `perplexity-panel` | the **capability** for driving Perplexity's subscription models at stage 1 | a one-off second opinion |

`review-relay` composes the other two and replaces neither.

## Install

```bash
git clone <this repo> review-relay
cp -R review-relay/skills/* ~/.claude/skills/
```

Or per-project, into `.claude/skills/` at the repo root. Then in Claude Code:

```
run the review relay on PR 1234
```

Claude picks the skill up from its description; you can also invoke `trevor-review` or
`perplexity-panel` by name for the narrower jobs.

## Optional supporting skills

`trevor-review` names a few skills it will pull in for subject-matter knowledge when they
happen to be installed — Python defect classes, CDK construct semantics, what makes a
fixture trustworthy. **None of them ship here and none of them are required.** A missing
one means that row is skipped and the reviewer does the work unaided; the method, the
evidence bar, and the P1/P2 gate are unchanged either way.

They are listed so you can install exactly the ones you want, from the original source
rather than a re-host.

| Skill | Install it if | Source | Licence |
|---|---|---|---|
| `python-programmer` | you review Python, or rules that target it | [Pyroxin/opinionated-claude-skills](https://github.com/Pyroxin/opinionated-claude-skills) `opinionated-python-development` | EPL-2.0 |
| `software-engineer` | findings turn on design — ownership boundaries, rule decomposition | same repo, `opinionated-software-engineering` | EPL-2.0 |
| `git-version-control` | you want worktree/branch discipline for the review object | same repo, `opinionated-software-engineering` | EPL-2.0 |
| `test-driven-development` | you fix findings as well as report them | [superpowers plugin](https://github.com/anthropics/claude-code) (official marketplace) | — |
| `test-design-philosophy` (rename on install — see below) | you review other people's fixtures | same repo, `opinionated-software-engineering` → `test-driven-development` | EPL-2.0 |
| `aws-cdk-development` | the artifact is CDK/CloudFormation or IaC | [zxkane/aws-skills](https://github.com/zxkane/aws-skills) `aws-iac` | MIT |
| `interactive-research` | upstream claims are contested and load-bearing | [Pyroxin/opinionated-claude-skills](https://github.com/Pyroxin/opinionated-claude-skills) `opinionated-research` | EPL-2.0 |

Two things worth knowing before you install any of them:

- **The two testing skills collide by name.** Superpowers ships
  `test-driven-development` and so does `opinionated-software-engineering`. Install the
  second under a different directory name (this setup calls it `test-design-philosophy`)
  and update its `name:` field to match, or one will shadow the other. They do different
  jobs — superpowers' owns the RED-GREEN-REFACTOR *process* when you're fixing; the other
  owns the *judgment* about whether a test is worth trusting when you're reviewing.
- **`software-engineer` declares itself mandatory.** Its upstream description ends
  "MUST ALWAYS be loaded when working on any kind of software development or design
  task!", which pulls ~1000 lines into every coding turn. Worth softening that line to a
  design/architecture trigger unless you want it always resident.
- **`aws-cdk-development` registers a hook.** Its frontmatter adds a `PreToolUse` hook
  that runs `aws sts get-caller-identity` once before any `cdk deploy`. It is read-only
  and useful — it prints the account you're about to deploy into — but it executes without
  prompting, so know it is there.

## What each stage needs

Every stage is optional except 0 and 4 — the relay skips what you don't have and says
so in the timing table.

| Stage | Needs | If missing |
|---|---|---|
| 0, 4 | Claude Code, the repo, the pinned analyzer | required |
| 1 | a Perplexity subscription + logged-in Chrome, and the Claude in Chrome extension | stage skipped |
| 2 | the `agy` CLI (Antigravity), authenticated | stage skipped |
| 3 | the `codex` CLI, authenticated | stage skipped |

Perplexity's **developer API is Sonar-only** — GLM, Grok, Kimi and Nemotron are reachable
only through the logged-in web app, which is why stage 1 drives a real browser rather
than an API.

## Layout of a run

```
<run>/frozen-context.md   self-contained artifact, built once, byte-identical to every stage
<run>/ledger.jsonl        every finding from every stage, accumulating
<run>/arbitration.md      Claude's verdicts + evidence, regenerated per stage
<run>/timings.tsv         stage / status / seconds / note
<run>/raw-<stage>.*       each stage's unmodified output
```

## Scripts

- `skills/review-relay/scripts/run-stage.sh` — times a stage and classifies the result.
  Exhaustion, auth failure and refusal are `SKIPPED` (relay continues); **empty output
  with a zero exit is `FAILED`**, because a silent no-op reads downstream as "this model
  found nothing", the most dangerous failure a review pipeline has.
- `skills/review-relay/scripts/codex-stage.sh` — stage 3 invoked the one way that does
  not hang. `codex exec` blocks forever on "Reading additional input from stdin" when the
  prompt is an argument and stdin stays open; this feeds it on stdin.
- `skills/review-relay/scripts/report-timings.sh` — per-stage table and wall-clock total.
- `skills/perplexity-panel/scripts/slurp-findings.py` — provenance-gated parser. Refuses
  to write unless the page's `Prepared using <MODEL>` line matches the model you asked
  for, because Perplexity's model selection is sticky and a missed click silently leaves
  the previous model selected — that's how a four-family panel becomes one model
  answering four times.

## The approval gate

Committing, pushing and posting a PR comment are outward-facing and irreversible. Stage 4
**prepares them, shows you, and stops.** Approval is per-PR and never carries forward.

## Notes

- Reference timings: a Perplexity Thinking model ≈150s, `agy` 2–60s by effort, Codex
  adjudication 1–5 min.
- If a relay is running long, cut stages 1 and 2 — never 0, 3 or 4.
- Stage 1 drives your own logged-in browser session. Keep the volume comparable to human
  use; it isn't a scraper.

## Licence

MIT — see `LICENSE`.
