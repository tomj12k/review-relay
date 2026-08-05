---
name: trevor-review
description: Perform exact-head, adversarial, customer-impact security detection PR reviews and remediation follow-ups in Trevor's evidence-heavy style. Use for reviewing Semgrep or other static-analysis rules, validating reported PR findings, fixing review comments, checking false positives/negatives, ownership/deduplication, severities, tests, documentation, and posting a convergence-focused GitHub review.
---

# Trevor Review

Apply Trevor's observable review method without impersonating him. Attribute every
posted review to the actual reviewer/model; use the user's required label, or
`Codex/GPT-5.6@xhigh` by default.

This skill owns the review **method** and is self-contained in that respect. Do not load
another detection-review skill unless the user explicitly requests it.

## Supporting skills

Load these for *subject-matter* knowledge the method needs. None of them replaces a step
here, and none of them relaxes the evidence bar: whatever they tell you is a reason to go
look, never a substitute for a probe.

**All optional — load if available.** They are separate installs, and this skill does not
ship them. A missing one means you skip that row and do the work unaided; it does not mean
the review is degraded or blocked. Never report a review as incomplete because a
supporting skill was absent, and never tell the user to install one mid-review — note it
at the end if it would genuinely have helped. The repo's README lists sources and licences
for anyone who wants them.

| Load | When | What it buys the review |
|---|---|---|
| `python-programmer` | the rule targets Python, or the code under review is Python | Names the defect classes worth probing for — mutable default arguments, bare `except:`/swallowed errors, `eval`/`exec` on untrusted input, string-concatenated SQL, missing context managers — and the tools that produce evidence rather than opinion (`ruff` incl. its `S` security rules, `bandit`, `pydoclint`, `ty`/`mypy`/`pyright`). Also fixes which Python version's semantics you are arguing about, which decides whether a "vulnerable state" is still reachable. |
| `test-design-philosophy` | judging a PR's fixtures, or writing the regression required before a fix | Supplies the standard for "is this fixture evidence?". Directly serves two rules here: *passing self-authored fixtures proves only that the checked-in contract executes*, and *a fixture asserting a shape IS vulnerable carries a finding's burden of proof*. Its mock-at-boundaries rule is how you tell a real coverage gap from an over-mocked test that never exercised the rule. |
| `git-version-control` | establishing the review object, or preparing the commit after fixes | Worktree and branch discipline for "work in a clean isolated clone, preserve unrelated user changes", and the atomic-commit standard for the fix-up commits. Its checkpoint pattern gives you a restore point before an edit without bypassing hooks. |
| `software-engineer` | a finding turns on design rather than detection — ownership boundaries, rule decomposition, whether a guard belongs in rule A or rule B | Vocabulary for arguing about abstraction boundaries, which is what the *handover guard* and *duplicate coverage* sections are really about. Skip it for ordinary pattern-level findings; it is a large skill and most findings do not need it. |
| `test-driven-development` (superpowers) | **fixing** a finding, not reviewing one | The RED-GREEN-REFACTOR discipline behind this skill's rule that a regression asserting the customer-visible oracle goes in *before* the rule is edited. Its value here is the order: watch the regression fail against the pre-fix head, so you know it detects the defect rather than merely passing after the fix. |
| `aws-cdk-development` | the artifact is CDK/CloudFormation, or the rule targets IaC | The construct semantics behind an IaC finding — whether a property the rule flags is actually the one that governs the exposure, and whether CDK's L2 defaults already set it safely. Its `scripts/validate-stack.sh` is a read-only `cdk synth` + template check, usable as a probe harness. Carries a `PreToolUse` hook that prints the target AWS account before any `cdk deploy`. |
| `interactive-research` | an upstream claim is load-bearing, contested, and not settled by one doc page | Serves the step *"verify unstable API/runtime claims against current primary upstream documentation"*. Its per-claim epistemic labels map onto this skill's own CONFIRMED/UNPROVEN split, and its `fact-checker` agent verifies one claim against one source in a fresh context — useful when you need a check that wasn't primed by the review thread. |
| `deep-research` | never load it to do research | A routing notice only. It disambiguates "deep research" and hands off to `interactive-research`. |

