#!/usr/bin/env bash
# Push via indirection: the push boundary must hold regardless of how git push
# is invoked. Two layers of defense:
#   1. guard_bash.py full-command regex (catches /usr/bin/git, env, bash -c, etc.)
#   2. git pre-push hook (fires at the git layer — structural, not bypassable
#      from the shell regardless of indirection form)
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# ---- honest neighbors: normal git and shell work still allowed ----
expect_allowed "git status"                    "$(agent_bash 'git status')"
expect_allowed "git log"                       "$(agent_bash 'git log --oneline -5')"
expect_allowed "git diff"                      "$(agent_bash 'git diff HEAD')"
expect_allowed "echo git push in a string"     "$(agent_bash 'echo "git push is blocked"')"
expect_allowed "grep for push in docs"         "$(agent_bash 'grep -r push docs/ || true')"

# ---- direct push (baseline, already covered by case 07) ----
expect_blocked "direct git push"               "$(agent_bash 'git push origin main')"

# ---- indirection forms: guard_bash full-command scan ----
expect_blocked "/usr/bin/git push"             "$(agent_bash '/usr/bin/git push origin main')"
expect_blocked "env git push"                  "$(agent_bash 'env git push origin main')"
expect_blocked "bash -c 'git push'"            "$(agent_bash 'bash -c "git push origin main"')"
expect_blocked "command git push"              "$(agent_bash 'command git push origin main')"

# ---- structural layer: pre-push hook ----
_assert "pre-push hook is installed" 0 "$([ -f .git/hooks/pre-push ] && echo 0 || echo 1)"

# The hook must block unless ALICE_PUSH_OK=1
# Set up a bare repo as a remote to test actual push
BARE="$(mktemp -d)"
git init -q --bare "$BARE"
git remote add test-bare "$BARE" 2>/dev/null || true

# Push without ALICE_PUSH_OK -> blocked by hook
PUSH_RC=0
git push test-bare main 2>/dev/null || PUSH_RC=$?
_assert "pre-push hook blocks push (no ALICE_PUSH_OK)" 1 "$([ "$PUSH_RC" -ne 0 ] && echo 1 || echo 0)"

# Push WITH ALICE_PUSH_OK=1 -> allowed (the human's floor act)
PUSH2_RC=0
ALICE_PUSH_OK=1 git push test-bare main 2>/dev/null || PUSH2_RC=$?
_assert "pre-push hook allows push with ALICE_PUSH_OK=1" 0 "$PUSH2_RC"

rm -rf "$BARE"
finish
