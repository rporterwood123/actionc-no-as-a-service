#!/bin/sh
# Post-install smoke test for the `naas` command.
set -eu

NAAS="$HOME/.local/bin/naas"
[ -x "$NAAS" ] || { echo "FAIL: $NAAS not installed (run ./install.sh)"; exit 1; }

# Run 10x: each line must be non-empty; collect for a variation check.
out=$(mktemp)
trap 'rm -f "$out"' EXIT   # clean up the temp file even on an early FAIL exit
i=0
while [ "$i" -lt 10 ]; do
    line=$("$NAAS")
    [ -n "$line" ] || { echo "FAIL: empty output on run $i"; exit 1; }
    echo "$line" >> "$out"
    i=$((i + 1))
done

# Expect more than one distinct reason across 10 runs (random index works).
distinct=$(sort -u "$out" | wc -l)
rm -f "$out"
[ "$distinct" -gt 1 ] || { echo "FAIL: no variation across 10 runs"; exit 1; }

# Runs from an unrelated cwd (wrapper cd makes it location-independent).
( cd / && "$NAAS" >/dev/null ) || { echo "FAIL: errored from cwd=/"; exit 1; }

echo "PASS: naas prints varied, non-empty reasons ($distinct distinct in 10 runs)"
