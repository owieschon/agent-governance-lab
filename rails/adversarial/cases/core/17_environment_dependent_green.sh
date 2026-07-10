#!/usr/bin/env bash
# Environment-dependent green (Job 7 Part 1, class D): a suite that is green
# because of a working-tree artifact (an uncommitted file, a cache, a stale
# build) does not reproduce from the committed state. clean_room re-runs the
# suite in a fresh git worktree (HEAD only) and requires the same pass count.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# clean-room-aware verify runner (the mode is OFF by default; ON in CI/pre-merge)
crv() { ( cd "$SANDBOX" && RAILS_CLEAN_ROOM=1 bash rails/verifier/verify.sh D-test >/dev/null 2>&1; echo $? ); }

_assert "committed tree reproduces -> clean_room verify PASS"  0 "$(crv)"
_assert "clean_room passes when committed == working tree"  true "$(check_state clean_room)"

# plant a working-tree-only green: an UNCOMMITTED passing test (not at HEAD)
cat > tests/test_uncommitted.py <<'EOF'
import unittest
class T(unittest.TestCase):
    def test_only_in_working_tree(self):
        self.assertTrue(True)
EOF
# re-seed baseline so full_suite does not fire on the higher count -- isolate clean_room
bash rails/verifier/verify.sh BOOTSTRAP --update-baseline >/dev/null 2>&1

_assert "working-tree suite is green (3 tests)"                0 "$(PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests >/dev/null 2>&1; echo $?)"
_assert "uncommitted-dependent green -> clean_room verify FAILs" 1 "$(crv)"
_assert "clean_room is the check that fired"               false "$(check_state clean_room)"
finish
