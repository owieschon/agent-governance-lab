#!/usr/bin/env bash
#
# receipt.sh <dispatch-id> -- render the shareable receipt (Job 8 Part C3).
#
# A receipt is RENDERING over existing verified data: the claim, the plain
# summary, the catch count, the decisions, and a PROVENANCE line (commit,
# governor fingerprint, a content hash of the actual evidence files, and the
# pointer back to the run). It computes and asserts NOTHING the verifier did
# not already establish -- a receipt is a view of evidence, never a new
# source of it. It renders only a PASS; there is no receipt for unverified
# work. Deterministic: every field comes from the evidence on disk (the
# timestamp is the verdict's, not the render clock), so re-rendering an
# unchanged run yields a byte-identical receipt and the provenance still
# resolves.
#
# Receipts carry their provenance; to trust one you didn't generate, follow
# it to its run. (Equally: a receipt whose provenance doesn't resolve proves
# nothing.)
#
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="${1:-}"
if [ -z "$DISPATCH" ]; then
  echo "usage: receipt.sh <dispatch-id>" >&2
  exit 2
fi

V="$ROOT/rails/evidence/$DISPATCH/verdict.json"
if [ ! -f "$V" ]; then
  echo "no receipt: no verdict exists for $DISPATCH. Run: bash rails/verifier/verify.sh $DISPATCH" >&2
  exit 1
fi

OUT="$ROOT/rails/handoff/$DISPATCH.receipt.md"
mkdir -p "$ROOT/rails/handoff"

exec python3 "$ROOT/rails/verifier/receipt.py" "$ROOT" "$DISPATCH" "$V" "$OUT"