## Choosing between the two testing skills

They have confusingly similar names and opposite triggers:

- **`test-driven-development`** (superpowers) — the *process*. Use when **making** a fix.
- **`test-design-philosophy`** — the *judgment*. Use when **reviewing** someone's tests:
  is this fixture evidence, is the mock boundary in the right place, does a green suite
  prove anything.

A review that reaches for the process skill and a fix that reaches for the judgment skill
are both the wrong way round.

## Research is bounded here

`interactive-research` spawns a persistent agent team — one context window per teammate,
resident until dismissed. That is disproportionate for the usual review question, which is
"does this library still accept this config?" and is answered by one `WebFetch` of the
upstream docs. Reach for the team only when a claim is genuinely contested across sources
and the finding turns on it. Fetching one doc page is not research; do that inline.

**None of these are review authorities.** A rule is not correct because
`python-programmer` says the idiom is fine, a fixture is not sound because
`test-design-philosophy` approves its shape, and a claim is not established because a
research agent labelled it well-supported. Every verdict still rests on a probe run
against the real artifact on the pinned engine, with its paired control. Research raises
or lowers your *prior*; only the probe produces a finding.

## Establish the review object

1. Fetch the PR's exact head SHA, base SHA, changed files, checks, issue comments,
   inline comments, and submitted reviews.
2. Identify the requested reviewer's latest feedback by verified account identity.
3. State whether reviewing the whole batch or only commits since a prior reviewed SHA.
4. Work in a clean isolated clone/worktree. Preserve unrelated user changes.
5. Pin and report the actual analyzer, pack, and supporting-tool versions.

Never review a moving symbolic branch without recording the exact SHA.

## Review from the customer backward

For every changed detection, independently decide:

- Does the matched behavior create the security impact asserted by the message?
- Is attacker control, dangerous configuration, or exploit wiring proven?
- Would a customer know what to change from the finding?
- Is the severity justified? Treat LOW as likely noise. Require an explicit product
  rationale for MEDIUM audit signals. Require strong exploit evidence for HIGH.
- Does an onboarded rule already own the same sink/CWE? Check production packs,
  coverage matrices, normalization, canonical selection, and real product deduplication.
- Do common real application shapes create obvious false positives or false negatives?
- Do rule comments, messages, fixtures, coverage docs, and PR descriptions agree?

Passing self-authored fixtures proves only that the checked-in contract executes. It
does not prove that the contract is sound or useful.

### Prove the impact, not just the flow

Reaching a sink is not reaching the consequence in the message. Ask what precondition
the claimed impact needs, and whether the rule establishes it:

- "unrestricted upload -> RCE" needs a web-served or executable destination, not merely
  an attacker-influenced filename reaching a move;
- "ReDoS" needs the pattern executed against attacker-sized input, not merely a regex
  constructed from user data;
- "timing oracle" needs a server secret, an attacker-controlled comparand, and a
  remotely observable difference — an identifier NAME establishes none of the three.

A rule that proves only the flow is an audit signal. Say so, and price it accordingly.

Read the rule's OWN fixtures as evidence about the claim, not merely as pass/fail
rows. A ReDoS rule whose vulnerable fixture executes the built regex against the
fixed five-character string `"value"` has shipped a fixture that cannot exhibit
catastrophic backtracking — the artifact intended to demonstrate the impact quietly
refutes it. When the fixture contradicts the message, the message is the thing that
is wrong.

### Read the message as a promise, then test the promise

The message is the customer contract. Read it first, then ask whether the patterns
establish exactly that. Messages naming a specific type, library, or API while the
sinks match any receiver of that method name are a recurring defect, and the gap is
invisible from the pattern alone.

### Check the severity mapping and the batch distribution

Find where analyzer severity becomes customer severity (in this product,
`scanners/common/sarif.py` maps ERROR -> HIGH and WARNING -> MEDIUM) and state it.
Then judge the batch as a whole: a set that is nearly all HIGH with no LOW is itself
evidence that severity was not considered per rule.

