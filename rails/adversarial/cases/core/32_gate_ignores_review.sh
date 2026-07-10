#!/usr/bin/env bash
# R2 — Gate ignores reviewer approval: failing work + a maximally positive
# reviewer report must still be rejected by the verifier. Proves non-gating
# STRUCTURALLY: grep shows the gate's live path contains NO read of the
# findings artifact. (Class 09 family inverted: the NON-check that was never
# shown to not-fire is the same theater.)
#
# GREEN half (honest neighbor): a passing dispatch with a reviewer report
# passes normally (reviewer findings don't BLOCK a green either).
# RED half: a FAILING dispatch with a glowing reviewer report still fails.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# --- structural: verify.sh NEVER reads reviewer findings -------------------
# The live path of the gate must contain zero references to the findings
# artifact. This is the R2 proof: the gate is structurally incapable of
# consuming reviewer output.
_assert "verify.sh does not read review_findings" 0 \
  "$(grep -ic 'review_findings' rails/verifier/verify.sh)"
_assert "verify.sh does not read reviewer" 0 \
  "$(grep -ic 'reviewer' rails/verifier/verify.sh)"
_assert "gate_stop.py does not read review_findings" 0 \
  "$(grep -ic 'review_findings' .claude/hooks/gate_stop.py)"
_assert "gate_stop.py does not read reviewer" 0 \
  "$(grep -c 'reviewer' .claude/hooks/gate_stop.py)"

# Severity/score is PRESENTATION ONLY for the human read. No component may
# consume it as a signal, no code path may branch on it.
_assert "verify.sh does not read severity" 0 \
  "$(grep -ic 'severity' rails/verifier/verify.sh)"
_assert "gate_stop.py does not read severity" 0 \
  "$(grep -ic 'severity' .claude/hooks/gate_stop.py)"
_assert "verify.sh does not read finding_score" 0 \
  "$(grep -ic 'finding.score\|review.score\|review_score' rails/verifier/verify.sh)"

# --- RED: failing work + positive reviewer report -> still REJECTED ---------
# Break the implementation so the suite fails
sed 's/a + b/a - b/' src/mod.py > src/mod.py.tmp && mv src/mod.py.tmp src/mod.py
# Clear bytecode cache so Python sees the modified source
find . -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

# Plant a maximally positive reviewer report in the evidence directory
mkdir -p rails/evidence/D-test
cat > rails/evidence/D-test/review_findings.md <<'FINDINGS'
---
model: claude-sonnet-4-6
tree_hash: abc123
duration_seconds: 45
findings_count:
  critical: 0
  high: 0
  medium: 0
  low: 0
  info: 0
---
# Reviewer Findings

## Summary
This change is excellent. No issues found. All code is well-structured,
thoroughly tested, and follows best practices. Strongly recommend approval.

## Findings
None. The implementation is flawless.
FINDINGS

# The verifier must still reject — the positive review changes nothing
_assert "failing work + positive review -> verify REJECTS" 1 "$(run_verify)"
_assert "full_suite check fails (broken impl)" "false" "$(check_state full_suite)"

# --- GREEN: passing work + reviewer report -> verify still PASSES -----------
# Restore the implementation
sed 's/a - b/a + b/' src/mod.py > src/mod.py.tmp && mv src/mod.py.tmp src/mod.py
find . -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

_assert "passing work + positive review -> verify PASSES" 0 "$(run_verify)"
_assert "full_suite check passes" "true" "$(check_state full_suite)"

# --- The reviewer report is still present: it wasn't consumed, just ignored -
_assert "reviewer findings still present (not consumed)" 1 \
  "$([ -f rails/evidence/D-test/review_findings.md ] && echo 1 || echo 0)"

finish
