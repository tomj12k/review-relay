#!/bin/bash
# Run one relay stage: time it, detect exhaustion, never let a dead stage look clean.
#
#   run-stage.sh <run-dir> <stage-name> -- <command...>
#
# Appends a row to <run-dir>/timings.tsv:
#   stage <TAB> status <TAB> seconds <TAB> note
# status: OK | SKIPPED | FAILED
#
# Exit 0 on OK *and* on SKIPPED, so the caller's chain continues past an
# exhausted provider. Exit 1 only on FAILED (a real error worth stopping for).
# The distinction matters: SKIPPED means "this family did not participate" and
# MUST be reported as such — never counted as a stage that found nothing.

set -uo pipefail
RUN="$1"; STAGE="$2"; shift 2
[ "${1:-}" = "--" ] && shift

mkdir -p "$RUN"
TIMINGS="$RUN/timings.tsv"
OUT="$RUN/raw-$STAGE.out"
ERR="$RUN/raw-$STAGE.err"

record() { printf '%s\t%s\t%s\t%s\n' "$STAGE" "$1" "$2" "$3" >> "$TIMINGS"; }

START=$(date +%s)
"$@" > "$OUT" 2> "$ERR"
RC=$?
ELAPSED=$(( $(date +%s) - START ))

blob=$(cat "$OUT" "$ERR" 2>/dev/null)

# Exhaustion / unavailability — skip and continue. Patterns seen in practice:
#   agy    : shared Antigravity quota, all agy models die at once
#   codex  : ChatGPT plan usage limits
#   pplx   : API credit exhaustion or auth failure
if printf '%s' "$blob" | grep -qiE \
   'quota reached|quota exceeded|out of credits|insufficient_quota|insufficient credit|rate limit|429|usage limit|plan limit|too many requests|billing|payment required|402'; then
  record SKIPPED "$ELAPSED" "provider exhausted — stage did not participate"
  echo "SKIP $STAGE (${ELAPSED}s): provider exhausted, continuing relay" >&2
  exit 0
fi

if printf '%s' "$blob" | grep -qiE 'not (logged in|authenticated)|unauthorized|401|please (run )?login|re-?auth'; then
  record SKIPPED "$ELAPSED" "not authenticated — stage did not participate"
  echo "SKIP $STAGE (${ELAPSED}s): not authenticated, continuing relay" >&2
  exit 0
fi

# A refusal is a failed member, never an empty review.
if printf '%s' "$blob" | grep -qiE "I can'?t help with|cannot assist with|I'?m not able to help"; then
  record SKIPPED "$ELAPSED" "model refused the prompt — reframe as analysis, not payloads"
  echo "SKIP $STAGE (${ELAPSED}s): refused, continuing relay" >&2
  exit 0
fi

if [ "$RC" -ne 0 ]; then
  record FAILED "$ELAPSED" "exit $RC"
  echo "FAIL $STAGE (${ELAPSED}s): exit $RC — see $ERR" >&2
  exit 1
fi

# Empty output with a zero exit is a silent no-op, the worst failure mode:
# it reads downstream as "this model found nothing".
if [ ! -s "$OUT" ]; then
  record FAILED "$ELAPSED" "empty output despite exit 0 — silent no-op"
  echo "FAIL $STAGE (${ELAPSED}s): empty output, do NOT score as clean" >&2
  exit 1
fi

record OK "$ELAPSED" ""
echo "OK   $STAGE (${ELAPSED}s)" >&2
