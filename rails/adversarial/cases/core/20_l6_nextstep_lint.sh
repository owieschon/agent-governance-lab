#!/usr/bin/env bash
# L6 next-step lint (Job 8 Part D2): every block/flag/error message in the
# kit carries its own next step. Both directions: the lint passes the kit as
# shipped (no false fire on clean messages), and it FIRES on a planted
# dead-end message (a condition stated with no action).
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

_assert "lint passes the kit as shipped" 0 \
  "$(python3 rails/verifier/nextstep_lint.py . >/dev/null 2>&1; echo $?)"

# plant a dead end in a hook: states a condition, hands the reader nothing
cat >> .claude/hooks/guard_files.py <<'EOF'

def _planted_dead_end():
    deny("BOUNDARY: you may not do that")
EOF

OUT="$(python3 rails/verifier/nextstep_lint.py . 2>&1 >/dev/null; true)"
_assert "lint fires on a planted no-next-step message" 1 \
  "$(python3 rails/verifier/nextstep_lint.py . >/dev/null 2>&1; echo $?)"
_assert "lint names the offending file" 1 \
  "$(printf '%s' "$OUT" | grep -c 'guard_files.py')"

git checkout -q .claude/hooks/guard_files.py
_assert "lint clean again after restore" 0 \
  "$(python3 rails/verifier/nextstep_lint.py . >/dev/null 2>&1; echo $?)"
finish
