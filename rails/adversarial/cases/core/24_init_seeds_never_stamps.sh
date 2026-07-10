#!/usr/bin/env bash
# rails init (Job 9a Part 1): the pre-trust write. Proven here:
#  R1 (the headline invariant) -- init SEEDS the adapter but NEVER STAMPS the
#     governor: after init there is no registry, verify.sh still refuses, and
#     only a real run_eval.sh proves it.
#  detection both directions -- python in this sandbox, node/jest in a throwaway
#     (via --detect-only, so it is deterministic without pytest/jest installed).
#  validate-or-ask (D53/D56) -- the VALIDATION branch itself must refuse:
#     a) zero collectable tests (unittest "Ran 0 tests") must not validate;
#     b) a broken import (unittest's synthetic _FailedTest, "Ran 1 test ...
#        FAILED") must not validate;
#     c) branch discrimination -- both refusals must come from the validation
#        ask ("could not validate"), NEVER the detection ask, so this case can
#        never again go green through the wrong exit path (the pre-D56 case
#        deleted tests/ entirely, detect() found no family, and the validation
#        assertions passed vacuously against the detection branch);
#     d) environment invariance -- a fixture-side seam (a root-level pytest.py
#        shim that raises ImportError) hides any host-installed pytest from
#        detect()'s `python3 -c "import pytest"` probe (cwd shadows
#        site-packages), forcing the unittest family without touching init.sh's
#        runtime surface. The red scenarios behave identically with or without
#        pytest on the host.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

INIT="rails/verifier/init.sh"

# --- detection, both directions (dry-run; no runner needs to be installed) ---
_assert "detects python in this sandbox" 1 \
  "$(bash $INIT --detect-only | grep -cE 'family=(pytest|unittest)')"
NODE="$(mktemp -d)"
mkdir -p "$NODE/rails/verifier"
cp "$INIT" "$NODE/rails/verifier/init.sh"
printf '{"devDependencies":{"jest":"^29"}}' > "$NODE/package.json"
( cd "$NODE" && git init -q )
_assert "detects node/jest in a throwaway repo" 1 \
  "$( ( cd "$NODE" && bash rails/verifier/init.sh --detect-only ) | grep -c 'family=jest')"
rm -rf "$NODE"

# --- validate-or-ask: the VALIDATION branch must refuse, in a throwaway repo
# that detect() is FORCED to see as unittest (pytest.py shim, see header d).
mk_unittest_repo() {  # mk_unittest_repo <dir> -- detectable family, sentinel config
  mkdir -p "$1/rails/verifier" "$1/tests"
  cp "$INIT" "$1/rails/verifier/init.sh"
  printf 'raise ImportError("rails eval shim: pytest hidden")\n' > "$1/pytest.py"
  touch "$1/tests/__init__.py"
  printf '{"scope":"keep me","test_cmd":"OLD-UNTOUCHED"}\n' > "$1/rails/config.json"
  cp "$1/rails/config.json" "$1/config.golden"
  ( cd "$1" && git init -q )
}

# (a) zero collectable tests: family detects, suite runs, "Ran 0 tests"
ZT="$(mktemp -d)"
mk_unittest_repo "$ZT"
_assert "shim forces unittest family (host pytest hidden, env-invariant)" 1 \
  "$( ( cd "$ZT" && bash rails/verifier/init.sh --detect-only ) | grep -c 'family=unittest')"
OUT_ZT="$( ( cd "$ZT" && bash rails/verifier/init.sh ) 2>&1 )"
RC_ZT=$?
_assert "zero-test suite -> init exits nonzero (refuses to validate)" 1 \
  "$([ "$RC_ZT" -ne 0 ] && echo 1 || echo 0)"
_assert "zero-test suite -> config byte-untouched" 1 \
  "$(cmp -s "$ZT/rails/config.json" "$ZT/config.golden" && echo 1 || echo 0)"