### Check the vulnerable state is still reachable

Verify the library still ACCEPTS the configuration the rule calls dangerous. A finding
for a state current versions refuse to load — a config that raises on boot, a header a
framework rejects, an API removed upstream — is correct-looking and unexploitable. It
costs a triage and teaches nothing. Name the version and the guard.

### Check duplicate coverage across the whole product

Rule-pack-internal dedup is not enough. Look at the other scanners' detector
registries and at what the deduplicator actually collapses. Two deterministic sources
that the deduper deliberately keeps separate means a new rule becomes an additional
finding for the same customer action, not a replacement.

Duplicates do not have to share a line. One rule matched a hoisted options object
across `L41-44` while another matched the call at `L43` — one cookie, two findings,
adjacent lines. Every check keyed on START LINE reported "no duplicates" while a
customer would plainly see the same cookie reported twice. Compare match SPANS and
the underlying customer action, not start lines, or the check certifies the defect.

### Make a handover guard mirror the receiving rule's REACH, not its intent

When rule A hands a shape to rule B, the natural guard matches the shape — and that
is wrong. Wherever B's pattern cannot actually reach the shape, excluding it from A
leaves it owned by NOBODY. Both failure directions are live: guard too little and the
shape is reported twice, guard too much and it disappears.

Write A's guard as a copy of B's OWN pattern so it inherits B's blind spots exactly.
Ownership then tracks B's measured coverage automatically instead of tracking what
you hoped B covered, and the two rules cannot drift apart on the next edit. Verify
both directions on one fixture: every shape has exactly one owner, and none has zero.

Copy it LITERALLY and diff the two pattern texts. Paraphrasing is how this fails: a
guard written for `const`/`let`/`var` against a receiver that recognises only `const`
silently orphaned both `let` and `var` — ordinary spellings that had been actionable
findings before the handoff. Every form the guard lists and the receiver does not
becomes unowned, so the diff is the check. Test ownership per SPELLING, not per
shape: one representative of a shape passing proves nothing about its siblings.

### Check the coverage and inventory documentation

A PR that changes the rule inventory, severities, or ownership without updating the
coverage matrix leaves the onboarding record wrong. Treat it as a P2.

A cross-repo companion goes stale the moment the rule changes again. One written
accurately at an early head described behaviour two commits later had already
replaced, and by merge time it OVERCLAIMED — asserting coverage the rule did not
have. Re-sync the companion immediately before merge, not when it was first written,
and diff it against the shipped behaviour rather than against your memory of it.

### Re-aim every "remove once X" comment that governs a security constraint

A removal trigger is an INSTRUCTION to a future maintainer, and it goes stale silently.
A dependency pin raised to clear a second, later advisory kept a comment naming only
the first advisory's floor — so following the comment as written would have resolved to
a version still carrying the newer CVE. The pin was correct and the instruction beside
it was not.

Any removal trigger, TODO, or "safe to drop when…" note must name the HIGHEST
constraint it clears and be updated in the same edit as the constraint itself.
Otherwise it is a documented instruction to reintroduce a vulnerability. This applies
to any repo, not only detection work: check pins, waivers, suppressions, feature flags,
and ignore-file entries whenever the PR moves the thing they govern.

## Build adversarial evidence

For each suspected defect:

1. Read the actual rule and relevant product code.
2. Verify unstable API/runtime claims against current primary upstream documentation
   or implementation.
3. Create the smallest syntax-correct probe that expresses the real customer shape.
4. Include a nearby positive or negative control when it distinguishes a rule defect
   from parser/type limitations.
5. Scan the probe with the individual rule and the complete production/custom pack.
6. Record findings, locations, severities, duplicates, and analyzer errors.
7. Reproduce before requesting a change. Do not infer behavior from rule prose.

Prefer ordinary framework idioms over exotic syntax. Test helpers, factories, injected
clients, aliases, reassignment, shadowing, mixed SDKs, current API spellings, safe
remediation, and ownership boundaries when relevant.

