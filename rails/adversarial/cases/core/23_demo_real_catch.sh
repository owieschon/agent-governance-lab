#!/usr/bin/env bash
# Demo real-catch (Job 9a Part 2): the demo must DEMONSTRATE, never ASSERT --
# the catch it shows is the actual verifier producing an actual verdict against
# a real planted violation, and the demo cannot fake it. Both directions
# (blocks the tamper, passes whole work) and the anti-theater structure.
#
# Why this tests the demo's mechanism rather than nesting another fixture: the
# compatibility wrapper builds its own disposable repo. We reproduce its exact
# bad-code + moved-oracle pair in this already-built sandbox, and the ordinary
# suite MUST be demonstrably green before the governor is allowed to take credit.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

DEMO="rails/verifier/demo.sh"
DRIVER="rails/agl/demo.py"

# 1. anti-theater: the legacy path delegates to the canonical CLI; the driver
# invokes the real fixture, test command, and verifier and contains no baked
# verdict line.
_assert "legacy demo path delegates to agl" 1 "$([ "$(grep -c 'bin/agl.*demo' $DEMO)" -ge 1 ] && echo 1 || echo 0)"
_assert "demo hardcodes no BLOCKED verdict" 0 "$(grep -c 'VERDICT: BLOCKED' "$DRIVER")"
_assert "demo actually invokes the real verifier" 1 "$([ "$(grep -c 'rails/verifier/verify.sh' "$DRIVER")" -ge 1 ] && echo 1 || echo 0)"
_assert "demo builds a throwaway sandbox, not the live repo" 1 "$([ "$(grep -c 'rails/adversarial/fixture.sh' "$DRIVER")" -ge 1 ] && echo 1 || echo 0)"
_assert "demo emits a content-addressed receipt" 1 "$([ "$(grep -c 'write_receipt' "$DRIVER")" -ge 1 ] && echo 1 || echo 0)"
_assert "demo preserves both candidate snapshots" 1 "$([ "$(grep -c 'write_candidate_snapshot' "$DRIVER")" -ge 2 ] && echo 1 || echo 0)"

# 2. the catch is REAL: the bad implementation and weakened test agree, so
# plain tests pass. The governor must still block the candidate because the
# agent moved its own oracle.
python3 - <<'PY'
p = "src/mod.py"
t = open(p).read()
open(p, "w").write(t.replace(
    "    return a + b\n",
    "    if a < 0 and b < 0:\n        return 99\n    return a + b\n",
))
PY
sed_i 's/self.assertEqual(add(-2, -3), -5)/self.assertEqual(add(-2, -3), 99)/' tests/test_mod.py
python3 -m unittest discover -s tests >/dev/null 2>&1
_assert "bad change + moved oracle -> ordinary tests PASS" 0 "$?"
_assert "tampered green -> verify BLOCKS (real verdict, not narrated)" 1 "$(run_verify)"
_assert "the catch is oracle_integrity (cannot edit your own grader)" false "$(check_state oracle_integrity)"
_assert "the governor saw the full suite green" true "$(check_state full_suite)"

# 3. the other direction: whole work certifies (quiet on good, loud on bad)
( cd "$SANDBOX" && git checkout -q src/mod.py tests/test_mod.py )
_assert "restored work -> verify PASS (not a blanket blocker)" 0 "$(run_verify)"
_assert "oracle_integrity clean again (no false fire)" true "$(check_state oracle_integrity)"
finish
