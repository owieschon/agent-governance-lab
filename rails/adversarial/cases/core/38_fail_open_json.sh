#!/usr/bin/env bash
# Fail-open on bad JSON parse: guard_bash.py exits 0 (allow) on unparseable
# stdin. If the agent can craft input that fails json.load, ALL commands pass
# unguarded. The fix makes guard_bash.py fail CLOSED (exit 2) on parse error.
source "$(dirname "$0")/../../lib.sh"

# ---- honest neighbor: normal commands still work ----
expect_allowed "normal bash command"           "$(agent_bash 'ls -la')"
expect_allowed "git status"                    "$(agent_bash 'git status')"

# ---- the attack: send malformed JSON to the guard ----
# Simulate what happens if the guard receives broken JSON
MALFORMED_RC="$(echo 'NOT VALID JSON {{{' | CLAUDE_PROJECT_DIR="$SANDBOX" python3 "$SANDBOX/.claude/hooks/guard_bash.py" >/dev/null 2>&1; echo $?)"
_assert "malformed JSON -> guard BLOCKS (fail closed)" 2 "$MALFORMED_RC"

# ---- empty input ----
EMPTY_RC="$(echo '' | CLAUDE_PROJECT_DIR="$SANDBOX" python3 "$SANDBOX/.claude/hooks/guard_bash.py" >/dev/null 2>&1; echo $?)"
_assert "empty input -> guard BLOCKS (fail closed)" 2 "$EMPTY_RC"

# ---- truncated JSON ----
TRUNC_RC="$(echo '{"tool_input": {"command": "git push' | CLAUDE_PROJECT_DIR="$SANDBOX" python3 "$SANDBOX/.claude/hooks/guard_bash.py" >/dev/null 2>&1; echo $?)"
_assert "truncated JSON -> guard BLOCKS (fail closed)" 2 "$TRUNC_RC"

# ---- guard_files.py same treatment ----
FMALFORM_RC="$(echo 'NOT VALID JSON' | CLAUDE_PROJECT_DIR="$SANDBOX" python3 "$SANDBOX/.claude/hooks/guard_files.py" >/dev/null 2>&1; echo $?)"
_assert "guard_files: malformed JSON -> BLOCKS (fail closed)" 2 "$FMALFORM_RC"

# ---- honest neighbor: well-formed but benign commands still pass ----
expect_allowed "well-formed benign command"    "$(agent_bash 'echo hello')"
expect_blocked "well-formed push still caught" "$(agent_bash 'git push origin main')"

finish
