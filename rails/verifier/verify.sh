#!/usr/bin/env bash
#
# verify.sh <dispatch-id> [--update-baseline]
#
# The keystone: your distrust, mechanized. A dispatch
# is DONE only if every check below passes against the CURRENT tree:
#
#   manifest_complete   the dispatch actually declares its proof obligations
#   full_suite          suite runs to completion, exit 0, count >= baseline
#                       (count-is-the-tell: a dropped count is a false green)
#   load_bearing        the named load-bearing tests were collected/ran BY NAME
#                       (not-exercised is not pass)
#   live_path           grep proves the tested code is on the path that ships
#   demonstrated_red    each break in the plan makes its test go red, then
#                       green again after restore (a test never seen red is
#                       unproven)
#
# Writes rails/evidence/<id>/verdict.json stamped with the tree hash.
# The Stop gate only honors a PASS whose tree hash matches the current tree.
#
# This file is the trust layer: not agent-editable. --update-baseline is
# human-only (the bash guard blocks the agent from invoking it).
#
set -u

DISPATCH="${1:-}"
MODE="${2:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG="$ROOT/rails/config.json"
BASELINE="$ROOT/rails/verifier/baseline.json"

if [ -z "$DISPATCH" ]; then
  # If exactly one dispatch is active, use it.
  ACT=()
  while IFS= read -r _ln; do ACT+=("$_ln"); done \
    < <(find "$ROOT/rails/dispatches/active" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  if [ "${#ACT[@]}" -eq 1 ]; then
    DISPATCH="$(basename "${ACT[0]}")"
  else
    echo "usage: verify.sh <dispatch-id>   (found ${#ACT[@]} active dispatches)" >&2
    exit 2
  fi
fi

DDIR="$ROOT/rails/dispatches/active/$DISPATCH"
MANIFEST="$DDIR/manifest.json"
EVID="$ROOT/rails/evidence/$DISPATCH"
mkdir -p "$EVID"

jqpy() { python3 -c "$1" "${@:2}"; }

cfg_get() {
  jqpy "
import json,sys
try:
    cfg=json.load(open('$CFG'))
except Exception:
    cfg={}
v=cfg.get(sys.argv[1], sys.argv[2] if len(sys.argv)>2 else '')
print(v if isinstance(v,str) else json.dumps(v))
" "$@"
}

TEST_CMD="$(cfg_get test_cmd 'pytest -q')"
COUNT_REGEX="$(cfg_get count_regex '([0-9]+) passed')"
COLLECT_CMD="$(cfg_get collect_cmd '')"
FLAKY_GLOB="$(cfg_get flaky_glob '')"     # the quarantine lane directory (off when empty)
FLAKY_CMD="$(cfg_get flaky_cmd '')"       # how to RUN the lane (non-gating)

PASS=0; FAIL=1
# bash 3.2 portability: bash 3.2 (stock macOS) has no associative arrays. The
# check set is fixed and its keys are valid identifiers, so results live in
# plain vars RESULT_<key>/DETAIL_<key>, read via indirect expansion (${!ref})
# in the verdict loops below. No check semantics change.
CUR_BASH="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"

# Output subtraction (Job 8 Part C1): the default output is ONE line -- PASS,
# or BLOCKED with the why and the next step. Everything else (progress notes,
# the per-check block) is one expansion away: RAILS_VERBOSE=1, or
# rails/verifier/why.sh <id>, which renders the same verdict.json in full.
# The verdict file always carries everything; only the default rendering shrank.
VERBOSE="${RAILS_VERBOSE:-0}"
note() { [ "$VERBOSE" = "1" ] && printf '%s\n' "$*"; return 0; }
say()  { printf '%s\n' "$*"; }

# ---------------------------------------------------------- governor proven
# Spec section 4: a change to the governor runs the adversarial eval BEFORE
# it takes force. Mechanized: if the trust-layer fingerprint differs from
# the one stamped at the last full eval pass, this verifier refuses to
# certify work until rails/adversarial/run_eval.sh passes again.
REG="$ROOT/rails/adversarial/registry.json"
GOV="$(jqpy "
import json,subprocess,os
cur=subprocess.run(['python3','$ROOT/rails/verifier/fingerprint.py','$ROOT'],capture_output=True,text=True).stdout.strip()
try:
    reg=json.load(open('$REG'))
except Exception:
    print('FAIL: no adversarial registry; the checks are unproven. Run: bash rails/adversarial/run_eval.sh'); raise SystemExit
if reg.get('last_proven_fingerprint')!=cur:
    print('FAIL: trust layer changed since last adversarial proof. A changed governor does not gate work until re-proven. Run: bash rails/adversarial/run_eval.sh')
    raise SystemExit
env=reg.get('environment',{})
import sys,platform
pyv='.'.join(platform.python_version_tuple()[:2])
if env.get('python') not in (None,'unknown',pyv):
    print(f\"FAIL: environment changed (python {env.get('python')} -> {pyv}); spec section 4: re-run the eval\"); raise SystemExit
bashv='$CUR_BASH'
if env.get('bash') not in (None,'unknown',bashv):
    print(f\"FAIL: environment changed (bash {env.get('bash')} -> {bashv}); spec section 4: re-run the eval\"); raise SystemExit
import shutil
cc_rec=env.get('claude_code')
cc_now='unknown'
if shutil.which('claude'):
    try:
        cc_now=subprocess.run(['claude','--version'],capture_output=True,text=True,timeout=10).stdout.strip() or 'unknown'
    except Exception:
        cc_now='unknown'
if cc_rec not in (None,'unknown','') and cc_now not in ('unknown','') and cc_rec!=cc_now:
    print(f\"FAIL: environment changed (claude_code {cc_rec} -> {cc_now}); spec section 4: re-run the eval\"); raise SystemExit
print('OK')
")"
if [ "$GOV" = "OK" ]; then
  RESULT_governor_proven=$PASS; DETAIL_governor_proven="fingerprint matches last eval pass"
else
  RESULT_governor_proven=$FAIL; DETAIL_governor_proven="${GOV#FAIL: }"
fi

# ---------------------------------------------------------------- manifest
if [ ! -f "$MANIFEST" ]; then
  RESULT_manifest_complete=$FAIL
  DETAIL_manifest_complete="missing $MANIFEST"
else
  M_OK="$(jqpy "
import json,sys,os,hashlib,subprocess
m=json.load(open('$MANIFEST'))
probs=[]
if not m.get('live_path_greps'): probs.append('no live_path_greps')
if not m.get('load_bearing_tests'): probs.append('no load_bearing_tests')
if not m.get('break_plan'): probs.append('no break_plan (demonstrated-red is mandatory)')
# Freeze: if the dispatch was approved with a manifest snapshot (snapshot.sh at
# approval), the live manifest must be byte-identical. The manifest defines the
# proof obligations, so a post-approval rewrite is the agent grading itself
# against an answer key it changed -- a real amendment re-approves and
# re-snapshots. No snapshot (older install) -> structural check only.
try:
    frozen=json.load(open('$DDIR/.oracle_snapshot.json')).get('manifest')
except Exception:
    frozen=None
if frozen:
    cur=hashlib.sha256(open('$MANIFEST','rb').read()).hexdigest()
    if cur!=frozen:
        probs.append('manifest changed after approval (re-approve to re-snapshot)')
# Grounded-on-diff: when a base ref was recorded at approval (.base_ref = HEAD
# before the agent built), the break plan must target files the dispatch
# actually changed -- not a decoy file it never touched. Otherwise green->red->
# green proves nothing about the shipped change. No base ref -> structural only.
def _changed_since_base():
    try:
        base=open('$DDIR/.base_ref').read().strip()
    except Exception:
        return None
    if not base: return None
    files=set()
    for a in (['diff','--name-only',base,'HEAD'],['diff','--name-only','HEAD'],
              ['ls-files','--others','--exclude-standard']):
        try:
            r=subprocess.run(['git']+a,capture_output=True,text=True,cwd='$ROOT')
            files.update(x for x in r.stdout.splitlines() if x.strip())
        except Exception:
            pass
    # a dispatch changes PROJECT code, never the trust layer (rails/ is
    # agent-read-only); drop rails/ paths so evidence/registry/snapshot churn
    # never counts as the dispatch's diff.
    return {f for f in files if not f.startswith('rails/')}
changed=_changed_since_base()
if changed is not None:
    stray=sorted({f for b in (m.get('break_plan') or []) for f in (b.get('files') or []) if f not in changed})
    if stray:
        probs.append('break_plan targets files not in the dispatch diff: '+', '.join(stray)+' (break the changed code, not a decoy)')
print('OK' if not probs else '; '.join(probs))
")"
  if [ "$M_OK" = "OK" ]; then
    RESULT_manifest_complete=$PASS; DETAIL_manifest_complete="ok"
  else
    RESULT_manifest_complete=$FAIL; DETAIL_manifest_complete="$M_OK"
  fi
fi

# ---------------------------------------------------------------- decisions
# Senior-engineer judgment cannot be machine-graded; its DISCLOSURE can be
# machine-required. DECISIONS.md (options considered, trade-offs, choice
# with grounds, reversibility) must exist before "done", and it travels in
# the handoff for human review. The human may exempt trivial dispatches
# via "decisions_required": false in the manifest they approve.
DEC="$(jqpy "
import json,os
try:
    m=json.load(open('$MANIFEST'))
except Exception:
    m={}
if m.get('decisions_required', True) is False:
    print('OK exempted by approved manifest'); raise SystemExit
p='$DDIR/DECISIONS.md'
if not os.path.isfile(p) or os.path.getsize(p)==0:
    print('FAIL: DECISIONS.md missing/empty -- undisclosed judgment is the violation (write options, trade-offs, choice, reversibility)'); raise SystemExit
txt=open(p,errors='replace').read().lower()
need=['options considered','trade-offs','choice','reversibility']
miss=[n for n in need if n not in txt]
print('OK structurally complete' if not miss else 'FAIL: DECISIONS.md missing sections: '+', '.join(miss))
")"
case "$DEC" in
  OK*) RESULT_decisions=$PASS; DETAIL_decisions="${DEC#OK }";;
  *)   RESULT_decisions=$FAIL; DETAIL_decisions="${DEC#FAIL: }";;
esac

# --------------------------------------------------------- oracle integrity
# Scorer-tampering defense: if the dispatch was approved with a snapshot of its
# test/fixture files (rails/verifier/snapshot.sh, run at approval), those files
# must be byte-identical at verify time unless the manifest explicitly NAMES the
# changed files ("test_changes": [paths]) -- a per-file declaration the human
# sees at the approval gate, never a single blanket on/off flag (a lone boolean
# the agent could set on its own manifest to disable the whole check is exactly
# the scorer-tampering bypass this defends against). The agent must READ tests
# to write code -- that is not blocked (see DECISIONS); what is gated is silent
# MUTATION of the thing that grades the work.
ORACLE="$(jqpy "
import json,os,hashlib
snap_p='$DDIR/.oracle_snapshot.json'
if not os.path.isfile(snap_p):
    print('NA'); raise SystemExit
snap=json.load(open(snap_p)).get('files',{})
try:
    m=json.load(open('$MANIFEST'))
except Exception:
    m={}
declared=set(m.get('test_changes',[]) or [])
changed=[]
for rel,h in snap.items():
    try:
        cur=hashlib.sha256(open(os.path.join('$ROOT',rel),'rb').read()).hexdigest()
    except Exception:
        cur='MISSING'
    if cur!=h and rel not in declared:
        changed.append(rel)
print('OK unchanged' if not changed else 'FAIL: undeclared test/fixture mutation: '+', '.join(changed))
")"
case "$ORACLE" in
  NA)  RESULT_oracle_integrity=$PASS; DETAIL_oracle_integrity="n/a (no approval snapshot)";;
  OK*) RESULT_oracle_integrity=$PASS; DETAIL_oracle_integrity="${ORACLE#OK }";;
  *)   RESULT_oracle_integrity=$FAIL; DETAIL_oracle_integrity="${ORACLE#FAIL: }";;
