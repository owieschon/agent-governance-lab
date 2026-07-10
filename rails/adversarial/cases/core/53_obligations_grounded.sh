#!/usr/bin/env bash
# Obligations grounded on the diff (V1/V4): the manifest's proof obligations are
# agent-authored, so a decoy that points the break plan or a live-path grep at
# code the dispatch never touched would "prove" nothing about the real change.
# When a base ref was recorded at approval (basis.sh, HEAD before the build),
# verify.sh requires the break plan to target files the dispatch actually
# changed and a live-path grep to hit a changed file. Without a base ref the
# check is N/A, so this case records one and then exercises both directions.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# Approval records the base = current HEAD (the agent cannot write .base_ref;
# the trusted basis.sh does). Then the dispatch's real change touches the two
# files its manifest points at (break -> src/mod.py, grep -> src/main.py).
bash rails/verifier/basis.sh D-test >/dev/null 2>&1
printf '\n# dispatch change\n' >> src/mod.py
printf '\n# dispatch change\n' >> src/main.py

_assert "obligations on the dispatch's changed files -> verify PASS"   0 "$(run_verify)"
_assert "manifest_complete passes (break targets changed code)"     true "$(check_state manifest_complete)"
_assert "live_path passes (grep hits a changed file)"               true "$(check_state live_path)"

# DECOY break plan: target a file that exists in the base and was never changed.
python3 - <<'PY'
import json
p = "rails/dispatches/active/D-test/manifest.json"
m = json.load(open(p)); m["break_plan"][0]["files"] = ["src/__init__.py"]
json.dump(m, open(p, "w"), indent=2)
PY
bash rails/verifier/snapshot.sh D-test >/dev/null 2>&1   # re-approve (isolate from the freeze check)
_assert "decoy break plan (unchanged file) -> verify FAILs"            1 "$(run_verify)"
_assert "manifest_complete is the firing check"                    false "$(check_state manifest_complete)"

# Restore the real break; DECOY grep: match real code in a file the dispatch
# did NOT change (the test file), so the grep hits only pre-existing code.
python3 - <<'PY'
import json
p = "rails/dispatches/active/D-test/manifest.json"
m = json.load(open(p))
m["break_plan"][0]["files"] = ["src/mod.py"]
m["live_path_greps"] = [{"pattern": "def test", "path": "tests/test_mod.py"}]
json.dump(m, open(p, "w"), indent=2)
PY
bash rails/verifier/snapshot.sh D-test >/dev/null 2>&1
_assert "decoy live-path grep (only unchanged code) -> verify FAILs"   1 "$(run_verify)"
_assert "live_path is the firing check"                            false "$(check_state live_path)"
finish
