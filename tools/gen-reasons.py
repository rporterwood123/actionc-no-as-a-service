#!/usr/bin/env python3
"""Generate reasons.txt (pipe-joined, single line) from canonical reasons.json.

The ActionC program splits on '|'. No reason in reasons.json contains a pipe,
newline, or tab, so a single-line pipe-joined file is unambiguous. We assert
that invariant rather than trust it.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
src = ROOT / "reasons.json"
dst = ROOT / "reasons.txt"

reasons = json.loads(src.read_text(encoding="utf-8"))
if not isinstance(reasons, list) or not reasons:
    sys.exit("reasons.json must be a non-empty JSON array")

bad = [r for r in reasons if "|" in r or "\n" in r or "\t" in r]
if bad:
    sys.exit(f"{len(bad)} reason(s) contain a pipe/newline/tab; pick a different delimiter")

dst.write_text("|".join(reasons), encoding="utf-8")
print(f"wrote {dst} ({len(reasons)} reasons, {dst.stat().st_size} bytes)")