_assert "zero-test refusal comes from the VALIDATION branch" 1 \
  "$(printf '%s\n' "$OUT_ZT" | grep -c 'could not validate')"
_assert "zero-test refusal is NOT the detection ask (branch discrimination)" 0 \
  "$(printf '%s\n' "$OUT_ZT" | grep -c 'could not detect a test ecosystem')"
rm -rf "$ZT"

# (b) broken import (the D53 original): unittest fabricates _FailedTest and
# reports "Ran 1 test ... FAILED (errors=1)" -- N parses to 1, but the run
# exited nonzero. That must NOT count as a validated adapter.
BI="$(mktemp -d)"
mk_unittest_repo "$BI"
printf 'import zzz_nonexistent_module\n' > "$BI/tests/test_mod.py"
OUT_BI="$( ( cd "$BI" && bash rails/verifier/init.sh ) 2>&1 )"
RC_BI=$?
_assert "broken-import _FailedTest run -> init exits nonzero" 1 \
  "$([ "$RC_BI" -ne 0 ] && echo 1 || echo 0)"
_assert "broken-import run -> config byte-untouched" 1 \
  "$(cmp -s "$BI/rails/config.json" "$BI/config.golden" && echo 1 || echo 0)"
_assert "broken-import refusal comes from the VALIDATION branch" 1 \
  "$(printf '%s\n' "$OUT_BI" | grep -c 'could not validate')"
_assert "broken-import refusal is NOT the detection ask (branch discrimination)" 0 \
  "$(printf '%s\n' "$OUT_BI" | grep -c 'could not detect a test ecosystem')"
rm -rf "$BI"

# --- R1: SEEDS, NEVER STAMPS (the demonstrated invariant; green direction) ---
# strip the proof, then init on a real 2-test green suite: the adapter seeds,
# scope survives, and the governor must stay unproven.
rm -f rails/adversarial/registry.json
printf '{"scope":"keep me","posture":"quiet"}\n' > rails/config.json
bash $INIT >/dev/null 2>&1
_assert "init seeded the adapter (validated)" 1 \
  "$(python3 -c "import json;print(1 if json.load(open('rails/config.json')).get('test_cmd') else 0)")"
_assert "init preserved the per-repo scope" "keep me" \
  "$(python3 -c "import json;print(json.load(open('rails/config.json')).get('scope'))")"
_assert "init wrote NO registry (seeds, never stamps)" 1 \
  "$([ -f rails/adversarial/registry.json ] && echo 0 || echo 1)"
_assert "unproven governor -> verify still REFUSES after init" 1 "$(run_verify)"
_assert "governor_proven is the check that fired"          false "$(check_state governor_proven)"
# only a real eval pass proves it
bash rails/adversarial/run_eval.sh >/dev/null 2>&1 || true
python3 - <<'PY'
import json, subprocess
fp = subprocess.run(["python3","rails/verifier/fingerprint.py","."],capture_output=True,text=True).stdout.strip()
json.dump({"last_proven_fingerprint":fp}, open("rails/adversarial/registry.json","w"))
PY
_assert "after a real proof -> verify PASS" 0 "$(run_verify)"

# --- detection ask path stays distinct: with NO detectable family at all the
# refusal is the DETECTION message, and the config is still untouched.
rm -f tests/test_mod.py tests/__init__.py
printf '{"scope":"keep me","test_cmd":"OLD-UNTOUCHED"}\n' > rails/config.json
cp rails/config.json config.golden
OUT_ND="$(bash $INIT 2>&1)"
RC_ND=$?
_assert "no detectable family -> init exits nonzero" 1 \
  "$([ "$RC_ND" -ne 0 ] && echo 1 || echo 0)"
_assert "no detectable family -> refusal is the DETECTION ask" 1 \
  "$(printf '%s\n' "$OUT_ND" | grep -c 'could not detect a test ecosystem')"
_assert "no detectable family -> config byte-untouched" 1 \
  "$(cmp -s rails/config.json config.golden && echo 1 || echo 0)"
rm -f config.golden
finish