### Reason about the grammar of the program being invoked

When a rule reasons about how ANOTHER program parses input — argv and option syntax,
format strings, shell quoting, SQL dialect, template syntax — the exposure depends on
that program's grammar, not on the calling code's shape. Check it, and prefer a runtime
demonstration over reading:

```
$ tar tf --help
tar: --help: No such file or directory      # -f consumed it as the FILENAME
```

That one command decides whether `system("tar", "-xf", user_input)` is option injection
or a safe operand. Position matters: a value after a flag that TAKES an argument is an
operand and can never be an option, while a value after a subcommand or a flag that
takes none is genuinely injectable. If the engine cannot model the arity of preceding
flags, say so and bound the rule to the position it can defend.

### Verify a suppressor ENGAGES, rather than inferring it from the output

A fix that edits a NEGATIVE pattern — `pattern-not`, a sanitizer, an exclusion —
has two ways to produce a clean run: the guard matched and permitted, or the guard
matched nothing at all. These are indistinguishable downstream, and the second is a
silent no-op wearing the first's clothes.

Widening a guard's regex to accept an extra delimiter is the classic version. It is
plausible, it validates clean, and it can change nothing whatsoever — a metavariable
does not bind a template literal, so `sameSite: ` + backtick + `none` never reached
the regex being widened. Confirm the guard's OWN match exists (extract it into a
standalone rule and run it) before believing the fix works.

### Find which branch produced the match before guarding it

In a rule with many `pattern-either` arms, "which arm fired?" is a real question with
a real answer, and reading the arm nearest your probe's shape is not how you get it.
A hoisted-options call was matched by a general local-options branch four hundred
lines away that contained no literal `secure: false` at all, while the explicit-false
branch that looked responsible was irrelevant. Bisect it: lift a single arm into its
own rule and scan the probe. Guarding the wrong branch produces exactly the same
symptom as a guard that does not work.

Know what the engine's operators actually compare, too. `pattern-not` tests range
EQUALITY, so a multi-statement sequence can never suppress a single-statement match;
containment is `pattern-not-inside`. Reaching for the wrong one reads as an engine
limitation and is not.

### Run the recommended remediation against the matched probe

False remediation is not only a sanitizer that fails to neutralise. It is also advice
that BREAKS working code. Apply the message's fix to the exact shape the rule matched
and confirm both that the finding clears and that the code still functions. Inserting
`--` before a value that is already an operand makes `--` the operand and breaks the
command — advice that is wrong AND destructive is worse than no rule.

### Prove a "false negative" is a vulnerability before fixing it

A shape the rule does not match is not automatically a miss. Establish that the missed
shape is genuinely exploitable BEFORE widening anything. Widening a rule to "catch" a
safe shape converts a non-issue into a false-positive class, and the fixture added
alongside it then defends the defect. This is a measured failure mode, not a
hypothetical: it is how the tar operand case entered a rule that was previously correct.

### Narrowing an over-match creates a false-negative surface — probe it at once

The dual of the rule above, and the more common mistake. Fixing a false positive by
adding a type, base-class, receiver or scope anchor does not merely remove the noise;
it removes everything that fails to spell the anchor your way.

An over-broad header-injection rule was narrowed to `class $H(BaseHTTPRequestHandler)`.
The anchor is correct and the false positive is gone — but the ordinary stdlib
spelling `class H(http.server.BaseHTTPRequestHandler)` no longer matches, and a HIGH
detection now misses the canonical form. The narrowing was never probed with the
idiomatic ways the anchored thing is actually written.

So: immediately after narrowing, probe the spellings of whatever you narrowed TO —
module-qualified, aliased import, re-export, indirect subclass, mixin, multiple
inheritance. Then decide EXPLICITLY which of those the rule covers and record it. An
anchor is a claim about how the world writes code, and it needs the same evidence as
any other claim.

## Address review comments

