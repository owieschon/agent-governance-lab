#!/usr/bin/env bash
# Precondition-masked pass (Job 7 Part 1, class C): a load-bearing test that is
# collected but SKIPPED / xfailed / never-run is a silent no-op -- present-by-
# name satisfies load_bearing, yet no assertion executed and the suite stays
# green. Caught by exercised_assertions (per-test accounting).
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

_assert "clean -> verify PASS"                                  0 "$(run_verify)"
_assert "exercised_assertions passes when the LB test runs"  true "$(check_state exercised_assertions)"

# plant a skip on the load-bearing test: still collected, never asserts
python3 - <<'PY'
p = "tests/test_mod.py"
s = open(p).read().replace(
    "    def test_add_positive(self):",
    "    @unittest.skip(\"masked precondition\")\n    def test_add_positive(self):")
open(p, "w").write(s)
PY
python3 - <<'PY'
import json
p = "rails/dispatches/active/D-test/manifest.json"
m = json.load(open(p)); m["test_changes"] = ["tests/test_mod.py"]
json.dump(m, open(p, "w"), indent=2)
PY

_assert "suite stays GREEN with the load-bearing test skipped" 0 "$(PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests >/dev/null 2>&1; echo $?)"
_assert "skipped load-bearing test -> verify FAILs"            1 "$(run_verify)"
_assert "exercised_assertions is the check that fired"     false "$(check_state exercised_assertions)"
_assert "load_bearing still PASSES (present by name) -- the gap C closes" true "$(check_state load_bearing)"
finish
