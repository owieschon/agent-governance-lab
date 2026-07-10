#!/usr/bin/env bash
#
# handoff_review.sh <launch|render> <dispatch-id> [--timeout <seconds>]
#
# The handoff-adjacent seam for the reviewer (D58). /handoff calls `launch`
# right after its preconditions (the reviewer works concurrently while the
# report is written) and embeds the output of `render` in the handoff doc.
# `rails review <id>` is an alias for the render path; the primary path
# needs no verb.
#
# Config-gated and DEFAULT-QUIET: when rails/config.json has no
# `reviewer_model` key, both subcommands exit 0 with zero output and zero
# artifacts -- the handoff is byte-for-byte what it was before the reviewer
# existed. A second model's spend is the operator's budget call, never the
# kit's default.
#
# NON-BLOCKING by construction (a reviewer that can stall the pipeline is an
# unproven gate by another name):
#   launch -- backgrounds review.sh in its OWN PROCESS GROUP (set -m) and
#            returns immediately. Portable bash 3.2: no `timeout` command.
#   render -- waits with a hard deadline, then group-kills the reviewer's
#            whole process tree (review.sh's internal kill reaps its child
#            subshell; a hung model process can be a grandchild that
#            survives orphaned -- the group kill is what reaps it
#            cross-process, case 44), and prints either the capped findings
#            block (render_review_summary.py) or one honest
#            "review: unavailable" line. NEVER exits nonzero.
#
# The output is presentation for the human read only: the gate never
# consumes it (case 32), and nothing here reads the operator's judgment
# stream back into the reviewer (case 46 -- corpus fence).
#
# Lives in the trust layer. Not agent-editable.
set -u

MODE="${1:?usage: handoff_review.sh <launch|render> <dispatch-id> [--timeout <seconds>]}"
DISPATCH="${2:?usage: handoff_review.sh <launch|render> <dispatch-id> [--timeout <seconds>]}"
shift 2

TIMEOUT=120  # passed through to review.sh; render's deadline adds grace
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG="$ROOT/rails/config.json"
EVID="$ROOT/rails/evidence/$DISPATCH"
PIDFILE="$EVID/review.pid"
STATUSF="$EVID/review_status.txt"
FINDINGS="$EVID/review_findings.md"

# --- config gate (D58): no reviewer_model key -> quiet no-op ---------------
HAS_KEY=0
if [ -f "$CFG" ]; then
  HAS_KEY="$(python3 -c "import json,sys;print(1 if 'reviewer_model' in json.load(open(sys.argv[1])) else 0)" "$CFG" 2>/dev/null || echo 0)"
fi
[ "$HAS_KEY" = "1" ] || exit 0

do_launch() {
  mkdir -p "$EVID"
  # set -m gives the background job its own process group (pgid == its pid),
  # which the render phase can kill as a unit from a separate process.
  set -m
  bash "$ROOT/rails/verifier/review.sh" "$DISPATCH" --timeout "$TIMEOUT" \
    > "$STATUSF" 2>&1 &
  echo $! > "$PIDFILE"
  set +m
}

case "$MODE" in
  launch)
    do_launch
    exit 0
    ;;
  render)
    # re-render is a READ: findings already on disk (and no run in flight)
    # render as-is -- never respawn the reviewer (paid tokens) and never
    # overwrite the artifact. Alias path (`rails review <id>`) with neither
    # findings nor a prior launch runs the whole flow itself.
    if [ ! -f "$PIDFILE" ] && [ ! -f "$FINDINGS" ]; then
      do_launch
    fi
    PID="$(cat "$PIDFILE" 2>/dev/null || echo "")"
    # wait-with-deadline: review.sh enforces its own timeout; the grace
    # margin covers launch overhead. The deadline protects the handoff,
    # it is not a gate.
    DEADLINE=$((TIMEOUT + 15))
    ELAPSED=0
    while [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; do
      if [ "$ELAPSED" -ge "$DEADLINE" ]; then break; fi
      sleep 1
      ELAPSED=$((ELAPSED + 1))
    done
    # cross-process cleanup: kill the reviewer's process group so a hung
    # reviewer never outlives the handoff (no-op when it exited cleanly)
    if [ -n "$PID" ]; then
      kill -TERM -- "-$PID" 2>/dev/null
      kill -KILL -- "-$PID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
    if [ -f "$FINDINGS" ]; then
      BLOCK="$(python3 "$ROOT/rails/verifier/render_review_summary.py" "$FINDINGS" 2>/dev/null)" || BLOCK=""
      if [ -n "$BLOCK" ]; then
        printf '%s\n' "$BLOCK"
      else
        echo "review: unavailable"
      fi
    else
      # surface review.sh's own honest one-liner when it wrote one
      LINE="$(head -1 "$STATUSF" 2>/dev/null)" || LINE=""
      case "$LINE" in
        review:*) printf '%s\n' "$LINE" ;;
        *)        echo "review: unavailable" ;;
      esac
    fi
    exit 0
    ;;
  *)
    # unknown subcommand: harmless and quiet -- this script may never block
    # a handoff
    exit 0
    ;;
esac