Apply every check below to the WHOLE RULE, not to the fix you are looking at. The
characteristic failure is local success: each principle held for the targeted change
and was never re-applied to the rule around it, so one commit narrowed a sink into a
false negative, added an arm outside the existing guards, and broadened a handover
guard past its receiver — while every targeted probe stayed green. If a check is
worth running on the line you touched, it is worth running on the rule you touched it in.

When asked to fix findings:

1. Reproduce every comment on the exact pre-fix head.
2. Add a regression asserting the customer-visible oracle before editing the rule.
3. Make the smallest root-cause fix.
4. Retain a positive control so a false-positive fix cannot silently erase coverage.
5. Test normalized/deduplicated product output when ownership is involved.
6. Update rule commentary, messages, fixtures, coverage docs, and PR descriptions.
7. Capture the rule's output at the committed baseline BEFORE editing, then diff the
   working tree against it over the same fixtures. An expectations table encodes what
   you believed when you wrote it; the baseline encodes what the code actually did.
   Only the diff proves a finding is newly introduced rather than pre-existing.
8. Re-run the edited rule's ENTIRE fixture contract — vulnerable, safe, repaired, and
   every limitation fixture — not only the case you targeted. Editing one arm has
   repeatedly deleted an adjacent guard: removing a rule's name-matching arms also
   removed its reassignment suppressor, and only the SAFE fixture caught it. Targeted
   probes stay green through exactly this class of damage.
9. Re-measure expected line numbers after any formatter runs. Reformatting a fixture
   shifts them, and a table copied from the pre-format run fails only in CI.
10. Re-run every gate the rule has already passed, not just its fixtures. A gate
    result describes the rule AS MEASURED and expires the moment the rule changes.
11. Commit and push only after the focused and full verification matrices pass.

A comment describing a guard is not evidence the guard exists. A rule's name anchor
was deleted in an earlier edit while its six-line explanatory comment survived intact:
the rule documented a constraint it no longer had, read as correct to anyone reviewing
by eye, and re-broke a safe fixture. When a comment claims a constraint, grep for the
constraint. This cuts both ways when YOU edit — a surgical deletion that leaves the
surrounding prose in place manufactures exactly this trap for the next reviewer.

A fixture asserting that a shape IS vulnerable is a claim carrying the same burden of
proof as a finding. Check in a wrong one and the green suite defends the defect from
then on — it reads as intended behaviour to every later reviewer.

### A new match arm does not inherit the rule's existing exclusions

Exclusions are written against the arms that existed when they were written. Add an
arm and it enters the rule OUTSIDE every guard already there, which lands the new
false positives precisely on the remediated cases the guards were built to protect.

A cookie rule whose `secure:` exclusions inspected inline object literals gained a
hoisted-options arm. The arm matched; the exclusions did not follow it; and the rule
began reporting `{ sameSite: "none", secure: true }` — its own advertised fix, and the
exact thing the batch's own withholding criterion forbids. After adding an arm, run
every existing exclusion against it and treat guards as per-arm until proven shared.

### A gate result expires when the rule changes

Measuring that a rule is silent on its advertised remediation licenses a decision —
to ship it, to price it MEDIUM, to promote it out of incubation. That license is
attached to the measured rule, not to the rule's name. Edit the rule afterwards and
the citation silently becomes false: a "every advertised remediation is silent" claim
was true when measured, and false by the time it was written into a commit message
two arms later. Re-run the gate as part of the edit, not once at decision time.

### The probe grid is not the contract

The controls that justified a fix must be CHECKED IN beside the fixture they guard.
Scratch probes are how you learn something; fixtures are how the repository keeps it.

This one is easy to miss because nothing looks wrong: a CSV rule's sanitizer fix was
justified by a grid containing the unprefixed negative controls, they were correct,
and they never left `/tmp`. The checked-in `repaired.py` gained only the two silent
cases, so nothing in the suite would catch a future relaxation that also suppressed
the vulnerable spellings. A control that exists only in your scratch directory
protects the code for exactly as long as your session lasts.

### If you enumerate, say you enumerated

