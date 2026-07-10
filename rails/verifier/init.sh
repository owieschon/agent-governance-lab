#!/usr/bin/env bash
#
# init.sh [--detect-only] -- autodetect + VALIDATE the per-repo adapter (Job 9a
# Part 1). Subtracts the eleven-key config decision (L1): it detects your test
# setup, runs it to confirm the detection is real, and writes the adapter into
# rails/config.json -- leaving every value a plain key you can still edit.
#
# Two invariants:
#   SEEDS, NEVER STAMPS. init writes config.json and nothing else. It never
#   touches rails/adversarial/registry.json -- the first run_eval.sh remains the
#   sole proof of the governor. A freshly init'd repo is configured but UNPROVEN,
#   and verify.sh refuses to certify until you prove it.
#   VALIDATE OR ASK. init never seeds a config it could not parse a real run
#   with. It runs the detected runner's collect and a real test run, and only
#   seeds if the run exits 0 AND count_regex parses >=1 test from it (a
#   zero-test run or a failing run -- e.g. unittest's synthetic _FailedTest on
#   a broken import -- proves nothing). If detection or validation fails, it
#   tells you exactly which keys to set by hand and writes nothing.
#
# --detect-only prints what it WOULD use and exits (no run, no write) -- a dry
# run, and the testable seam. Lives in the trust layer; not agent-editable.
#
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG="$ROOT/rails/config.json"
cd "$ROOT"

DETECT_ONLY=0
[ "${1:-}" = "--detect-only" ] && DETECT_ONLY=1

say() { printf '%s\n' "$*"; }

# capped_run <seconds> <shell-cmd> -> writes combined output to $CAP_OUT,
# returns the command's status (124 on timeout). Portable: stock macOS bash 3.2
# has no `timeout`/`gtimeout`, so we background + poll + kill.
CAP_OUT=""
capped_run() {
  local secs="$1" cmd="$2" i=0 pid
  CAP_OUT="$(mktemp)"
  bash -c "$cmd" >"$CAP_OUT" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1; i=$((i + 1))
    if [ "$i" -ge "$secs" ]; then
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124
    fi
  done
  wait "$pid" 2>/dev/null
}

