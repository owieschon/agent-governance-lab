#!/usr/bin/env bash
# Observer protected set (D59, Bundle 4 phase A): rails/observers/ definitions
# and the runner are governor-adjacent -- they shape what the operator sees in
# the inbox -- so they join the protected set as a PATH-PREFIX rule whose
# protection does NOT depend on the files existing (the wall went up in phase
# A, before phase B created the inhabitants). To keep proving that property
# now that phase B ships real files, the harness REMOVES the dir first: every
# block below fires against a nonexistent path. rails/observers/state/ is the
# one agent-writable carve-out.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# the point of a prefix rule: protection precedes existence (harness clears
# the shipped phase-B files so the rule is exercised pre-existence)
rm -rf rails/observers
_assert "rails/observers does not exist for the RED half" 0 \
  "$([ -d rails/observers ] && echo 1 || echo 0)"

# --- RED: agent (worker) edits of definitions/runner are BLOCKED --------------
expect_blocked "Edit a (future) observer definition"  "$(agent_edit "$SANDBOX/rails/observers/sentry.json")"
expect_blocked "Edit the (future) runner"             "$(agent_edit "$SANDBOX/rails/observers/run_observer.sh")"
expect_blocked "shell write to the runner"            "$(agent_bash 'echo x >> rails/observers/run_observer.sh')"
expect_blocked "mv a file over the runner"            "$(agent_bash 'mv evil.sh rails/observers/run_observer.sh')"
expect_blocked "rm -rf rails/observers"               "$(agent_bash 'rm -rf rails/observers')"
expect_blocked "decoy state mention does not unlock"  "$(agent_bash 'echo x >> rails/observers/run_observer.sh # rails/observers/state/ok')"
# the state carve-out is resolved, not string-prefixed: a path that prefixes
# state/ but traverses back out to the runner must NOT unlock
expect_blocked "traversal out of state/ to the runner" "$(agent_bash 'echo x > rails/observers/state/../run_observer.sh')"

# --- GREEN: the state carve-out is agent-writable ------------------------------
expect_allowed "Edit a state file"                    "$(agent_edit "$SANDBOX/rails/observers/state/sentry.json")"
mkdir -p rails/observers/state
expect_allowed "shell write to state"                 "$(agent_bash 'echo x > rails/observers/state/ci.json')"
expect_allowed "shell rm of an own-state file"        "$(agent_bash 'rm rails/observers/state/ci.json')"
expect_allowed "rm -rf of the state dir itself"       "$(agent_bash 'rm -rf rails/observers/state')"

# --- GREEN: ordinary work is unaffected ----------------------------------------
expect_allowed "worker edit src/mod.py"               "$(agent_edit "$SANDBOX/src/mod.py")"
expect_allowed "ordinary scratch write"               "$(agent_bash 'echo hi > scratch.txt')"

finish
