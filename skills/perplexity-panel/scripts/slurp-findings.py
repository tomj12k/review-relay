#!/usr/bin/env python3
"""Parse a Perplexity panel answer into a structured findings ledger (JSONL).

Enforces the provenance gate before parsing anything: if the page does not carry
a `Prepared using <MODEL>` line matching the model we asked for, this exits
non-zero and writes nothing. A mislabelled panelist is a harness failure, never
a finding.

Usage:
  slurp-findings.py --raw page.txt --prompt frozen-prompt.txt \
      --expect "GLM 5.2" --thread-url https://... [--out ledger.jsonl]

Appends to --out so several panelists accumulate into one ledger.
"""
import argparse
import json
import re
import sys

FIELDS = ("SEVERITY", "CLASS", "CLAIM", "PROBE", "EXPECTED", "WHY")


def provenance(raw):
    """Return the model named by the page's `Prepared using` line, or None."""
    m = re.search(r"Prepared using\s+([^\n]+)", raw)
    return m.group(1).strip() if m else None


def normalise(s):
    """Loose model-name compare: GLM 5.2 / GLM-5.2 / glm5.2 all match."""
    return re.sub(r"[^a-z0-9]", "", s.lower())


def strip_prompt_echo(raw, prompt):
    """Perplexity echoes the whole prompt above the answer — and our prompt
    contains the literal word FINDING in its output-format section, which would
    otherwise parse as a finding. Cut everything up to the end of the echo."""
    tail = [ln.strip() for ln in prompt.strip().splitlines() if ln.strip()][-1]
    idx = raw.rfind(tail)
    return raw[idx + len(tail):] if idx != -1 else raw


def parse_findings(body):
    """Split on FINDING headers and pull the labelled fields out of each block."""
    blocks = re.split(r"\bFINDING\s+(\d+)\b", body)
    out = []
    for i in range(1, len(blocks) - 1, 2):
        num, text = blocks[i], blocks[i + 1]
        rec = {"finding": int(num)}
        for f in FIELDS:
            # Field runs until the next field label or the next FINDING.
            others = "|".join(x for x in FIELDS if x != f)
            m = re.search(
                rf"{f}:\s*(.*?)(?=\n\s*(?:{others}):|\bFINDING\s+\d+\b|\Z)",
                text,
                re.S,
            )
            rec[f.lower()] = " ".join(m.group(1).split()) if m else ""
        if rec["claim"]:
            out.append(rec)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--raw", required=True, help="get_page_text output")
    p.add_argument("--prompt", required=True, help="the frozen prompt that was sent")
    p.add_argument("--expect", required=True, help="model you selected, e.g. 'GLM 5.2'")
    p.add_argument("--thread-url", default="")
    p.add_argument("--out", default="findings-ledger.jsonl")
    a = p.parse_args()

    raw = open(a.raw, encoding="utf-8", errors="replace").read()
    prompt = open(a.prompt, encoding="utf-8", errors="replace").read()

    got = provenance(raw)
    if not got:
        sys.exit(
            "HARNESS FAILURE: no 'Prepared using' line — answer was still streaming, "
            "or the page never rendered one. Nothing parsed."
        )
    if normalise(a.expect) not in normalise(got):
        sys.exit(
            f"HARNESS FAILURE: asked for {a.expect!r} but page says 'Prepared using {got}'. "
            "The model click did not take (selection is sticky). Nothing parsed."
        )

    findings = parse_findings(strip_prompt_echo(raw, prompt))

    body = strip_prompt_echo(raw, prompt)
    if not findings and "NO FINDINGS" not in body.upper():
        sys.exit(
            f"HARNESS FAILURE: {got} returned neither parseable FINDING blocks nor "
            "'NO FINDINGS'. Do not score this as a clean panelist."
        )

    with open(a.out, "a", encoding="utf-8") as fh:
        for rec in findings:
            rec.update(
                model=got,
                thread_url=a.thread_url,
                verdict="UNVERIFIED",  # only the arbiter may change this
                corroborated_by=[],
            )
            fh.write(json.dumps(rec) + "\n")

    print(f"{got}: {len(findings)} finding(s) -> {a.out}")
    if not findings:
        print(f"{got}: explicit NO FINDINGS")


if __name__ == "__main__":
    main()
