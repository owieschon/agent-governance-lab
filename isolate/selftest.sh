#!/usr/bin/env bash
#
# selftest.sh -- prove the isolation boundary actually holds, on a host that has
# a container engine. Run this before relying on isolate/run.sh. It asserts the
# two properties the in-process guards cannot enforce:
#   1. an interpreter write to the trust layer FAILS (read-only mount; this is
#      the AUDIT.md "B4" bypass the host-side guards miss);
#   2. a push attempt FAILS (no network).
#
# Exit 0 = boundary holds. Exit 1 = it does not -- do not rely on it.
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. interpreter write to a read-only trust-layer file must fail.
W="$(bash "$HERE/run.sh" python3 -c '
import sys
try:
    open("rails/verifier/verify.sh", "a").write("# tamper\n")
    print("WROTE")            # boundary FAILED -- the file was writable
except OSError as e:
    print("BLOCKED", e.errno) # expected: read-only filesystem (EROFS=30)
' 2>/dev/null | tr -d "\r")"

# 2. a push must fail with no network.
P="$(bash "$HERE/run.sh" bash -c '
git push origin main >/dev/null 2>&1 && echo PUSHED || echo BLOCKED
' 2>/dev/null | tr -d "\r")"

ok=0
case "$W" in BLOCKED*) echo "  ok   interpreter write to the trust layer is blocked ($W)";; *) echo "  FAIL interpreter write was NOT blocked (got: ${W:-<none>})"; ok=1;; esac
case "$P" in BLOCKED*) echo "  ok   push is blocked (no network)";; *) echo "  FAIL push was NOT blocked (got: ${P:-<none>})"; ok=1;; esac

if [ "$ok" -eq 0 ]; then echo "isolation boundary holds."; else echo "isolation boundary DOES NOT hold -- do not rely on it."; fi
exit "$ok"
