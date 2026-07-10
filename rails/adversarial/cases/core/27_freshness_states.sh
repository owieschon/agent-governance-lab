#!/usr/bin/env bash
# Cold-start freshness (Job 9b Part 5, L10): an accumulation artifact below its
# meaning threshold shows a forward-pointing "not enough history yet" line, not
# a misleading number and not a sad/empty n/a. Both directions: the helper
# gates on min-N, and the scoreboard renders the forward line at zero history.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

F="rails/verifier/freshness.py"

# the helper, both directions (default min-N = 3)
_assert "0 observations -> not meaningful" 1 "$(python3 $F meaningful 0; echo $?)"
_assert "2 observations -> not meaningful" 1 "$(python3 $F meaningful 2; echo $?)"
_assert "3 observations -> meaningful"     0 "$(python3 $F meaningful 3; echo $?)"
_assert "thin sample -> forward-pointing state, not empty" 1 \
  "$([ -n "$(python3 $F state 1 'a rate')" ] && echo 1 || echo 0)"
_assert "forward state names what is missing" 1 \
  "$(python3 $F state 1 'a rate' | grep -c 'not enough history yet')"
_assert "meaningful sample -> NO cold-start line (real metric shows)" 0 \
  "$(python3 $F state 5 'a rate' | grep -c .)"

# the scoreboard surface at zero history: forward-pointing, never a sad n/a
rm -rf rails/evidence/* rails/dispatches/archive/* 2>/dev/null || true
OUT="$(bash rails/verifier/scoreboard.sh 2>/dev/null)"
_assert "scoreboard rate at 0 history -> forward-pointing line" 1 \
  "$(printf '%s' "$OUT" | grep -c 'not enough history yet')"
_assert "scoreboard does NOT show a misleading 0%/n-a rate" 0 \
  "$(printf '%s' "$OUT" | grep -c 'first-pass verify rate: *n/a\|first-pass verify rate: *0/0')"
_assert "raw counts are still shown honestly (0 completed)" 1 \
  "$(printf '%s' "$OUT" | grep -c 'dispatches completed (PASS verdict):  0')"
finish
