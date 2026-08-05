---
name: perplexity-panel
description: Ask any model in the user's Perplexity subscription (GLM 5.2, Grok 4.5, Kimi K3, Nemotron 3 Ultra, Gemini 3.1 Pro, GPT-5.6 Terra, Claude Sonnet 5, Sonar 2) via their logged-in Chrome session, verify which model actually answered, and parse the reply into a structured findings ledger. Use for a second opinion from a different model family, cross-model verification of a claim or draft, or fanning one question across several models to compare. Reaches models the Perplexity API cannot serve — the API is Sonar-only, so the browser is the only route. For a full multi-stage PR review, see the review-relay skill, which uses this as one stage.
---

# Perplexity Panel

Make the user's Perplexity subscription callable. The developer API serves **Sonar
only** — GLM, Grok, Kimi, Nemotron, Gemini, GPT and Claude are reachable *only*
through the logged-in web app.

This skill is the *capability*: select a model, ask, verify provenance, parse the
answer. For the five-stage PR review workflow that uses it, see **`review-relay`**.
For review *method*, see **`trevor-review`**.

## Two rules that make the rest work

**Verify provenance, not clicks.** Positions shift between builds and viewports, so
don't try to make clicking reliable — make verification reliable. Every answer carries
`Prepared using <MODEL>`; assert on it.

- **Models don't know what they are.** Asked directly, Grok 4.5 answered "You are
  Perplexity." Self-report is worthless.
- **Selection is sticky and global**, persisting across new threads and page loads. A
  missed click silently leaves the *previous* model selected — this is how a
  four-family panel becomes one model answering four times. Verify per question.

**Panelists have no tools.** The model cannot read the repo, run a probe, or fetch a
URL. Everything must be inline. A prompt saying "review the rule in `foo.yml`" gets a
hallucinated review of a file it cannot see. Save the frozen prompt to disk — every
model must get byte-identical input, and the parser needs it to strip the echo.

## Procedure

Open a session:

```
tabs_context_mcp { createIfEmpty: true } → navigate perplexity.ai → screenshot
```

A sidebar of past sessions means logged in; a marketing page means stop and ask the
user to sign in. Never log in yourself.

**Select the model.** `find` does *not* locate the picker (absent from the
accessibility tree) — work from the screenshot. Click **"Model"**, screenshot, click
the target row, screenshot, confirm the composer footer names it.

| Model | Notes |
|---|---|
| Best | never use — provenance unpredictable |
| Sonar 2 | fast, also on the API |
| GPT-5.6 Terra | |
| GPT-5.6 Sol | **Max-only, locked** |
| Gemini 3.1 Pro | Thinking |
| Claude Sonnet 5 | your own family — weakest for cross-checking |
| Claude Opus 5 | **Max-only, locked** |
| Kimi K3 | Thinking |
| GLM 5.2 | Thinking |
| Grok 4.5 | fast |
| Nemotron 3 Ultra | Thinking |

Locked models refuse silently; the footer check catches it. Thinking variants cost
2–3 minutes — pick a fast model when breadth matters more than depth.

**Paste, don't type**: `pbcopy < frozen-prompt.txt`, click the composer, `key cmd+v`.
Submit with the send button — `Return` inserts a newline in a multi-line composer.

**Wait properly.** Short questions return in ~8s; a **Thinking model on a large
analytical prompt takes 2–3 minutes** (measured: GLM 5.2 Thinking, ~150s on a 10KB
review). Perplexity web-searches first even for pure reasoning; the composer's
"Search" toggle can be turned off when no sources are wanted.

Complete means: streaming control gone, `Prepared using` present, text stable across
two reads. An in-progress page shows the prompt echo and "Searching the web" with no
answer body — **parsing that yields a silently empty result.**

Capture with `get_page_text`, save to `raw-<model>.txt`, record the thread URL.

Run models **sequentially in one tab** — selection is global, so parallel tabs race
and mislabel each other.

## Output contract

When the answer must be machine-parsed, end the prompt with this verbatim —
`scripts/slurp-findings.py` parses exactly this shape:

```
===== OUTPUT FORMAT (follow exactly) =====
For each defect, one block:

FINDING <n>
SEVERITY: P1 (customer-facing false positive / obvious false negative / broken
  remediation) or P2 (bounded but material)
CLASS: false-positive | false-negative | asymmetry | severity | remediation | other
CLAIM: one sentence.
PROBE: the smallest exact snippet that demonstrates it.
EXPECTED: what happens on that snippet, and what should happen.
WHY: which specific lines cause this.

If you find nothing real, say NO FINDINGS. Do not pad with style nits. Precision
matters more than volume: a wrong finding costs more than a missed one.
```

## Slurp

```bash
scripts/slurp-findings.py --raw raw-glm.txt --prompt frozen-prompt.txt \
    --expect "GLM 5.2" --thread-url "https://www.perplexity.ai/search/..." \
    --out findings-ledger.jsonl
```

Refuses to write unless `Prepared using` exists and matches `--expect`, and strips the
prompt echo (which contains the literal word FINDING). Every record lands
`verdict: UNVERIFIED`. Append each model to the same ledger.

Non-zero exit is a **harness failure** — re-run that panelist, never record it as
clean. A panelist returning neither findings nor an explicit `NO FINDINGS` also fails;
that is a truncated read, not a quiet model.

## Using the results

Panel output is **claims, not findings**. Independent agreement across families is
corroboration, not proof — models share assumptions. Reproduce anything you intend to
act on: run the probe, read the code. A verdict resting on what an identifier
*probably* means is unproven.

Report which models actually answered. If one failed or was locked, say so rather than
implying a fuller panel than ran.

Prefer real family diversity — GLM, Grok, Kimi, Nemotron and Gemini are distinct
families. Two models from one family share blind spots.

## Failure modes

| Symptom | Meaning |
|---|---|
| Marketing page, no sidebar | not logged in — ask the user |
| Composer footer names another model | click missed, or Max-locked |
| `Prepared using` absent | still streaming — wait, do not parse |
| slurp exits non-zero | harness failure — re-run, never score as clean |
| Identical answers across models | selection isn't sticking; re-verify each footer |
| Model list won't open | narrow viewport or a modal; screenshot and resolve |
| Layout unrecognisable | Perplexity shipped a UI change; re-derive from screenshot |

## Constraints

- Drives the user's own logged-in session; keep volume comparable to human use and
  never bulk-scrape. Needs a visible, awake Chrome — not truly headless.
- The Perplexity **desktop app** cannot substitute: it blocks external accessibility
  inspection entirely, so the browser is the only route.
- For unattended runs, `sonar-reasoning-pro` via the Perplexity API works headlessly
  (a different family from Claude, just not the subscription models).

## Files

- `scripts/slurp-findings.py` — provenance-gated parser: answer text → ledger JSONL.
