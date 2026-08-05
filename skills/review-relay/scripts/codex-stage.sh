#!/bin/bash
# Stage 3 — Codex adjudication, invoked the one way that does not hang.
#
#   codex-stage.sh <adjudication-prompt.md> <run-dir> [model-args...]
#
# `codex exec` reads additional input from stdin whenever stdin stays open. Pass
# the prompt as an ARGUMENT and it blocks forever on
# "Reading additional input from stdin..." — indistinguishable from a slow model,
# which is why this wrapper exists rather than a bare command in the docs.
# The prompt therefore goes on STDIN and never in argv.
#
# Read-only and ephemeral: the adjudicator must not touch the tree it is ruling on.
# Its verdict is still a claim — stage 4 reproduces it like any other.

set -uo pipefail

PROMPT="${1:?usage: codex-stage.sh <adjudication-prompt.md> <run-dir> [model-args...]}"
RUN="${2:?usage: codex-stage.sh <adjudication-prompt.md> <run-dir> [model-args...]}"
shift 2

[ -s "$PROMPT" ] || { echo "codex-stage: prompt $PROMPT missing or empty" >&2; exit 1; }

SCHEMA="${VERDICT_SCHEMA:-$(dirname "$0")/../assets/verdict.schema.json}"
[ -s "$SCHEMA" ] || { echo "codex-stage: schema $SCHEMA missing" >&2; exit 1; }

mkdir -p "$RUN"

codex exec -s read-only --skip-git-repo-check --ephemeral \
  --output-schema "$SCHEMA" \
  -o "$RUN/raw-codex.json" \
  "$@" \
  < "$PROMPT"
RC=$?

# Surface the structured verdict on stdout so run-stage.sh sees real output and
# cannot record a silent no-op as a clean stage.
[ -s "$RUN/raw-codex.json" ] && cat "$RUN/raw-codex.json"

exit $RC
