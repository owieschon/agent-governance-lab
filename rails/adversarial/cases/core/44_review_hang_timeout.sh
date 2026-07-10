#!/usr/bin/env bash
# Case 44 — cross-process reviewer timeout (D58): a reviewer that HANGS past
# the timeout is KILLED and the handoff proceeds. This is the test DEPARTURES
# named as future work in the launch slice ("a full cross-process timeout
# test ... is a future integration test"); it is an eval case now.
#
# The sharp edge this pins: review.sh's own timeout kills the SUBSHELL it
# backgrounded, but a hung model process can be a grandchild that survives
# that kill (orphaned, reparented to init). handoff_review.sh launches
# review.sh in its own process group (set -m) and group-kills at render
# time, so the whole reviewer tree dies cross-process.
#
# GREEN half is case 45 (a fast reviewer is not killed mid-write -- its
# findings render); this case is the RED: hang -> killed -> one honest line.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

cp "$KIT_HOST/rails/verifier/review.sh" rails/verifier/review.sh 2>/dev/null || true
cp "$KIT_HOST/rails/verifier/handoff_review.sh" rails/verifier/handoff_review.sh 2>/dev/null || true
chmod +x rails/verifier/*.sh 2>/dev/null || true
HR="rails/verifier/handoff_review.sh"
_assert "handoff_review.sh exists" 1 "$([ -f "$HR" ] && echo 1 || echo 0)"

# configure a reviewer + a model command that hangs forever
python3 - <<'PY'
import json
c = json.load(open('rails/config.json'))
c['reviewer_model'] = 'stub-model'
json.dump(c, open('rails/config.json', 'w'), indent=2)
PY
mkdir -p stubbin
cat > stubbin/claude <<'EOF'
#!/bin/bash
sleep 31536000
EOF
chmod +x stubbin/claude

START="$(date +%s)"
PATH="$PWD/stubbin:$PATH" bash "$HR" launch D-test --timeout 3 >/dev/null 2>&1
LRC=$?
OUT="$(PATH="$PWD/stubbin:$PATH" bash "$HR" render D-test --timeout 3 2>&1)"
RRC=$?
END="$(date +%s)"
WALL=$((END - START))

_assert "launch exit 0" 0 "$LRC"
_assert "render exit 0 (hang never propagates)" 0 "$RRC"
_assert "render returned within the deadline (< 60s wall)" 1 \
  "$([ "$WALL" -lt 60 ] && echo 1 || echo 0)"
_assert "handoff proceeds with the one honest line" 1 \
  "$(echo "$OUT" | grep -c 'review: unavailable')"
_assert "no findings were fabricated" 0 \
  "$([ -f rails/evidence/D-test/review_findings.md ] && echo 1 || echo 0)"

# the kill must be REAL: no orphaned reviewer process survives the render
sleep 1
SURVIVORS="$(pgrep -f 'sleep 31536000' 2>/dev/null | wc -l | tr -d ' ')"
_assert "hung reviewer tree killed (zero orphan survivors)" 0 "$SURVIVORS"
# hygiene: never leave a hung stub behind even if the assertion failed
pkill -f 'sleep 31536000' 2>/dev/null || true

finish
