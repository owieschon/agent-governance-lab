#!/usr/bin/env bash
#
# run_observer.sh <name> [--dry-run] -- the shared observer runner (Job 4A).
#
# An observer is an outer loop pointed at the world instead of the repo. Its
# constitution (D59, guard-enforced for agents and honored STRUCTURALLY
# here): the ONLY write privilege is creating NEW files in
# rails/dispatches/inbox/ plus its own state under rails/observers/state/.
# This runner never overwrites an existing inbox item (the same create-only
# law guard_files enforces on agents), never edits code, never touches the
# governor. Observers PROPOSE; the human approves; the inner loop implements.
#
# Definition: rails/observers/<name>.json (JSON, the kit's house format --
# D59 records the KEY=VALUE vs JSON choice). Keys:
#   name, source, trigger     strings rendered into every filed inbox item
#   query_cmd                 bash command emitting CANDIDATE JSONL on stdout:
#                             {"id","title","evidence","problem","priority"}
#                             one object per line (see extract.py transforms)
#   fixture                   candidate JSONL file used with --dry-run (no
#                             network, no credentials)
#   dedup_field               which candidate field is its identity (def "id")
#   rate_limit                max items filed per run (default 3); the rest
#                             is carried in state overflow for the next run
#   env_var                   credential ENV VAR NAME only -- the value lives
#                             in the runner's environment and is NEVER
#                             written to any file by any code path
#   requires_cmd              a command that must exist on PATH (e.g. gh)
#
# Fail-safe-to-human: a missing credential, missing required command, or a
# failing query is a silent-and-logged skip (state log, exit 0) -- a cron
# run never breaks because a key is absent, and a broken observer never
# invents work. Suitable for launchd/cron; schedule lines are PROPOSED in
# docs/OPERATING.md ("Outer loops") and never installed by the kit.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="${1:?usage: run_observer.sh <name> [--dry-run]}"
DRY=0
[ "${2:-}" = "--dry-run" ] && DRY=1
DEF="$ROOT/rails/observers/$NAME.json"
if [ ! -f "$DEF" ]; then
  echo "run_observer: no definition at rails/observers/$NAME.json -- add one (see docs/OPERATING.md, 'Outer loops')" >&2
  exit 1
fi
STATE_DIR="$ROOT/rails/observers/state"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/$NAME.log"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

defget() {  # defget <key> -> string value ("" if absent)
  python3 -c 'import json, sys
v = json.load(open(sys.argv[1])).get(sys.argv[2], "")
print(v if isinstance(v, str) else json.dumps(v))' "$DEF" "$1"
}

REQ="$(defget requires_cmd)"
if [ -n "$REQ" ] && ! command -v "$REQ" >/dev/null 2>&1; then
  echo "$TS skip: required command '$REQ' not on PATH -- install it, or leave this observer dormant" >> "$LOG"
  exit 0
fi

ENV_VAR="$(defget env_var)"
if [ "$DRY" -eq 0 ] && [ -n "$ENV_VAR" ] && [ -z "${!ENV_VAR:-}" ]; then
  echo "$TS skip: credential env var $ENV_VAR not set -- set it in the runner's environment (env var only, never a file)" >> "$LOG"
  exit 0
fi

CAND="$(mktemp)"
if [ "$DRY" -eq 1 ]; then
  FIX="$(defget fixture)"
  if [ -n "$FIX" ] && [ -f "$ROOT/$FIX" ]; then
    cp "$ROOT/$FIX" "$CAND"
  else
    : > "$CAND"
    echo "$TS dry-run: no fixture file at '$FIX' -- zero candidates; set 'fixture' in the definition to a candidate JSONL file" >> "$LOG"
  fi
else
  if ! (cd "$ROOT" && bash -c "$(defget query_cmd)") > "$CAND" 2>> "$LOG"; then
    echo "$TS skip: query command failed (stderr above) -- fix the query or its credentials, then re-run" >> "$LOG"
    rm -f "$CAND"
    exit 0
  fi
fi

# dedup + rate limit + templating, one standalone python block (bash 3.2 safe)
FILED_F="$(mktemp)"
python3 "$ROOT/rails/observers/run_observer.py" "$ROOT" "$NAME" "$DEF" "$CAND" "$TS" "$FILED_F"
rc=$?
FILED="$(cat "$FILED_F" 2>/dev/null || echo 0)"
rm -f "$CAND" "$FILED_F"
[ "$rc" -eq 0 ] || exit "$rc"

# push surfacing (Job 4C): ONE batched message per run, only when something
# was filed. notify.sh is default-OFF and exits 0 when unconfigured or
# token-less, so this is a no-op on installs that never set it up.
if [ "${FILED:-0}" -gt 0 ] && [ -f "$ROOT/rails/notify/notify.sh" ]; then
  bash "$ROOT/rails/notify/notify.sh" observer_filed \
    "rails/dispatches/inbox/ ($FILED new from $NAME)" || true
fi
exit 0
