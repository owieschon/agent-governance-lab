#!/usr/bin/env bash
# Case 45 — reviewer success path (D58): findings produced -> the handoff doc
# gets the CAPPED block per render_review_summary.py (3 severity-ordered
# lines + "N more in artifacts"), CONTRACT items before JUDGMENT items, and
# the FULL report lands in the dispatch evidence dir.
#
# Register ordering is STRUCTURAL (D45 v2.2): the stub emits reviewer.md's
# actual two-register format (## CONTRACT with ### FAIL/PASS items, then
# ## JUDGMENT with ### observations) and the renderer must parse THAT --
# contract failures first, then judgment, PASS items never rendered as
# findings, re-render never respawns the reviewer.
#
# This is the GREEN half of case 44 (a fast reviewer is not killed mid-write)
# and the wired-path complement of case 33 (which proves the renderer alone).
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

cp "$KIT_HOST/rails/verifier/review.sh" rails/verifier/review.sh 2>/dev/null || true
cp "$KIT_HOST/rails/verifier/handoff_review.sh" rails/verifier/handoff_review.sh 2>/dev/null || true
chmod +x rails/verifier/*.sh 2>/dev/null || true
HR="rails/verifier/handoff_review.sh"
_assert "handoff_review.sh exists" 1 "$([ -f "$HR" ] && echo 1 || echo 0)"

python3 - <<'PY'
import json
c = json.load(open('rails/config.json'))
c['reviewer_model'] = 'stub-model'
json.dump(c, open('rails/config.json', 'w'), indent=2)
PY

# a stub reviewer that writes findings in the TRUE v2.2 two-register format
# (reviewer.md's emission spec: ## CONTRACT / ### FAIL|PASS:, ## JUDGMENT /
# ### observation) -- the renderer must parse what the live reviewer emits.
# The stub also counts its invocations: a render after findings exist must
# NEVER respawn the reviewer (paid tokens) nor overwrite the artifact.
mkdir -p stubbin
cat > stubbin/claude <<EOF
#!/bin/bash
echo x >> "$PWD/stub_invocations.txt"
echo "\${ANTHROPIC_API_KEY:-none}" > "$PWD/stub_key.txt"
mkdir -p "$PWD/rails/evidence/D-test"
cat > "$PWD/rails/evidence/D-test/review_findings.md" <<'F'
---
model: stub-model
tree_hash: abc123
duration_seconds: 2
---
# Reviewer Findings

## CONTRACT

### FAIL: error path swallows the config parse failure
provenance: dispatch spec, error-handling clause
falsifiability: a test feeding malformed config that asserts the surfaced error
severity: critical

### FAIL: live-path grep does not cover the new branch
provenance: manifest.json live_path_greps
falsifiability: grep the shipped entrypoint for the new call
severity: high

### PASS: baseline count preserved
provenance: manifest.json baseline clause
falsifiability: re-run verify with a dropped test

## JUDGMENT

### retry loop may not scale past hundreds of items
provenance: reading the loop in src/main.py
falsifiability: a load test at realistic N

### unicode input path is untested
provenance: absence of any non-ascii fixture
falsifiability: a fixture with non-ascii input
F
exit 0
EOF
chmod +x stubbin/claude

# dedicated key seam: RAILS_REVIEWER_API_KEY reaches the reviewer CHILD as
# ANTHROPIC_API_KEY (billing scoped to the reviewer), never the wider env
PATH="$PWD/stubbin:$PATH" RAILS_REVIEWER_API_KEY=test-key-123 \
  bash "$HR" launch D-test --timeout 10 >/dev/null 2>&1
RENDER="$(PATH="$PWD/stubbin:$PATH" bash "$HR" render D-test --timeout 10 2>&1)"
RC=$?

_assert "reviewer child sees the dedicated key as ANTHROPIC_API_KEY" \
  "test-key-123" "$(cat stub_key.txt 2>/dev/null || echo missing)"

_assert "render exit 0" 0 "$RC"
_assert "findings block rendered (not 'unavailable')" 0 \
  "$(echo "$RENDER" | grep -c 'review: unavailable')"

# capped per render_review_summary.py: 3 findings + "N more in artifacts"
_assert "exactly 3 finding lines shown" 3 \
  "$(echo "$RENDER" | grep -c '^- \*\*')"
_assert "'1 more in artifacts' line present" 1 \
  "$(echo "$RENDER" | grep -c '1 more in artifacts')"
_assert "highest severity first" 1 \
  "$(echo "$RENDER" | grep '^- \*\*' | head -1 | grep -ic 'critical')"

# register order is STRUCTURAL: contract failures before judgment items,
# never interleaved (D45 v2.2), and a PASS item is not a rendered finding
LASTC="$(echo "$RENDER" | grep -n '\*\*FAIL' | tail -1 | cut -d: -f1)"
FIRSTJ="$(echo "$RENDER" | grep -in 'judgment' | head -1 | cut -d: -f1)"
_assert "CONTRACT items render before JUDGMENT items" 1 \
  "$([ -n "$LASTC" ] && [ -n "$FIRSTJ" ] && [ "$LASTC" -lt "$FIRSTJ" ] && echo 1 || echo 0)"
_assert "PASS items are not rendered as findings" 0 \
  "$(echo "$RENDER" | grep -c 'baseline count preserved')"

# DX budget: the block fits inside the existing handoff read
_assert "rendered block within budget (< 800 chars)" 1 \
  "$([ "$(echo "$RENDER" | wc -c | tr -d ' ')" -lt 800 ] && echo 1 || echo 0)"

# the FULL report landed in the dispatch evidence dir (all 5 items, header)
FULL="rails/evidence/D-test/review_findings.md"
_assert "full report in evidence dir" 1 "$([ -f "$FULL" ] && echo 1 || echo 0)"
_assert "full report keeps all 5 register items" 5 "$(grep -c '^### ' "$FULL")"
_assert "full report carries the YAML header (model)" 1 \
  "$(grep -c '^model:' "$FULL")"

# and the block lands in the handoff doc the script path writes
{ echo "# Handoff: D-test"; echo; printf '%s\n' "$RENDER"; } > rails/handoff/D-test.md
_assert "handoff doc carries the capped block" 1 \
  "$(grep -c '1 more in artifacts' rails/handoff/D-test.md)"

# re-render is a READ: with findings on disk, a second render (the
# `rails review <id>` alias path) must not respawn the reviewer (paid
# tokens) and must not overwrite the artifact
SUM_BEFORE="$(cksum "$FULL")"
RENDER2="$(PATH="$PWD/stubbin:$PATH" bash "$HR" render D-test --timeout 10 2>&1)"
_assert "second render still renders the block" 1 \
  "$(echo "$RENDER2" | grep -c '1 more in artifacts')"
_assert "second render does NOT respawn the reviewer" 1 \
  "$(wc -l < stub_invocations.txt | tr -d ' ')"
_assert "findings artifact byte-unchanged by re-render" "$SUM_BEFORE" \
  "$(cksum "$FULL")"

finish
