#!/usr/bin/env bash
#
# status.sh -- read-only operator dashboard (backs the /status command).
#
# Surfaces, at a glance: active dispatches and their state, BLOCKED handoffs
# with reasons, incidents lacking a linked_case, whether the governor is
# proven (with stamp age), baseline age, and the last verify verdict.
#
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/rails/verifier/status.py" "$ROOT"