esac

# ----------------------------------------------------- oracle independence
# Answer-leakage defense: a load-bearing test whose expected value is produced
# by the implementation it grades proves nothing (the oracle and the subject
# are the same). Scoped to load-bearing tests; heuristic (see DECISIONS).
OIND="$(python3 "$ROOT/rails/verifier/oracle_independence.py" "$ROOT" "$MANIFEST" 2>/dev/null)"
case "$OIND" in
  OK*)   RESULT_oracle_independence=$PASS; DETAIL_oracle_independence="${OIND#OK }";;
  FAIL*) RESULT_oracle_independence=$FAIL; DETAIL_oracle_independence="${OIND#FAIL: }";;
  *)     RESULT_oracle_independence=$PASS; DETAIL_oracle_independence="n/a";;
esac

# -------------------------------------------------------------- full suite
# Stale-bytecode hazard (same class demonstrated_red.py documents and busts
# for its own phase): a same-second, same-size source rewrite passes CPython's
# timestamp+size pyc validation, so the gated suite can execute cached
# bytecode that does not match the source bytes on disk. Seen live (case 23
# CI flake): tamper -> verify -> restore landing inside one whole second made
# the restored run grade the TAMPERED pyc against clean source. The gate must
# grade the bytes on disk: clear cached bytecode and suppress repopulation for
# the gated run. No-op for non-Python suites; caches are regenerable.
find "$ROOT" \( -name .git -o -name node_modules \) -prune -o \
     -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
