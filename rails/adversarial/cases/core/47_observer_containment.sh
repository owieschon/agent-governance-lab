#!/usr/bin/env bash
# Observer containment (D59, Bundle 4 phase A): an observer is an outer loop
# whose ONLY write privilege is creating NEW files in rails/dispatches/inbox/
# and its own state under rails/observers/state/. Everything else -- source,
# tests, the governor surface, hooks, evidence, dispatches, existing inbox
# items -- is guard-blocked, not prompt-discouraged. The human dispatch gate
# stays exactly where it is: observers propose, the human approves, the inner
# loop implements.
#
# RED half: observer-posture writes outside inbox+state are blocked via the
# real hooks. GREEN half: a NEW inbox item and a state write succeed; reads
# of the work tree stay open.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

_assert "observer posture file exists" 1 \
  "$([ -f rails/verifier/postures/observer.json ] && echo 1 || echo 0)"

observer_edit() {  # observer_edit <file-path> -> echoes hook exit code
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1]}}))' "$1" \
    | CLAUDE_PROJECT_DIR="$SANDBOX" CLAUDE_AGENT_NAME=observer \
      python3 "$SANDBOX/.claude/hooks/guard_files.py" >/dev/null 2>&1
  echo $?
}
observer_bash() {  # observer_bash <command> -> echoes hook exit code
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" \
    | CLAUDE_PROJECT_DIR="$SANDBOX" CLAUDE_AGENT_NAME=observer \
      python3 "$SANDBOX/.claude/hooks/guard_bash.py" >/dev/null 2>&1
  echo $?
}

mkdir -p rails/dispatches/inbox

# --- RED: writes outside inbox + own state are BLOCKED -----------------------
expect_blocked "observer edit src/mod.py"               "$(observer_edit "$SANDBOX/src/mod.py")"
expect_blocked "observer edit tests/test_mod.py"        "$(observer_edit "$SANDBOX/tests/test_mod.py")"
expect_blocked "observer edit rails/verifier/verify.sh" "$(observer_edit "$SANDBOX/rails/verifier/verify.sh")"
expect_blocked "observer edit a hook"                   "$(observer_edit "$SANDBOX/.claude/hooks/guard_bash.py")"
expect_blocked "observer edit evidence (verdict)"       "$(observer_edit "$SANDBOX/rails/evidence/D-test/verdict.json")"
expect_blocked "observer edit its own definition"       "$(observer_edit "$SANDBOX/rails/observers/sentry.json")"
expect_blocked "observer edit the runner"               "$(observer_edit "$SANDBOX/rails/observers/run_observer.sh")"
expect_blocked "observer edit a dispatch manifest"      "$(observer_edit "$SANDBOX/rails/dispatches/active/D-test/manifest.json")"

# shell writes are default-denied for a restricted posture: Edit/Write is the
# channel, with proper path resolution (same default-deny law as the reviewer)
expect_blocked "observer shell write to src/"           "$(observer_bash 'echo x >> src/mod.py')"
expect_blocked "observer shell write even to inbox"     "$(observer_bash 'echo x > rails/dispatches/inbox/new.md')"
expect_blocked "observer eject (floor)"                 "$(observer_bash 'bash rails/verifier/eject.sh')"

# --- RED: create-only holds INSIDE the writable set --------------------------
echo "human spec" > rails/dispatches/inbox/existing-item.md
expect_blocked "observer edit an EXISTING inbox item"   "$(observer_edit "$SANDBOX/rails/dispatches/inbox/existing-item.md")"

# --- GREEN: the two permitted writes ------------------------------------------
expect_allowed "observer creates a NEW inbox item"      "$(observer_edit "$SANDBOX/rails/dispatches/inbox/obs-ci-fail-20260612.md")"
expect_allowed "observer writes its own state"          "$(observer_edit "$SANDBOX/rails/observers/state/ci.json")"

# --- GREEN: the observer can still SEE the world ------------------------------
expect_allowed "observer reads source"                  "$(observer_bash 'cat src/mod.py')"
expect_allowed "observer reads git log"                 "$(observer_bash 'git log --oneline -1')"

finish
