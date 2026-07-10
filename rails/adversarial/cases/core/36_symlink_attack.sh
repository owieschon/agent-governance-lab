#!/usr/bin/env bash
# Symlink attack: guard_files.py used os.path.abspath() which does NOT resolve
# symlinks. An agent can ln -s a protected file to an unprotected path, then
# write through the symlink. The fix is os.path.realpath().
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# ---- honest neighbors: normal writes to unprotected paths ----
expect_allowed "write to src/mod.py (normal)"  "$(agent_edit "$SANDBOX/src/mod.py")"
expect_allowed "write to src/main.py (normal)" "$(agent_edit "$SANDBOX/src/main.py")"

# ---- direct write to protected path (baseline, already covered) ----
expect_blocked "direct write to verify.sh"     "$(agent_edit "$SANDBOX/rails/verifier/verify.sh")"
expect_blocked "direct write to guard_bash.py" "$(agent_edit "$SANDBOX/.claude/hooks/guard_bash.py")"

# ---- symlink attack: link protected -> unprotected, write via link ----
ln -s "$SANDBOX/rails/verifier/verify.sh" "$SANDBOX/src/sneaky_link.py"
LINK_RESULT="$(agent_edit "$SANDBOX/src/sneaky_link.py")"
_assert "write via symlink to verify.sh is BLOCKED" 2 "$LINK_RESULT"
rm -f "$SANDBOX/src/sneaky_link.py"

ln -s "$SANDBOX/.claude/hooks/guard_bash.py" "$SANDBOX/tests/another_link.py"
LINK_RESULT2="$(agent_edit "$SANDBOX/tests/another_link.py")"
_assert "write via symlink to guard_bash.py is BLOCKED" 2 "$LINK_RESULT2"
rm -f "$SANDBOX/tests/another_link.py"

# ---- symlink to load-bearing test ----
LB_FILE="$SANDBOX/tests/test_mod.py"
ln -s "$LB_FILE" "$SANDBOX/src/lb_link.py"
LB_RESULT="$(agent_edit "$SANDBOX/src/lb_link.py")"
_assert "write via symlink to load-bearing test is BLOCKED" 2 "$LB_RESULT"
rm -f "$SANDBOX/src/lb_link.py"

# ---- symlink to baseline.json ----
ln -s "$SANDBOX/rails/verifier/baseline.json" "/tmp/innocent_$$.txt"
BASE_RESULT="$(agent_edit "/tmp/innocent_$$.txt")"
_assert "write via symlink to baseline.json (outside repo) is BLOCKED" 2 "$BASE_RESULT"
rm -f "/tmp/innocent_$$.txt"

# ---- non-symlink write to the same unprotected paths works ----
expect_allowed "write to src/sneaky_link.py (no symlink)" "$(touch "$SANDBOX/src/sneaky_link.py" && agent_edit "$SANDBOX/src/sneaky_link.py")"
rm -f "$SANDBOX/src/sneaky_link.py"

finish