note "== full suite: $TEST_CMD"
( cd "$ROOT" && PYTHONDONTWRITEBYTECODE=1 bash -c "$TEST_CMD" ) >"$EVID/full_suite.log" 2>&1
SUITE_EXIT=$?
COUNT="$(jqpy "
import re,sys
txt=open('$EVID/full_suite.log',errors='replace').read()
m=re.search(r'''$COUNT_REGEX''',txt)
print(m.group(1) if m else '-1')
")"

if [ "$MODE" = "--update-baseline" ]; then
  if [ "$SUITE_EXIT" -ne 0 ] || [ "$COUNT" = "-1" ]; then
    say "refusing to baseline a failing or uncountable run (exit=$SUITE_EXIT count=$COUNT); fix the suite or count_regex, then re-run"; exit 2
  fi
  OLD_BASE="$(jqpy "
import json
try: print(json.load(open('$BASELINE')).get('test_count',0))
except Exception: print(0)
")"
  # Downward rebaselining is the test-deletion laundering path: raising the
  # floor is conservative and delegable, lowering it hides removed tests and
  # is human-only (guard_bash.py blocks --allow-shrink for the agent).
  ALLOW_SHRINK=0; [ "${3:-}" = "--allow-shrink" ] && ALLOW_SHRINK=1
  if [ "$COUNT" -lt "$OLD_BASE" ] && [ "$ALLOW_SHRINK" -ne 1 ]; then
    say "refusing to LOWER the baseline ($OLD_BASE -> $COUNT) without --allow-shrink."
    say "downward rebaselining hides deleted tests and is human-only. If the"
    say "shrink is genuinely intended, a human re-runs with --allow-shrink."
    exit 2
  fi
  printf '{"test_count": %s}\n' "$COUNT" > "$BASELINE"
  say "baseline updated: test_count=$COUNT (was $OLD_BASE)"; exit 0
