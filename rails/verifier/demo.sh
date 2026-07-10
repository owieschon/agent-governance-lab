#!/usr/bin/env bash
#
# demo.sh -- the 5-minute demonstrated catch (Job 9a Part 2; the L4 reveal).
#
# The FIRST touch: runs on a fresh clone with ZERO config, in a disposable
# sandbox (never the live repo), and shows the user a REAL verifier catch
# before asking them to invest in anything. The catch is staged but not faked:
# it is the actual verify.sh producing an actual verdict against a planted
# violation -- a green suite the verifier refuses to stand behind, the thing a
# plain "did the tests pass?" check waves through. After the catch lands, and
# only then, it points at the next layer (rails init -> /dispatch). That order
# is L4: the layer is earned by a benefit the user just watched, not by the
# README.
#
# Also a distribution asset: the output is captured for the README, so it is
# dry, single-line where it states a verdict (L9, and Job 8's output
# discipline), and self-contained. Zero prerequisites is a hard requirement.
#
# Read-only on your repo: everything happens under a mktemp sandbox that is
# removed on exit. Lives in the trust layer; not agent-editable.
#
set -u
HOST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

line() { printf '%s\n' "$*"; }
rule() { line "------------------------------------------------------------"; }

SB=""
cleanup() { [ -n "$SB" ] && [ -d "$SB" ] && rm -rf "$SB"; }
trap cleanup EXIT

line ""
line "3xit2 demo -- a real catch, in a sandbox, in about a minute."
line "Nothing here touches your repo; no config needed. (sandbox is removed on exit.)"
rule

# --- build the disposable sandbox (the eval's own fixture: a tiny repo with a
#     proven governor and a clean, passing 2-test suite) --------------------
SB="$(bash "$HOST/rails/adversarial/fixture.sh" 2>/dev/null)"
if [ -z "$SB" ] || [ ! -d "$SB" ]; then
  line "could not build the demo sandbox (the eval fixture did not run)."
  line "Next: from the kit root, run bash rails/adversarial/run_eval.sh to see why."
  exit 1
fi
cd "$SB"

line ""
line "Setup: a tiny repo with a passing 2-test suite, already committed and"
line "approved. Now an agent 'finishes a task' -- but one test won't pass. So"
line "instead of fixing the code, it quietly EDITS THE TEST to assert the value"
line "its buggy code produces. The suite is now green. A 'did the tests pass?'"
line "check says yes, ship it."
line ""

# the planted violation: tamper with the test that grades the work so a buggy
# value passes. Real, not narrated -- the verifier runs against this actual
# tree, and the fixture snapshotted the test files at approval.
python3 - <<'PY'
src = "tests/test_mod.py"
t = open(src).read()
# weaken the assertion: make it assert the (wrong) value the agent's bug yields
open(src, "w").write(t.replace("self.assertEqual(add(-2, -3), -5)",
                               "self.assertEqual(add(-2, -3), 99)  # 'fixed'"))
PY

line "Here is what the 3xit2 verifier says about that green:"
rule
# the REAL verifier, default single-line output -- this is the catch.
bash rails/verifier/verify.sh D-test 2>/dev/null | grep -E '^VERDICT:|^Next:'
rule
line ""
line "The suite was green. But the verifier snapshotted the tests when the work"
line "was approved, and it caught that the agent changed the very thing that"
line "grades it. Green built on a moved goalpost is not green. That is the catch"
line "a plain test run cannot make: the agent does not get to edit its own"
line "grader. (It also checks the tested code is on the path that ships, that the"
line "test count never silently drops, and that every test was seen to go red"
line "before it went green.)"
line ""

# --- the other direction: the verifier is not a blanket blocker. Restore the
#     test; real work certifies. (Quiet on good, loud on bad -- the eval's own
#     both-directions discipline, shown to the user.) ------------------------
( cd "$SB" && git checkout -q tests/test_mod.py )
line "And when the work is actually whole, the same verifier passes it:"
rule
bash rails/verifier/verify.sh D-test 2>/dev/null | grep -E '^VERDICT:'
rule
line ""
line "That is the whole idea: an exogenous check the agent cannot satisfy by"
line "cutting a corner, and a clean pass when the work is real."
line ""
line "To run this on YOUR repo:"
line "  1. rails init     -- detects your test setup and writes the adapter"
line "  2. run_eval.sh    -- proves the governor once (it refuses to certify"
line "                       until you do)"
line "  3. /dispatch      -- turn a task into a tracked unit of work, /go to build"
line ""
line "Nothing was changed in any repo of yours; the sandbox is now removed."
