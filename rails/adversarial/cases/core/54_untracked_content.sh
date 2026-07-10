#!/usr/bin/env bash
# Freshness, untracked-content (V6): a PASS is stamped against the working tree,
# so the stamp must cover the CONTENT of untracked files, not just their names.
# Otherwise an agent gets a PASS with an untracked file present, then swaps its
# content for arbitrary code -- the name is unchanged, so a name-only stamp does
# not notice and the stale PASS stands against code that changed.
#
# Also pins the companion property the fix depends on: the kit's own churning
# state under rails/ (evidence, ledgers, registry, snapshots) is excluded from
# the freshness hash, so a benign untracked file does NOT false-positive a fresh
# PASS as stale.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

note="untracked_payload.txt"
printf 'original\n' > "$note"            # present (untracked) at verify time

_assert "verify PASSes with an untracked file present"            0 "$(run_verify)"
_assert "fresh PASS + untracked present -> stop allowed (no churn FP)" 0 "$(agent_stop)"

printf 'swapped-after-pass\n' > "$note"  # same name, new content, still untracked
_assert "untracked CONTENT changed after PASS -> stop BLOCKED"     2 "$(agent_stop)"

printf 'original\n' > "$note"            # restore exact content
_assert "untracked content restored -> stop allowed"              0 "$(agent_stop)"

rm -f "$note"
finish
