#!/usr/bin/env bash
# Posture invariant (Job 8 Part A5 + floor-invariant D4): posture changes
# CEREMONY LOUDNESS ONLY. Verification is byte-for-conclusion identical in all
# three postures (verify.sh never reads posture); only gating differs (a stale
# PASS blocks in standard/strict, reports in quiet); and the catastrophic floor
# holds in every posture. This is the mechanical guarantee that posture never
# neuters verification.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

set_posture() {
  python3 - "$1" <<'PY'
import json, sys
p = "rails/config.json"; c = json.load(open(p)); c["posture"] = sys.argv[1]
json.dump(c, open(p, "w"), indent=2)
PY
}
canon() { python3 -c "import json;v=json.load(open('rails/evidence/D-test/verdict.json'));print(v['status'],sorted((k,c['pass']) for k,c in v['checks'].items()))" 2>/dev/null; }

# 1. the architectural invariant: verify never reads posture
_assert "verify.sh does not read posture"                 0 "$(grep -ic posture rails/verifier/verify.sh)"

# 2. identical verdict/conclusion across all three postures
set_posture quiet;    run_verify >/dev/null; Q="$(canon)"
set_posture standard; run_verify >/dev/null; S="$(canon)"
set_posture strict;   run_verify >/dev/null; R="$(canon)"
_assert "verify conclusion identical: quiet == standard"  "$Q" "$S"
_assert "verify conclusion identical: standard == strict" "$S" "$R"

# 3. gating differs: a stale PASS blocks in standard/strict, only reports in quiet
echo "# drift" >> src/main.py
set_posture standard; _assert "standard -> stop BLOCKED on stale verdict" 2 "$(agent_stop)"
set_posture strict;   _assert "strict -> stop BLOCKED on stale verdict"   2 "$(agent_stop)"
set_posture quiet;    _assert "quiet -> stop REPORTS, not gated (allowed)" 0 "$(agent_stop)"
( cd "$SANDBOX" && git checkout -q src/main.py )

# 4. the floor is posture-INDEPENDENT: push is blocked in every posture
set_posture quiet;    expect_blocked "floor (push) holds in quiet"  "$(agent_bash 'git push origin main')"
set_posture standard; expect_blocked "floor (push) holds in standard" "$(agent_bash 'git push origin main')"
set_posture strict;   expect_blocked "floor (push) holds in strict" "$(agent_bash 'git push origin main')"

# 5. L8 floor invariant (merged here per Job 8 Part D4): the WHOLE floor holds
# in the most-relaxed setting. quiet relaxes ceremony, never the boundary.
set_posture quiet
expect_blocked "floor (force-push) holds in quiet"    "$(agent_bash 'git push --force origin main')"
expect_blocked "floor (merge) holds in quiet"         "$(agent_bash 'git merge feature')"
expect_blocked "floor (hard reset) holds in quiet"    "$(agent_bash 'git reset --hard HEAD~1')"
expect_blocked "floor (amend) holds in quiet"         "$(agent_bash 'git commit --amend -m x')"
expect_blocked "floor (history rewrite) holds in quiet" "$(agent_bash 'git rebase -i HEAD~3')"
expect_blocked "floor (dependency add) holds in quiet" "$(agent_bash 'npm add leftpad')"
expect_blocked "floor (migration) holds in quiet"     "$(agent_bash 'alembic upgrade head')"
expect_blocked "floor (trust-layer write) holds in quiet" "$(agent_bash 'echo x >> rails/verifier/verify.sh')"
expect_blocked "floor (baseline shrink) holds in quiet" "$(agent_bash 'bash rails/verifier/verify.sh D-test --update-baseline --allow-shrink')"

finish
