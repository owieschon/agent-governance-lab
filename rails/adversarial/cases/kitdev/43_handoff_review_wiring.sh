#!/usr/bin/env bash
# Case 43 — handoff-review wiring (D58): the shipped reviewer trigger is ON
# the live handoff path, config-gated and default-quiet, and can never block.
#
# RED (the unwired state this case was demonstrated against): review.sh
# shipped at 4b76506 but NOTHING invoked it -- no helper seam existed, and
# the /handoff command never referenced the reviewer. Every wiring assertion
# below fails against that state.
#
# Two halves:
#   DEFAULT-QUIET half: with NO reviewer_model key in rails/config.json
#     (the fixture default), launch and render emit zero output, exit 0,
#     and leave zero review artifacts -- review.sh is never invoked.
#   NON-BLOCKING half (honest unavailable): with reviewer_model configured
#     but the model command failing, the handoff SCRIPT PATH proceeds and
#     the handoff doc carries exactly one "review: unavailable" line.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

gpresent() { grep -qi "$1" "$2" 2>/dev/null && echo 1 || echo 0; }

# The reviewer trigger files ride along from the host so the case drives the
# same bytes that ship (fixture copies the rest of the governor).
cp "$KIT_HOST/rails/verifier/review.sh" rails/verifier/review.sh 2>/dev/null || true
cp "$KIT_HOST/rails/verifier/handoff_review.sh" rails/verifier/handoff_review.sh 2>/dev/null || true
chmod +x rails/verifier/*.sh 2>/dev/null || true
HR="rails/verifier/handoff_review.sh"

# --- the seam exists and is WIRED (red in the unwired state) ----------------
_assert "handoff_review.sh exists (the script seam ships)" 1 \
  "$([ -f "$HR" ] && echo 1 || echo 0)"
_assert "/handoff command invokes the helper (live path)" 1 \
  "$(gpresent 'handoff_review.sh' "$KIT_HOST/.claude/commands/handoff.md")"
_assert "helper invokes the shipped review.sh (real mechanism)" 1 \
  "$(gpresent 'review\.sh' "$HR")"
_assert "install ships the helper" 1 \
  "$(gpresent 'handoff_review.sh' "$KIT_HOST/install.sh")"
_assert "eject removes the helper (install-eject symmetry)" 1 \
  "$(gpresent 'handoff_review.sh' "$KIT_HOST/rails/verifier/eject.sh")"

# --- DEFAULT-QUIET: no reviewer_model key -> zero output, zero artifacts ----
_assert "fixture config has no reviewer_model (premise)" 0 \
  "$(grep -c 'reviewer_model' rails/config.json)"

OUT="$(bash "$HR" launch D-test 2>&1)"; RC=$?
_assert "quiet launch: exit 0" 0 "$RC"
_assert "quiet launch: zero output" "" "$OUT"
OUT="$(bash "$HR" render D-test 2>&1)"; RC=$?
_assert "quiet render: exit 0" 0 "$RC"
_assert "quiet render: zero output" "" "$OUT"
_assert "quiet: review.sh never ran (no artifacts)" 0 \
  "$(ls rails/evidence/D-test 2>/dev/null | grep -c 'review')"

# --- NON-BLOCKING: reviewer configured, model command failing ---------------
python3 - <<'PY'
import json
c = json.load(open('rails/config.json'))
c['reviewer_model'] = 'stub-model'
json.dump(c, open('rails/config.json', 'w'), indent=2)
PY
mkdir -p stubbin
printf '#!/bin/bash\nexit 1\n' > stubbin/claude
chmod +x stubbin/claude

OUT="$(PATH="$PWD/stubbin:$PATH" bash "$HR" launch D-test --timeout 5 2>&1)"; RC=$?
_assert "failing-model launch: exit 0 (never propagates)" 0 "$RC"
_assert "failing-model launch: silent (concurrent, no chatter)" "" "$OUT"

# the handoff script path proceeds: the doc is written WITH the render block
{ echo "# Handoff: D-test"
  echo
  PATH="$PWD/stubbin:$PATH" bash "$HR" render D-test --timeout 5
} > rails/handoff/D-test.md
RC=$?
_assert "render with failing model: exit 0 (handoff proceeds)" 0 "$RC"
_assert "handoff doc has exactly one 'review: unavailable' line" 1 \
  "$(grep -c 'review: unavailable' rails/handoff/D-test.md)"
_assert "review block within doc budget (one line, not a dump)" 1 \
  "$(grep -c '^review:' rails/handoff/D-test.md)"
_assert "doc stayed small (3 lines total)" 3 \
  "$(wc -l < rails/handoff/D-test.md | tr -d ' ')"

finish
