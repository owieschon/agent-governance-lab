#!/usr/bin/env bash
# L5 footprint (Job 8 Part D1): in the default (quiet) install, the kit's
# entire footprint on the workflow is the verdict line and the catastrophic
# floor -- NOTHING else is blocked, required, moved, or reformatted. The
# behavior surface is probed action by action: everything outside the floor
# set must be allowed, the floor itself is proven held by case 18. Also
# proves the other side: standard keeps the ceremony the user opted into,
# a missing posture key falls back to standard (a pre-Job-8 install never
# silently un-gates), and the guard message routes governor intent to the
# ceremony (A4).
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

set_posture() {
  python3 - "$1" <<'PY'
import json, sys
p = "rails/config.json"; c = json.load(open(p)); c["posture"] = sys.argv[1]
json.dump(c, open(p, "w"), indent=2)
PY
}

# 1. quiet: nothing outside the floor is blocked (the user works as they
# always did; the kit adds the verdict line and the floor, nothing else)
set_posture quiet
expect_allowed "quiet: ordinary file edit"            "$(agent_edit src/main.py)"
expect_allowed "quiet: ordinary shell write"          "$(agent_bash 'echo hi > scratch.txt')"
expect_allowed "quiet: plain commit (commits as they always did)" "$(agent_bash 'git commit -m wip')"
expect_allowed "quiet: editing their own tests"       "$(agent_bash 'echo note >> tests/test_mod.py')"
expect_allowed "quiet: new branch"                    "$(agent_bash 'git checkout -b feature-x')"
_assert "quiet: session end never gated (no lifecycle required)" 0 "$(agent_stop)"

# 2. standard: the ceremony the user opted into is intact (the relax is
# quiet-only, not a global weakening)
set_posture standard
expect_blocked "standard: commit boundary intact"     "$(agent_bash 'git commit -m wip')"
expect_blocked "standard: test mutation gated"        "$(agent_bash 'echo x >> tests/test_mod.py')"
_assert "standard: stop gated without fresh proof" 2 "$(agent_stop)"

# 3. missing posture key -> standard (an install predating Job 8 keeps its
# full gating; new installs are quiet by template, old ones opt in)
python3 - <<'PY'
import json
p = "rails/config.json"; c = json.load(open(p)); c.pop("posture", None)
json.dump(c, open(p, "w"), indent=2)
PY
expect_blocked "no posture key: commit boundary still intact (conservative fallback)" "$(agent_bash 'git commit -m wip')"
_assert "no posture key: stop still gated" 2 "$(agent_stop)"

# 4. A4: the trust-layer guard message routes a human-intended governor
# change to the human (both guards carry the hint)
FMSG="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"rails/verifier/verify.sh"}}' \
  | CLAUDE_PROJECT_DIR="$SANDBOX" python3 "$SANDBOX/.claude/hooks/guard_files.py" 2>&1 >/dev/null || true)"
_assert "guard_files hint routes to the human" 1 "$(printf '%s' "$FMSG" | grep -c human)"
_assert "guard_files hint names strict"       1 "$(printf '%s' "$FMSG" | grep -c strict)"
BMSG="$(printf '{"tool_name":"Bash","tool_input":{"command":"echo x >> rails/verifier/verify.sh"}}' \
  | CLAUDE_PROJECT_DIR="$SANDBOX" python3 "$SANDBOX/.claude/hooks/guard_bash.py" 2>&1 >/dev/null || true)"
_assert "guard_bash hint routes to the human"  1 "$(printf '%s' "$BMSG" | grep -c human)"
finish