An enumeration cannot support a completeness claim. Three template-literal casings
shipped under a rule contract promising "every casing", and the mixed-case neighbour
had no owner in the whole pack. Either use a mechanism that is genuinely general — a
case-insensitive regex rather than a list — or state the enumeration as an
enumeration in the contract, and put a member the list does NOT cover into the
ownership fixture so the gap is visible rather than asserted away.

Prefer convergence over enumerating syntax indefinitely. If a search-mode regex is
acting as a type system, sanitizer proof, or scope resolver, remove the unsound arm
when a bounded false negative is acceptable. Do not respond to each delimiter failure
by extending a delimiter list.

## Re-review after fixes

Confirm the reported probes and their controls first. Then inspect the adjacent semantic
boundary once, looking for a root-cause regression rather than demanding completeness
over an unbounded syntax space.

Use this stop condition:

- all confirmed customer-impact defects are fixed;
- remaining false positives/negatives are explicit, bounded, owned, and accepted;
- severities and product-feed decisions have named owner acceptance;
- production ownership/deduplication is tested;
- the small final delta has no new P1/P2 issue.

Do not restart an unlimited whole-batch adversarial loop after every narrow fix unless
the new delta reveals another systematic defect.

## Verification matrix

Run and report, as applicable:

- exact regression probes and paired controls;
- a baseline-vs-working-tree diff over the edited rule's whole fixture contract, so a
  newly introduced finding is distinguishable from a pre-existing one;
- focused rule, normalizer, and deduplication tests, with ownership checked by match
  SPAN rather than start line — adjacent-line duplicates pass a line-keyed check, and
  per SPELLING rather than per shape (`const`/`let`/`var`, bare/qualified/aliased);
- every gate the rule previously passed, re-run against the CURRENT rule;
- confirmation that the controls justifying each fix are checked in beside the fixture
  they guard, not left in a scratch probe directory;
- full custom-rule tests and the repository build;
- analyzer scan/config parse errors;
- the repository's production validation path;
- strict/experimental validators separately, clearly labeling discrepancies;
- `git diff --check` over the reviewed range;
- hosted CI and product security scans;
- clean worktree and remote-head equality.

Never describe an expected-failure ledger as a merge gate. State the number and customer
meaning of open false-positive and false-negative cases.

Separate the two kinds of xfail, because they are not equally acceptable:

- An xfail asserting that SECURE, message-recommended code still produces a finding is
  a shipped false positive with a test blessing it. It is a product defect, not an
  engine gap, and "it is documented" does not make it acceptable. Fix it, demote the
  severity, or get named owner acceptance.
- An xfail asserting that genuinely vulnerable code is NOT reported is an honest recall
  gap. Pin it, name what would close it, and let it XPASS itself out of existence when
  the engine improves.

Both belong in the ledger; only the second is a limitation.

## Assign priorities

Report only actionable P1/P2 items in the main review:

- **P1:** customer-facing HIGH false positive, obvious/common severe false negative,
  duplicate finding, false remediation, broken production rule/config path, or a
  systematic defect spanning rules.
- **P2:** bounded but material customer noise/coverage gap, missing regression or
  documentation that can mislead onboarding, or an unresolved product decision.

Keep lower-value polish out of the blocking review.

## Write the PR review

Use this structure:

```markdown
Codex/GPT-5.6@xhigh

[Convergence-focused or independent] review of [range], exact head `[SHA]`.

[State which earlier fixes are real and the overall disposition.]

1. **[P1/P2] Outcome-focused finding title.**

   Explain the violated customer contract, show a minimal executable probe, report
   observed output, link exact rule lines and primary upstream evidence, and request
   the smallest convergent fix plus regression control.

Disposition of other reviewed points:

- Explain accepted limits, non-blocking tooling discrepancies, and product decisions.

Verification: exact head; pinned tool versions; focused/full counts; validator status;
`git diff --check`; hosted checks; probe parse/scan errors.
```

Use direct, neutral language. Distinguish real fixes from remaining issues. Do not claim
that green CI proves soundness. If the user requires direct PR feedback, always post the
review; when no findings remain, post a labeled no-additional-P1/P2 convergence comment.
