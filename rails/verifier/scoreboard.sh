#!/usr/bin/env bash
#
# scoreboard.sh -- human-run program-level scoreboard (read-only).
#
# Aggregates rails/evidence/ (verdicts + stats.jsonl), rails/incidents/, and
# rails/dispatches/archive/ into a plain-text summary: dispatches completed,
# first-pass verify rate, mean iterations to green, incident count and
# accretion status. The aggregation itself is SQL over an in-memory SQLite DB;
# see rails/verifier/scoreboard.py.
#
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/rails/verifier/scoreboard.py" "$ROOT"