fi

BASE_COUNT="$(jqpy "
import json
try: print(json.load(open('$BASELINE')).get('test_count',0))
except Exception: print(0)
")"

if [ "$SUITE_EXIT" -ne 0 ]; then
  RESULT_full_suite=$FAIL; DETAIL_full_suite="suite exit=$SUITE_EXIT (see full_suite.log)"
elif [ "$COUNT" = "-1" ]; then
  RESULT_full_suite=$FAIL; DETAIL_full_suite="could not parse test count (count_regex='$COUNT_REGEX'); a run you cannot count is not a green"
elif [ "$COUNT" -lt "$BASE_COUNT" ]; then
  RESULT_full_suite=$FAIL; DETAIL_full_suite="count dropped: $COUNT < baseline $BASE_COUNT (silent drop / partial collection)"
else
  RESULT_full_suite=$PASS; DETAIL_full_suite="exit 0, $COUNT tests (baseline $BASE_COUNT)"
fi

# ------------------------------------------------------------ load-bearing
note "== load-bearing tests, by name"
if [ -n "$COLLECT_CMD" ]; then
  ( cd "$ROOT" && bash -c "$COLLECT_CMD" ) >"$EVID/collect.log" 2>&1 || true
  SRC="$EVID/collect.log"
else
  SRC="$EVID/full_suite.log"
fi
LB_MISS="$(jqpy "
import json,sys
names=[]
try:
    m=json.load(open('$MANIFEST'))
    names+= m.get('load_bearing_tests',[])
except Exception: pass
try:
    for ln in open('$ROOT/rails/verifier/load_bearing.txt'):
        ln=ln.strip()
        if ln and not ln.startswith('#'): names.append(ln)
except Exception: pass
hay=open('$SRC',errors='replace').read()
import os
def seen(n):
    base=os.path.basename(n)
    stem=os.path.splitext(base)[0]
    return (n in hay) or (base in hay) or (stem in hay)
missing=[n for n in names if not seen(n)]
print('OK' if not missing else 'NOT COLLECTED: '+', '.join(missing))
")"
if [ "$LB_MISS" = "OK" ]; then
  RESULT_load_bearing=$PASS; DETAIL_load_bearing="all named tests present in $(basename "$SRC")"
else
  RESULT_load_bearing=$FAIL; DETAIL_load_bearing="$LB_MISS"
fi

