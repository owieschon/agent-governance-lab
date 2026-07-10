#!/usr/bin/env bash
#
# flaky_triage.sh -- re-run the suite N times, NAME the unstable tests, and emit
# the manifest entry to quarantine each (Job 9b Part 4).
#
# FIND, DON'T FIX: it proposes; a HUMAN declares (moves the test into the lane
# dir and adds the entry to rails/verifier/flaky_lane.json). It NEVER
# auto-quarantines and NEVER retries-until-green -- retrying a flaky test until
# it passes hides a real failure behind a green, the inflation failure the kit
# exists to prevent. L10: honest about what a flaky suite can and cannot prove.
#
# Read-only on your work tree. Lives in the trust layer; not agent-editable.
#
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

exec python3 "$ROOT/rails/verifier/flaky_triage.py" "$ROOT"
