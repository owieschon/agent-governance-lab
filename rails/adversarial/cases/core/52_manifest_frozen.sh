#!/usr/bin/env bash
# Manifest integrity: the manifest defines the dispatch's proof obligations
# (break plan, live-path greps, declared test changes). It is written by the
# agent, so if it can be rewritten AFTER the human approves, the agent grades
# itself against an answer key it changed. snapshot.sh freezes the manifest
# hash at approval; verify.sh's manifest_complete check fails on any
# post-approval drift. A real amendment re-approves, which re-snapshots.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

_assert "clean: verify PASS"                                   0 "$(run_verify)"
_assert "manifest_complete passes on the approved manifest" true "$(check_state manifest_complete)"

# the agent edits its own manifest after approval, without re-approval
python3 - <<'PY'
import json
p = "rails/dispatches/active/D-test/manifest.json"
m = json.load(open(p)); m["_tampered_after_approval"] = True
json.dump(m, open(p, "w"), indent=2)
PY
_assert "manifest changed after approval -> verify FAILs"      1 "$(run_verify)"
_assert "manifest_complete is the firing check"            false "$(check_state manifest_complete)"

# re-approval re-snapshots the manifest -> the freeze clears, verify PASSes
( bash rails/verifier/snapshot.sh D-test >/dev/null 2>&1 )
_assert "re-approval (re-snapshot) clears the freeze -> PASS" 0 "$(run_verify)"
_assert "manifest_complete passes against the re-frozen manifest" true "$(check_state manifest_complete)"
finish