# ------------------------------------------------ exercised assertions
# Masked-precondition defense: a load-bearing test that is collected but
# skipped/xfailed/never-run is a silent no-op (present-by-name passes
# load_bearing, but the assertion never executed). Per-test accounting over the
# suite log (needs pytest -rA / unittest -v; NA otherwise -- see DECISIONS).
EXA="$(python3 "$ROOT/rails/verifier/exercised_assertions.py" "$ROOT" "$MANIFEST" "$EVID/full_suite.log" 2>/dev/null)"
case "$EXA" in
  OK*)   RESULT_exercised_assertions=$PASS; DETAIL_exercised_assertions="${EXA#OK }";;
  NA*)   RESULT_exercised_assertions=$PASS; DETAIL_exercised_assertions="${EXA#NA }";;
  FAIL*) RESULT_exercised_assertions=$FAIL; DETAIL_exercised_assertions="${EXA#FAIL: }";;
  *)     RESULT_exercised_assertions=$PASS; DETAIL_exercised_assertions="n/a";;
esac

# --------------------------------------------------------------- live path
note "== live-path greps"
LP="$(jqpy "
import json,subprocess
try:
    m=json.load(open('$MANIFEST')); greps=m.get('live_path_greps',[])
except Exception:
    greps=[]
# Grounded-on-diff (same base ref as manifest_complete): when present, a grep
# must match a line in a file the dispatch actually CHANGED, not pre-existing
# code -- otherwise 'the new code is on the live path' is unproven and a decoy
# grep at unrelated shipped code would pass. No base ref -> match-anywhere.
def _changed_since_base():
    try:
        base=open('$DDIR/.base_ref').read().strip()
    except Exception:
        return None
    if not base: return None
    files=set()
    for a in (['diff','--name-only',base,'HEAD'],['diff','--name-only','HEAD'],
              ['ls-files','--others','--exclude-standard']):
        try:
            r=subprocess.run(['git']+a,capture_output=True,text=True,cwd='$ROOT')
            files.update(x for x in r.stdout.splitlines() if x.strip())
        except Exception:
            pass
    # a dispatch changes PROJECT code, never the trust layer (rails/ is
    # agent-read-only); drop rails/ paths so evidence/registry/snapshot churn
    # never counts as the dispatch's diff.
    return {f for f in files if not f.startswith('rails/')}
