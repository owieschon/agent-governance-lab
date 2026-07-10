#!/usr/bin/env bash
# R4 — Minimal-grounding honest neighbor: a clean diff against a spec that
# omits a plausible-but-unstated constraint must NOT produce a CONTRACT FAIL
# for the unstated constraint. A JUDGMENT-register observation on the same
# point IS acceptable output. Tests that the two-register structure (v2.2),
# the MINIMAL-GROUNDING RULE, and severity-as-display-only are all present
# in the reviewer agent definition, and that render_review_summary.py treats
# severity as display-only.
#
# This is a STRUCTURAL test (like R2): it asserts the rules ARE in the prompt
# and that severity is not consumed as a signal anywhere in the gate.
# The execution-level test (does a live reviewer obey?) is the detection
# profile (grading discipline, demand-driven N), not the eval case.
#
# GREEN half: the grounding rule and two-register structure are present.
# RED half: without the rules, the agent definition would lack them.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# Helper: count grep matches without the double-print bug (grep -c outputs "0"
# AND exits 1, so '|| echo 0' would print 0 twice). Returns 0 for missing files.
gcount() { local n; n="$(grep -ic "$1" "$2" 2>/dev/null)" && echo "$n" || echo "${n:-0}"; }

# Presence check: returns 1 if pattern found (at least once), 0 otherwise.
# Use for terms that legitimately appear multiple times in the agent def.
gpresent() { grep -qi "$1" "$2" 2>/dev/null && echo 1 || echo 0; }

# --- structural: the reviewer agent definition exists ----------------------
AGENT_DEF=".claude/agents/reviewer.md"
_assert "reviewer agent definition exists" 1 \
  "$([ -f "$AGENT_DEF" ] && echo 1 || echo 0)"

# --- structural: MINIMAL-GROUNDING RULE present ----------------------------
_assert "agent def contains MINIMAL-GROUNDING RULE" 1 \
  "$(gpresent 'MINIMAL-GROUNDING RULE' "$AGENT_DEF")"

_assert "agent def contains 'NEVER invents'" 1 \
  "$(gpresent 'never invents' "$AGENT_DEF")"

_assert "agent def traces rubric to dispatch spec/diff/contract" 1 \
  "$(gpresent 'dispatch spec' "$AGENT_DEF")"

# --- structural: severity is display-only ----------------------------------
_assert "agent def states severity is PRESENTATION ONLY" 1 \
  "$(gpresent 'PRESENTATION ONLY' "$AGENT_DEF")"

_assert "agent def states per-item PASS/FAIL results" 1 \
  "$(gpresent 'per-item PASS' "$AGENT_DEF")"

# --- structural: two-register findings structure (v2.2) --------------------
_assert "agent def contains CONTRACT register" 1 \
  "$(gpresent 'CONTRACT register' "$AGENT_DEF")"

_assert "agent def contains JUDGMENT register" 1 \
  "$(gpresent 'JUDGMENT register' "$AGENT_DEF")"

# The honest-neighbor assertion: unstated constraints must NOT produce a
# CONTRACT FAIL — only a JUDGMENT observation is acceptable.
_assert "agent def prohibits CONTRACT FAIL for unstated constraints" 1 \
  "$(gpresent 'never as a CONTRACT FAIL' "$AGENT_DEF")"

# Both registers carry provenance and falsifiability (detection-profile hooks)
_assert "agent def requires provenance fields" 1 \
  "$(gpresent 'provenance' "$AGENT_DEF")"

_assert "agent def requires falsifiability fields" 1 \
  "$(gpresent 'falsifiability' "$AGENT_DEF")"

# --- structural: renderer is display-only, never gates on severity ---------
_assert "render_review_summary exists" 1 \
  "$([ -f rails/verifier/render_review_summary.py ] && echo 1 || echo 0)"

# The renderer sorts by severity for display but never gates on it
_assert "renderer does not gate on severity" 0 \
  "$(gcount 'min_severity\|severity_threshold' rails/verifier/render_review_summary.py)"

finish
