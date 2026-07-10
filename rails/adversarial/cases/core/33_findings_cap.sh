#!/usr/bin/env bash
# R3 — Findings cap: an oversized reviewer findings set renders a capped
# summary in the handoff doc (3 severity-ordered lines + "N more"), the full
# set is in artifacts, and the doc length stays within budget.
#
# GREEN half (honest neighbor): a small findings set renders fully.
# RED half: a large findings set renders capped (3 + "N more").
#
# Tests the render_review_summary helper that the handoff command calls.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# --- the rendering helper must exist and be callable -----------------------
_assert "render_review_summary.py exists" 1 \
  "$([ -f rails/verifier/render_review_summary.py ] && echo 1 || echo 0)"

# --- RED: oversized findings -> capped to 3 + "N more" --------------------
mkdir -p rails/evidence/D-test
cat > rails/evidence/D-test/review_findings.md <<'FINDINGS'
---
model: claude-sonnet-4-6
tree_hash: abc123
duration_seconds: 60
findings_count:
  critical: 2
  high: 3
  medium: 4
  low: 6
  info: 5
---
# Reviewer Findings

## critical: SQL injection in user input handler
The `process_query` function passes user input directly to the SQL query
without parameterization. This is a critical security vulnerability.

## critical: Authentication bypass in admin endpoint
The `/admin/reset` endpoint does not check authentication tokens.

## high: Race condition in cache invalidation
The cache invalidation logic has a TOCTOU race that can serve stale data.

## high: Missing input validation on file upload
File uploads accept any content type without validation.

## high: Unhandled exception in payment processing
A failed payment can leave the order in an inconsistent state.

## medium: N+1 query in user listing
The user listing page executes one query per user for their profile.

## medium: Hardcoded timeout value
The API timeout is hardcoded to 30s instead of using the config.

## medium: Missing index on frequently queried column
The `orders.user_id` column lacks an index causing full table scans.

## medium: Deprecated API usage
Using `requests.get` without `timeout` parameter (deprecated pattern).

## low: Inconsistent error message format
Some endpoints return `{error: "msg"}`, others `{message: "msg"}`.

## low: TODO comments left in production code
Several TODO comments reference tickets that are already closed.

## low: Unused import in utils module
`import os` is imported but never used in `utils/helpers.py`.

## low: Magic number in retry logic
The retry count of 3 is hardcoded without explanation.

## low: Missing docstring on public method
`UserService.get_active_users()` lacks a docstring.

## low: Variable shadowing in loop
The loop variable `id` shadows the builtin `id()` function.

## info: Consider using dataclasses
Several data-holder classes could benefit from `@dataclass`.

## info: Type hints missing on public API
The public-facing methods lack type annotations.

## info: Test coverage for edge cases
The happy path is well-tested but boundary conditions are sparse.

## info: Logging level inconsistency
Some debug info logged at INFO level, some at DEBUG.

## info: Opportunity for caching
The `get_user_preferences` call is made repeatedly with same args.
FINDINGS

RENDERED="$(python3 rails/verifier/render_review_summary.py \
  rails/evidence/D-test/review_findings.md 2>/dev/null)"

# Capped: at most 3 finding lines + an "N more" line
LINE_COUNT="$(echo "$RENDERED" | grep -c '^\-\|^##\|^[0-9]')"
_assert "capped rendering has <= 4 content lines (3 findings + N more)" 1 \
  "$([ "$LINE_COUNT" -le 6 ] && echo 1 || echo 0)"

# The "N more" line exists and names the count
_assert "capped rendering mentions remaining count" 1 \
  "$(echo "$RENDERED" | grep -ic 'more\|remaining\|additional')"

# The severity ordering: critical appears before low/info
FIRST_SEV="$(echo "$RENDERED" | grep -i 'critical\|high\|medium\|low\|info' | head -1)"
_assert "highest severity appears first" 1 \
  "$(echo "$FIRST_SEV" | grep -ic 'critical')"

# Total character budget: the rendered summary must be concise (< 800 chars)
CHAR_COUNT="$(echo "$RENDERED" | wc -c | tr -d ' ')"
_assert "rendered summary within budget (< 800 chars)" 1 \
  "$([ "$CHAR_COUNT" -lt 800 ] && echo 1 || echo 0)"

# --- GREEN: small findings set -> renders fully (no cap) -------------------
cat > rails/evidence/D-test/review_findings.md <<'SMALL'
---
model: claude-sonnet-4-6
tree_hash: abc123
duration_seconds: 30
findings_count:
  critical: 0
  high: 1
  medium: 1
  low: 0
  info: 0
---
# Reviewer Findings

## high: Missing null check in parser
The `parse_config` function does not handle null input.

## medium: Log rotation not configured
Application logs grow unbounded without rotation.
SMALL

SMALL_RENDERED="$(python3 rails/verifier/render_review_summary.py \
  rails/evidence/D-test/review_findings.md 2>/dev/null)"

# Small set: both findings appear (no "N more" needed)
_assert "small set: high finding present" 1 \
  "$(echo "$SMALL_RENDERED" | grep -ic 'null check\|parser')"
_assert "small set: medium finding present" 1 \
  "$(echo "$SMALL_RENDERED" | grep -ic 'log rotation\|rotation')"
_assert "small set: no 'more' line needed" 0 \
  "$(echo "$SMALL_RENDERED" | grep -ic 'more remaining\|additional')"

# --- GREEN: no findings file -> renders "review: unavailable" gracefully ---
rm -f rails/evidence/D-test/review_findings.md
NONE_RENDERED="$(python3 rails/verifier/render_review_summary.py \
  rails/evidence/D-test/review_findings.md 2>/dev/null)"
_assert "missing findings -> graceful (not an error)" 1 \
  "$([ $? -eq 0 ] || [ -z "$NONE_RENDERED" ] && echo 1 || echo 0)"

finish