changed=_changed_since_base()
fails=[]; hits=[]
for g in greps:
    pat=g.get('pattern',''); path=g.get('path','.')
    r=subprocess.run(['grep','-RHnE',pat,path],capture_output=True,text=True,cwd='$ROOT')
    lines=[l for l in r.stdout.splitlines() if l.strip()]
    if r.returncode!=0 or not lines:
        fails.append(f\"{pat} in {path}\"); continue
    hits.append(lines[0])
    if changed is not None:
        hit_files={l.split(':',1)[0] for l in lines}
        if not (hit_files & changed):
            fails.append(f\"{pat} matches only code outside the dispatch diff ({path})\")
open('$EVID/live_path.log','w').write('\n'.join(hits))
print('OK' if not fails else 'NO MATCH: '+'; '.join(fails))
")"
if [ "$LP" = "OK" ]; then
  RESULT_live_path=$PASS; DETAIL_live_path="all greps matched (live_path.log)"
else
  RESULT_live_path=$FAIL; DETAIL_live_path="$LP -- correct in isolation is not load-bearing live"
fi

# --------------------------------------------------------- demonstrated red
note "== demonstrated-red"
# Extracted to its own file: bash 3.2 mis-parses a here-doc inside $(...) when
# the body has an apostrophe (e.g. "Python's pyc"). A plain script call is the
# bash-3.2-safe form and changes no check semantics.
DR="$(python3 "$ROOT/rails/verifier/demonstrated_red.py" "$ROOT" "$MANIFEST" "$EVID")"
if [ "$DR" = "OK" ]; then
  RESULT_demonstrated_red=$PASS; DETAIL_demonstrated_red="every break went red, restore proven green (demonstrated_red.log)"
else
  RESULT_demonstrated_red=$FAIL; DETAIL_demonstrated_red="$DR"
fi

# ------------------------------------------------------------- clean room
# Environment-dependent-green defense: re-run the suite in a FRESH git worktree
# (committed state only -- no working-tree files, no caches) and require the
# same pass count. A green that depends on an uncommitted file, a cached
# artifact, or a stale build product does not reproduce and goes red here.
# Flag, default OFF locally (it doubles suite time) and ON in CI / pre-merge.
if [ "${RAILS_CLEAN_ROOM:-0}" = "1" ] && [ "$MODE" != "--update-baseline" ]; then
  note "== clean-room (fresh worktree)"
  CRTMP="$(mktemp -d)"
  if ( cd "$ROOT" && git worktree add -q --detach "$CRTMP" HEAD ) 2>/dev/null; then
    ( cd "$CRTMP" && bash -c "$TEST_CMD" ) >"$EVID/clean_room.log" 2>&1
    CR_EXIT=$?
    CR_COUNT="$(jqpy "
import re
txt=open('$EVID/clean_room.log',errors='replace').read()
m=re.search(r'''$COUNT_REGEX''',txt)
print(m.group(1) if m else '-1')
")"
    ( cd "$ROOT" && git worktree remove --force "$CRTMP" ) 2>/dev/null; rm -rf "$CRTMP"
    if [ "$CR_EXIT" -ne 0 ] || [ "$CR_COUNT" = "-1" ]; then
      RESULT_clean_room=$FAIL; DETAIL_clean_room="suite did not reproduce in a fresh worktree (exit=$CR_EXIT count=$CR_COUNT); the green depends on working-tree state"
    elif [ "$CR_COUNT" != "$COUNT" ]; then
      RESULT_clean_room=$FAIL; DETAIL_clean_room="clean-room count $CR_COUNT != working-tree count $COUNT; the green depends on uncommitted/working-tree state"
    else
      RESULT_clean_room=$PASS; DETAIL_clean_room="reproduced in a fresh worktree ($CR_COUNT tests)"
    fi
  else
    rm -rf "$CRTMP"
    RESULT_clean_room=$PASS; DETAIL_clean_room="n/a (no git HEAD to build a worktree from)"
  fi
else
  RESULT_clean_room=$PASS; DETAIL_clean_room="n/a (clean_room off; pre-merge/CI mode, not the inner loop)"
fi

# ------------------------------------------------------------- flaky lane
# Quarantine lane (Job 9b Part 4, decision A): flakiness is RELOCATED into a
# lane directory the GATED suite does not collect (so the gate stays
# byte-for-byte deterministic -- no flaky logic inside the gate). The lane runs
# NON-GATING and its results are NAMED in the verdict (a quarantined test that
# decays into a deterministic failure stays VISIBLE, never green-by-absence).
# The ONLY way this check FAILs is QUARANTINE-SMUGGLING: a test present in the
# lane but NOT declared in the governor-held manifest (flaky_lane.json) -- i.e.
# a test relocated into the lane without a human declaration, to dodge the gate.
# Membership is human-only (flaky_lane.json lives under the agent-read-only
# rails/verifier/). Inert with zero footprint when no lane is configured (L5).
FLAKY="$(python3 - "$ROOT" "$FLAKY_GLOB" "$FLAKY_CMD" "$EVID" "$COUNT_REGEX" <<'PY'
import json, os, sys, subprocess, glob, datetime, re
root, flaky_glob, flaky_cmd, evid, count_regex = sys.argv[1:6]
if not flaky_glob.strip():
    print("NA (no quarantine lane configured)"); raise SystemExit
lane_dir = os.path.join(root, flaky_glob)
if not os.path.isdir(lane_dir):
    print("NA (lane dir '%s' absent)" % flaky_glob); raise SystemExit
def is_test_file(p):
    # a RELOCATED test is what dodges the gate; ignore build artifacts so a
    # compiled .pyc or a cache dir never reads as smuggling.
    if "__pycache__" in p.replace("\\", "/").split("/"):
        return False
    b = os.path.basename(p)
    if b.startswith(".") or b.startswith("__"):
        return False
    if b.endswith((".pyc", ".pyo")) or b in ("__init__.py",):
        return False
    return os.path.isfile(p)
lane_files = sorted(p for p in glob.glob(os.path.join(lane_dir, "**", "*"), recursive=True) if is_test_file(p))
if not lane_files:
    print("NA (lane is empty)"); raise SystemExit
# manifest: the governor-held declaration of legitimate lane members
man_path = os.path.join(root, "rails", "verifier", "flaky_lane.json")
try:
    manifest = json.load(open(man_path))
except Exception:
    manifest = []
declared = {os.path.normpath(os.path.join(root, e.get("path", ""))) for e in manifest if e.get("path")}
smuggled = [os.path.relpath(p, root) for p in lane_files if os.path.normpath(p) not in declared]
if smuggled:
    print("FAIL quarantine-smuggling: lane test(s) NOT declared in "
          "rails/verifier/flaky_lane.json: " + ", ".join(smuggled)
          + " -- a test was relocated into the lane without a human declaration "
          "(the move dodges the gate). A human adds a manifest entry "
          "(test_id/path/date/reason) to quarantine it, or removes it from the lane.")
    raise SystemExit
# run the lane NON-GATING (results named, never gate the verdict)
rc, npass = None, None
if flaky_cmd.strip():
    r = subprocess.run(["bash", "-c", flaky_cmd], capture_output=True, text=True, cwd=root)
    out = (r.stdout or "") + (r.stderr or "")
    open(os.path.join(evid, "flaky_lane.log"), "w").write(out)
    rc = r.returncode
    m = re.search(count_regex, out)
    npass = m.group(1) if m else "?"
# staleness: a long-quarantined test with no fix is pressure (feeds freshness)
today = datetime.date.today()
stale = []
for e in manifest:
    try:
        days = (today - datetime.date.fromisoformat(str(e.get("date", ""))[:10])).days
        if days >= 30:
            stale.append("%s quarantined %dd (no fix)" % (e.get("test_id", "?"), days))
    except Exception:
        pass
run = ("last run exit %s (%s via count_regex)" % (rc, npass)) if rc is not None else "not run (no flaky_cmd)"
detail = "%d declared, %s -- NON-GATING" % (len(lane_files), run)
if rc not in (None, 0):
    detail += "; a lane test FAILED this run (named, not gated)"
if stale:
    detail += "; STALE: " + "; ".join(stale)
print("OK " + detail)
PY
)"
case "$FLAKY" in
  NA*)   RESULT_flaky_lane=$PASS; DETAIL_flaky_lane="${FLAKY#NA }";;
  OK*)   RESULT_flaky_lane=$PASS; DETAIL_flaky_lane="${FLAKY#OK }";;
  FAIL*) RESULT_flaky_lane=$FAIL; DETAIL_flaky_lane="${FLAKY#FAIL }";;
  *)     RESULT_flaky_lane=$PASS; DETAIL_flaky_lane="n/a";;
