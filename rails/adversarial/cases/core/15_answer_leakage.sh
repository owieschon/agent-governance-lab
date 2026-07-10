#!/usr/bin/env bash
# Answer-leakage / solution-in-the-test (Job 7 Part 1, class B): a load-bearing
# test whose expected value is produced by the implementation it grades proves
# nothing -- the assertion is true by construction and the suite stays green.
# Caught by oracle_independence (scoped to load-bearing tests).
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

_assert "clean load-bearing test -> verify PASS"               0 "$(run_verify)"
_assert "oracle_independence passes on an independent oracle" true "$(check_state oracle_independence)"

# plant a self-referential oracle: compare the impl to itself
python3 - <<'PY'
p = "tests/test_mod.py"
s = open(p).read().replace("self.assertEqual(add(2, 3), 5)",
                           "self.assertEqual(add(2, 3), add(2, 3))")
open(p, "w").write(s)
PY
# name the changed file so oracle_integrity is satisfied -> isolate this check
python3 - <<'PY'
import json
p = "rails/dispatches/active/D-test/manifest.json"
m = json.load(open(p)); m["test_changes"] = ["tests/test_mod.py"]
json.dump(m, open(p, "w"), indent=2)
PY

_assert "the vacuous self-referential test still passes the suite" 0 "$(PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.test_mod >/dev/null 2>&1; echo $?)"
_assert "self-referential oracle -> verify FAILs"              1 "$(run_verify)"
_assert "oracle_independence is the check that fired"      false "$(check_state oracle_independence)"
finish
