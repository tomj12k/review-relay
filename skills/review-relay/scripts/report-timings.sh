#!/bin/bash
# Print the relay's per-stage timings and wall-clock total.
#   report-timings.sh <run-dir>
set -uo pipefail
T="${1:?usage: report-timings.sh <run-dir>}/timings.tsv"
[ -f "$T" ] || { echo "no timings recorded at $T" >&2; exit 1; }

awk -F'\t' '
BEGIN { printf "%-14s %-8s %8s  %s\n", "STAGE", "STATUS", "SECONDS", "NOTE" }
{
  printf "%-14s %-8s %8s  %s\n", $1, $2, $3, $4
  total += $3
  if ($2 == "OK")      ok++
  if ($2 == "SKIPPED") skipped++
  if ($2 == "FAILED")  failed++
}
END {
  printf "%-14s %-8s %8d\n", "TOTAL", "", total
  printf "\n%d ok, %d skipped, %d failed", ok+0, skipped+0, failed+0
  if (skipped+failed > 0)
    printf "  <-- report these as non-participating stages, not as clean reviews"
  printf "\n"
  if (total >= 60) printf "wall clock: %dm %ds\n", total/60, total%60
}' "$T"