esac

# ----------------------------------------------------------------- verdict
TREE="$(python3 "$ROOT/rails/verifier/treehash.py")"
HEAD="$(cd "$ROOT" && git rev-parse HEAD 2>/dev/null || echo 'NO-GIT')"
# The governor fingerprint at verify time travels in the verdict so a receipt
# rendered later is bound to what was actually in force during THIS run.
FPNOW="$(python3 "$ROOT/rails/verifier/fingerprint.py" "$ROOT")"

STATUS="PASS"
for k in governor_proven manifest_complete decisions oracle_integrity oracle_independence full_suite load_bearing exercised_assertions live_path demonstrated_red clean_room flaky_lane; do
  _r="RESULT_$k"
  [ "${!_r:-1}" -ne 0 ] && STATUS="FAIL"
done

# Build the check data as a temp JSON file (no shell expansion in heredoc,
# so triple-quotes in DETAIL values cannot inject code).
_CHECKS_TMP="$(mktemp)"
python3 -c "
import json, sys
checks = {}
for name, rc, detail in zip(sys.argv[1::3], sys.argv[2::3], sys.argv[3::3]):
    checks[name] = {'pass': int(rc) == 0, 'detail': detail}
json.dump(checks, open('$_CHECKS_TMP', 'w'))
" \
  governor_proven       "${RESULT_governor_proven:-1}"       "${DETAIL_governor_proven:-}" \
  manifest_complete     "${RESULT_manifest_complete:-1}"     "${DETAIL_manifest_complete:-}" \
  decisions             "${RESULT_decisions:-1}"             "${DETAIL_decisions:-}" \
  oracle_integrity      "${RESULT_oracle_integrity:-1}"      "${DETAIL_oracle_integrity:-}" \
  oracle_independence   "${RESULT_oracle_independence:-1}"   "${DETAIL_oracle_independence:-}" \
  full_suite            "${RESULT_full_suite:-1}"            "${DETAIL_full_suite:-}" \
  load_bearing          "${RESULT_load_bearing:-1}"          "${DETAIL_load_bearing:-}" \
  exercised_assertions  "${RESULT_exercised_assertions:-1}"  "${DETAIL_exercised_assertions:-}" \
  live_path             "${RESULT_live_path:-1}"             "${DETAIL_live_path:-}" \
  demonstrated_red      "${RESULT_demonstrated_red:-1}"      "${DETAIL_demonstrated_red:-}" \
  clean_room            "${RESULT_clean_room:-1}"            "${DETAIL_clean_room:-}" \
  flaky_lane            "${RESULT_flaky_lane:-1}"            "${DETAIL_flaky_lane:-}"

