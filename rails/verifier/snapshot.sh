#!/usr/bin/env bash
#
# snapshot.sh <dispatch-id>  -- record test/fixture file hashes at approval time.
#
# Run when a dispatch is APPROVED. verify.sh's oracle_integrity check compares
# the current hashes to this snapshot and FAILs on an undeclared test/fixture
# mutation -- the scorer/oracle-tampering defense (the agent leaves the checks
# intact and instruments the thing that grades it instead). Writes
# rails/dispatches/active/<id>/.oracle_snapshot.json. Lives in the trust layer.
#
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DID="${1:?usage: snapshot.sh <dispatch-id>}"

exec python3 "$ROOT/rails/verifier/snapshot.py" "$ROOT" "$DID"
