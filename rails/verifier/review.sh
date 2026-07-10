#!/usr/bin/env bash
#
# review.sh <dispatch-id> [--timeout <seconds>]
#
# Launch the reviewer subagent concurrently with verify. Non-blocking:
# on error/timeout/model-down, the handoff proceeds with one honest line
# ("review: unavailable"). A reviewer that can stall the pipeline is an
# unproven gate by another name.
#
# This is the trigger wiring for the reviewer role. It:
#   1. Reads the reviewer config from rails/config.json
#   2. Launches the reviewer subagent (via claude --agent) in the background
#   3. Waits up to the timeout
#   4. On success: the findings artifact is in rails/evidence/<id>/review_findings.md
#   5. On timeout/error: prints "review: unavailable" and exits 0
#
# Lives in the trust layer. Not agent-editable.
set -u

DISPATCH="${1:?usage: review.sh <dispatch-id> [--timeout <seconds>]}"
shift

TIMEOUT=120  # default 2 minutes
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG="$ROOT/rails/config.json"
EVID="$ROOT/rails/evidence/$DISPATCH"
FINDINGS="$EVID/review_findings.md"

mkdir -p "$EVID"

# Read reviewer config
REVIEWER_MODEL=""
REVIEWER_ENABLED="true"
if [ -f "$CFG" ]; then
  REVIEWER_MODEL="$(python3 -c "import json;print(json.load(open('$CFG')).get('reviewer_model',''))" 2>/dev/null || echo "")"
  REVIEWER_ENABLED="$(python3 -c "import json;print(str(json.load(open('$CFG')).get('reviewer_enabled', True)).lower())" 2>/dev/null || echo "true")"
fi

if [ "$REVIEWER_ENABLED" = "false" ]; then
  echo "review: disabled by config"
  exit 0
fi

# Check if claude CLI is available
if ! command -v claude >/dev/null 2>&1; then
  echo "review: unavailable (claude CLI not found)"
  exit 0
fi

# Check if the reviewer agent definition exists
AGENT_DEF="$ROOT/.claude/agents/reviewer.md"
if [ ! -f "$AGENT_DEF" ]; then
  echo "review: unavailable (no agent definition)"
  exit 0
fi

# Build the reviewer prompt
TREE_HASH="$(python3 "$ROOT/rails/verifier/treehash.py" 2>/dev/null || echo "unknown")"
PROMPT="Review dispatch $DISPATCH. Tree hash: $TREE_HASH. Write findings to $FINDINGS."

# Launch the reviewer subagent in the background with timeout
# The --agent flag sets CLAUDE_AGENT_NAME which the guards read for posture
MODEL_ARG=""
[ -n "$REVIEWER_MODEL" ] && MODEL_ARG="--model $REVIEWER_MODEL"

# Background launch with timeout (portable: background + poll + kill).
# Dedicated key seam: RAILS_REVIEWER_API_KEY (env only, never a file) is
# handed to the reviewer CHILD as ANTHROPIC_API_KEY, scoping its spend to
# the operator's reviewer key without re-billing the wider session.
(
  cd "$ROOT"
  if [ -n "${RAILS_REVIEWER_API_KEY:-}" ]; then
    ANTHROPIC_API_KEY="$RAILS_REVIEWER_API_KEY" \
      claude --agent reviewer $MODEL_ARG --print "$PROMPT" > "$EVID/review.log" 2>&1
  else
    claude --agent reviewer $MODEL_ARG --print "$PROMPT" > "$EVID/review.log" 2>&1
  fi
) &
PID=$!

# Wait with timeout (portable for bash 3.2: no `timeout` command)
ELAPSED=0
while kill -0 "$PID" 2>/dev/null; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
    echo "review: unavailable (timeout after ${TIMEOUT}s)"
    exit 0
  fi
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

wait "$PID" 2>/dev/null
RC=$?

if [ "$RC" -ne 0 ]; then
  echo "review: unavailable (exit $RC)"
  exit 0
fi

if [ -f "$FINDINGS" ]; then
  echo "review: complete (findings in $FINDINGS)"
else
  echo "review: unavailable (no findings produced)"
fi

exit 0
