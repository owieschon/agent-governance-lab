#!/usr/bin/env bash
#
# basis.sh <dispatch-id>  -- record the base commit (HEAD at approval, before
# the agent builds) so verify.sh can tie the dispatch's proof obligations to
# the code it actually changed. Run at approval, alongside snapshot.sh.
#
# Writes rails/dispatches/active/<id>/.base_ref. Lives in the trust layer;
# .base_ref is agent-read-only (the guards block agent writes), so the agent
# cannot widen the base to make a decoy look "changed."
#
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DID="${1:?usage: basis.sh <dispatch-id>}"
D="$ROOT/rails/dispatches/active/$DID"
mkdir -p "$D"
if HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"; then
  printf '%s\n' "$HEAD" > "$D/.base_ref"
  echo "base ref: $HEAD recorded for $DID"
else
  echo "base ref: no git HEAD yet -- skipped for $DID (verify will not tie obligations to a diff)"
fi
