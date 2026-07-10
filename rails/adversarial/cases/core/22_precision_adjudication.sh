#!/usr/bin/env bash
# Precision adjudication (Job 8 Part B): the rolling-window signals fire on
# their shapes and stay quiet on a clean ledger. Proven: (1) quiet when
# nothing is recorded; (2) "under review: precision" on majority-false_block;
# (3) manifest_fault is excluded from a check's precision; (4) a check that
# fired but was never adjudicated surfaces as "unproven in practice", not
# perfect; (5) the true_catch catch-account renders dry; (6) the rubber-stamp
# (approval-fatigue) signal fires on near-zero review minutes at ~100%
# approval; (7) the L1 default-fitness signal fires via the SAME machinery on
# posture observations recorded by the stop gate, idempotent per session.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

ADJ="python3 rails/verifier/adjudicate.py"
set_posture() {
  python3 - "$1" <<'PY'
import json, sys
p = "rails/config.json"; c = json.load(open(p)); c["posture"] = sys.argv[1]
json.dump(c, open(p, "w"), indent=2)
PY
}

# 1. clean ledger -> no signals (no false fire)
_assert "clean ledger -> no signals" "" "$($ADJ signals . 2>/dev/null)"

# 2. majority false_block -> under review
$ADJ record . live_path D-test false_block seed1 >/dev/null
$ADJ record . live_path D-test false_block seed2 >/dev/null
$ADJ record . live_path D-test false_block seed3 >/dev/null
SIG="$($ADJ signals .)"
_assert "majority false_block flags 'under review: precision'" 1 \
  "$(printf '%s' "$SIG" | grep -c 'under review: precision -- live_path')"

# 3. manifest_fault is NOT counted against the check
$ADJ record . full_suite D-test manifest_fault m1 >/dev/null
$ADJ record . full_suite D-test manifest_fault m2 >/dev/null
$ADJ record . full_suite D-test manifest_fault m3 >/dev/null
_assert "manifest_fault never flags the check" 0 \
  "$($ADJ signals . | grep -c 'precision -- full_suite')"

# 4. zero-fire is not zero-precision: fired-but-unadjudicated = unproven
printf '{"source":"verify","check":"demonstrated_red","dispatch":"D-test","iteration":1,"timestamp":"t0"}\n' \
  >> rails/evidence/stats.jsonl
_assert "fired-but-unadjudicated surfaces as unproven in practice" 1 \
  "$($ADJ signals . | grep -c 'unproven in practice -- demonstrated_red')"

# 5. the catch account: dry, factual, no celebration
OUT="$($ADJ record . oracle_integrity D-test true_catch test suite redefined mid-dispatch, 374 to 12 tests)"
_assert "true_catch renders the catch account" 1 "$(printf '%s' "$OUT" | grep -c '^CAUGHT: oracle_integrity')"
_assert "catch account carries the concrete cost" 1 "$(printf '%s' "$OUT" | grep -c '374 to 12')"
_assert "catch account has no exclamation (register is dry)" 0 "$(printf '%s' "$OUT" | grep -c '!')"

# 6. approval fatigue: near-zero review minutes at ~100% approval
for i in 1 2 3 4 5 6; do
  $ADJ approval . "D-a$i" yes 0.5 >/dev/null
done
_assert "rubber-stamp shape flags the attention signal" 1 \
  "$($ADJ signals . | grep -c 'rubber-stamp shape')"

# 7. L1 default fitness through the live wiring: the stop gate records one
# posture observation per session; majority-overridden flags the default.
set_posture standard
for sid in s1 s2 s3; do
  printf '{"hook_event_name":"Stop","stop_hook_active":false,"session_id":"%s"}' "$sid" \
    | CLAUDE_PROJECT_DIR="$SANDBOX" python3 "$SANDBOX/.claude/hooks/gate_stop.py" >/dev/null 2>&1
done
_assert "stop gate recorded one observation per session" 3 \
  "$(grep -c '"kind": "observation"' rails/incidents/adjudications.jsonl)"
printf '{"hook_event_name":"Stop","stop_hook_active":false,"session_id":"s1"}' \
  | CLAUDE_PROJECT_DIR="$SANDBOX" python3 "$SANDBOX/.claude/hooks/gate_stop.py" >/dev/null 2>&1
_assert "repeat session does not double-record (idempotent)" 3 \
  "$(grep -c '"kind": "observation"' rails/incidents/adjudications.jsonl)"
_assert "majority override flags 'default under review'" 1 \
  "$($ADJ signals . | grep -c 'default under review: posture')"
finish