python3 - "$EVID/verdict.json" "$ROOT" "$_CHECKS_TMP" "$STATUS" "$TREE" "$HEAD" "$FPNOW" "$DISPATCH" "$MANIFEST" <<'PYEOF'
import json, sys, datetime, os
verdict_path, root, checks_path = sys.argv[1], sys.argv[2], sys.argv[3]
status, tree, head, fpnow, dispatch = sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7], sys.argv[8]
manifest_path = sys.argv[9]
# D23 corpus context: type/subsystem are OPTIONAL manifest keys -- empty
# strings when absent, never a crash (the non-fatal exhaust contract, D57).
dtype, subsystem = "", ""
try:
    _m = json.load(open(manifest_path))
    dtype = str(_m.get("type", "") or "")
    subsystem = str(_m.get("subsystem", "") or "")
except Exception:
    pass
try:
    prior = json.load(open(verdict_path))
except Exception:
    prior = None
checks = json.load(open(checks_path))
os.remove(checks_path)
# PASS -> FAIL on an UNCHANGED tree hash is a governance event: a check that
# certified this exact tree now rejects it (either the old PASS was wrong or
# the new FAIL is). Record it -- the trust layer writes; record() is idempotent.
if prior and prior.get("status") == "PASS" and status == "FAIL" \
        and prior.get("tree_hash") == tree:
    try:
        sys.path.insert(0, os.path.join(root, "rails", "verifier"))
        import incident
        fired = [k for k, v in checks.items() if not v["pass"]]
        incident.record(root, dispatch, "pass_to_fail_unchanged_tree",
                        ", ".join(fired) or "unknown",
                        "a prior verify PASS was stamped on this exact tree_hash",
                        "verify now FAILs on the identical tree_hash",
                        tree)
    except Exception:
        pass
ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
verdict = {
  "dispatch": dispatch,
  "timestamp": ts,
  "head": head,
  "tree_hash": tree,
  "governor_fingerprint": fpnow,
  "dispatch_type": dtype,
  "subsystem": subsystem,
  "status": status,
  "checks": checks,
}
json.dump(verdict, open(verdict_path, "w"), indent=2)
# Per-run verdict history (D57): verdict.json stays the canonical LATEST
# verdict every consumer reads; each run ALSO leaves its own copy, named by
# the run stamp, in the same evidence dir. This is the one record that is
# impossible to retrofit later -- the canonical file is overwritten per run.
stamp = ts.replace(":", "").replace("-", "").split(".")[0] + "Z"
evid_dir = os.path.dirname(verdict_path)
run_path = os.path.join(evid_dir, "verdict.%s.json" % stamp)
n = 1
while os.path.exists(run_path):
    n += 1
    run_path = os.path.join(evid_dir, "verdict.%s-%d.json" % (stamp, n))
json.dump(verdict, open(run_path, "w"), indent=2)
PYEOF
rm -f "$_CHECKS_TMP"

# Rejection stat: one append-only line per failing check (rails/evidence,
# outside the tree hash). Non-fatal: a stats hiccup never fails a verdict.
python3 "$ROOT/rails/verifier/stats.py" from_verdict "$ROOT" "$DISPATCH" "$EVID/verdict.json" >/dev/null 2>&1 || true

note ""
note "================ VERDICT: $STATUS ($DISPATCH) ================"
for k in governor_proven manifest_complete decisions oracle_integrity oracle_independence full_suite load_bearing exercised_assertions live_path demonstrated_red clean_room flaky_lane; do
  _r="RESULT_$k"; _d="DETAIL_$k"
  if [ "${!_r:-1}" -eq 0 ]; then ICON="PASS"; else ICON="FAIL"; fi
  note "  [$ICON] $k: ${!_d:-}"
done
note "evidence: rails/evidence/$DISPATCH/  (verdict stamped to tree $TREE)"

# The single signal that matters (default rendering): one line on PASS; on a
# block, the why and the next step. Full detail is one question away.
if [ "$STATUS" = "PASS" ]; then
  say "VERDICT: PASS ($DISPATCH) -- evidence: rails/evidence/$DISPATCH/"
  exit 0
else
  FIRST_FAIL=""; FIRST_DETAIL=""
  for k in governor_proven manifest_complete decisions oracle_integrity oracle_independence full_suite load_bearing exercised_assertions live_path demonstrated_red clean_room flaky_lane; do
    _r="RESULT_$k"; _d="DETAIL_$k"
    if [ "${!_r:-1}" -ne 0 ] && [ -z "$FIRST_FAIL" ]; then
      FIRST_FAIL="$k"; FIRST_DETAIL="${!_d:-}"
    fi
  done
  say "VERDICT: BLOCKED ($DISPATCH) -- $FIRST_FAIL: $FIRST_DETAIL"
  say "Next: fix it and re-run bash rails/verifier/verify.sh $DISPATCH (full detail: bash rails/verifier/why.sh $DISPATCH)"
  exit 1
fi