# detect -> echoes "family|test_cmd|count_regex|collect_cmd|test_glob|verified"
# verified=yes for fleet-proven families (pytest/unittest/jest/vitest); no for
# detected-but-unverified families (go/cargo) -- still validation-gated.
detect() {
  if [ -f package.json ]; then
    local fam
    fam="$(python3 - <<'PY'
import json
try:
    p = json.load(open("package.json"))
except Exception:
    p = {}
blob = (json.dumps(p.get("devDependencies", {})) + json.dumps(p.get("dependencies", {}))
        + json.dumps(p.get("scripts", {})))
print("vitest" if "vitest" in blob else "jest" if "jest" in blob else "node-unknown")
PY
)"
    case "$fam" in
      jest)   say 'jest|npx jest --ci 2>&1|Tests:.*?([0-9]+) passed|npx jest --listTests|tests|yes'; return;;
      vitest) say 'vitest|npx vitest run 2>&1|([0-9]+) passed|npx vitest list 2>&1|tests|yes'; return;;
    esac
  fi
  if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ] || [ -f tox.ini ] \
     || ls conftest.py >/dev/null 2>&1 || ls tests/*.py >/dev/null 2>&1; then
    if python3 -c "import pytest" >/dev/null 2>&1; then
      say 'pytest|pytest -q|([0-9]+) passed|pytest --collect-only -q|tests|yes'; return
    fi
    say 'unittest|python3 -m unittest discover -s tests -v 2>&1|Ran ([0-9]+) tests?||tests|yes'; return
  fi
  [ -f go.mod ]     && { say 'go|go test ./... -v 2>&1|([0-9]+) passed|go test ./... 2>&1|.|no'; return; }
  [ -f Cargo.toml ] && { say 'cargo|cargo test 2>&1|([0-9]+) passed|cargo test -- --list 2>&1|tests|no'; return; }
  say 'none|||||'
}

D="$(detect)"
FAMILY="$(printf '%s' "$D" | cut -d'|' -f1)"
TEST_CMD="$(printf '%s' "$D" | cut -d'|' -f2)"
COUNT_REGEX="$(printf '%s' "$D" | cut -d'|' -f3)"
COLLECT_CMD="$(printf '%s' "$D" | cut -d'|' -f4)"
TEST_GLOB="$(printf '%s' "$D" | cut -d'|' -f5)"
VERIFIED="$(printf '%s' "$D" | cut -d'|' -f6)"

MB="$(basename "$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)" 2>/dev/null)"
[ -z "$MB" ] && MB="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
REMOTE="$(git remote 2>/dev/null | head -1)"; [ -z "$REMOTE" ] && REMOTE="origin"

ask_and_exit() {
  say ""
  say "rails init: could not $1."
  say "Set these keys in rails/config.json by hand, then re-run 'rails init' to"
  say "validate (or run rails/adversarial/run_eval.sh once you are confident):"
  say "  test_cmd      the command that runs your full suite"
  say "  count_regex   a regex with one capture group for the passed-test count"
  say "  collect_cmd   a command that lists tests without running them (optional)"
  say "  test_glob     the directory holding your tests"
  say "init wrote nothing; your config is untouched."
  exit 1
}

if [ "$FAMILY" = "none" ]; then
  [ "$DETECT_ONLY" -eq 1 ] && { say "family=none (no test ecosystem detected)"; exit 1; }
  ask_and_exit "detect a test ecosystem (looked for pytest/unittest, jest/vitest, go, cargo)"
fi

if [ "$DETECT_ONLY" -eq 1 ]; then
  say "family=$FAMILY"
  say "test_cmd=$TEST_CMD"
  say "count_regex=$COUNT_REGEX"
  say "collect_cmd=$COLLECT_CMD"
  say "test_glob=$TEST_GLOB"
  say "verified=$VERIFIED"
  exit 0
fi

say "rails init: detected $FAMILY."
[ "$VERIFIED" = "no" ] && say "  (note: $FAMILY is an UNVERIFIED adapter family in this version -- it is" \
  && say "   validation-gated like any other, but confirm the keys before trusting it.)"

# --- validate: the detected runner must actually run and count_regex must parse
say "  validating against a real run (this executes your suite once)..."
if [ -n "$COLLECT_CMD" ]; then
  capped_run 90 "$COLLECT_CMD" || true   # collect is best-effort signal
fi
capped_run 240 "$TEST_CMD"
RC=$?
if [ "$RC" -eq 124 ]; then
  ask_and_exit "validate: the test command did not finish in time (timed out)"
fi
N="$(python3 -c "import re,sys; m=re.search(sys.argv[1], open(sys.argv[2],errors='replace').read()); print(m.group(1) if m else '')" "$COUNT_REGEX" "$CAP_OUT" 2>/dev/null)"
if [ -z "$N" ]; then
  ask_and_exit "validate: count_regex did not parse a test count from a real run"
fi
if [ "$N" = "0" ]; then
  ask_and_exit "validate: the run counted 0 tests -- a zero-test suite proves nothing"
fi
if [ "$RC" -ne 0 ]; then
  ask_and_exit "validate: the test command exited nonzero (rc=$RC) -- a failing suite is not a validated adapter; fix the suite or set the keys by hand"
fi

# --- seed config.json (preserve per-repo values; NEVER write registry.json) ---
python3 - "$CFG" "$TEST_CMD" "$COUNT_REGEX" "$COLLECT_CMD" "$TEST_GLOB" "$MB" "$REMOTE" <<'PY'
import json, sys
cfg_path, test_cmd, count_regex, collect_cmd, test_glob, mb, remote = sys.argv[1:8]
try:
    c = json.load(open(cfg_path))
except Exception:
    c = {}
c.setdefault("scope", "ONE line: what this repo is for.")
c.setdefault("posture", "quiet")
c.setdefault("allow_local_commits", False)
c.setdefault("fixtures_glob", "")
c["test_cmd"], c["count_regex"], c["collect_cmd"], c["test_glob"] = \
    test_cmd, count_regex, collect_cmd, test_glob
c["main_branch"], c["remote"] = mb, remote
json.dump(c, open(cfg_path, "w"), indent=2)
PY

say "  validated: count_regex parsed $N passing test(s) from a real run."
say ""
say "wrote rails/config.json:"
say "  test_cmd     $TEST_CMD"
say "  count_regex  $COUNT_REGEX"
say "  collect_cmd  $COLLECT_CMD"
say "  test_glob    $TEST_GLOB"
say "  main_branch  $MB     remote  $REMOTE"
say "Every value is a plain key you can edit. scope is left for you to fill"
say "(it is prose, not detectable) -- one line on what this repo is for."
say ""
say "The governor is NOT yet proven -- init seeds the adapter, it never stamps."
say "verify.sh will refuse to certify any dispatch until you prove it once:"
say "  1. bash rails/verifier/verify.sh BOOTSTRAP --update-baseline   (seed the count floor)"
say "  2. bash rails/adversarial/run_eval.sh                          (prove the governor)"
say "Then drop a spec in rails/dispatches/inbox/ and run /dispatch."
