#!/usr/bin/env bash
#
# why.sh [dispatch-id] -- the expansion behind the one-line verdict (Job 8 C1).
#
# Renders the LAST verdict for a dispatch in full: every check, its detail,
# the tree/commit/fingerprint it was stamped against, and where the evidence
# lives. Pure rendering over rails/evidence/<id>/verdict.json -- it computes
# nothing and asserts nothing the verifier did not already establish.
# Read-only; safe to run any time.
#
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="${1:-}"

if [ -z "$DISPATCH" ]; then
  # If exactly one dispatch has evidence, use it; otherwise ask.
  COUNT=0; ONLY=""
  for d in "$ROOT"/rails/evidence/*/verdict.json; do
    [ -f "$d" ] || continue
    base="$(basename "$(dirname "$d")")"
    [ "$base" = "ADVERSARIAL" ] && continue
    COUNT=$((COUNT + 1)); ONLY="$base"
  done
  if [ "$COUNT" -eq 1 ]; then
    DISPATCH="$ONLY"
  else
    echo "usage: why.sh <dispatch-id>   (found $COUNT dispatches with verdicts)" >&2
    exit 2
  fi
fi

V="$ROOT/rails/evidence/$DISPATCH/verdict.json"
if [ ! -f "$V" ]; then
  echo "no verdict exists for $DISPATCH yet. Run: bash rails/verifier/verify.sh $DISPATCH" >&2
  exit 1
fi

exec python3 "$ROOT/rails/verifier/why.py" "$V" "$DISPATCH"
