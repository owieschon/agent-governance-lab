#!/usr/bin/env bash
# Case 46 — reviewer false-positive ground truth + corpus fence (D58/D23):
# a wrong reviewer finding is flagged into the SAME append-only stream as
# every other adjudication (kind=reviewer_false_positive, D57 context shape:
# dispatch_type/subsystem/tree_hash/actor travel automatically), and that
# stream MEASURES the reviewer but never TEACHES it.
#
# RED half: the kind is validated (a bogus kind is rejected, nothing
# appended) -- and in the pre-D58 state the `flag` verb did not exist at all.
# FENCE half (the case 32 pattern, applied to the corpus): grep-proves NO
# code path reads the adjudication stream back into the reviewer prompt, the
# trigger scripts, or the renderer. This case FAILS the day such a read-back
# is added. Forbidden, not deferred.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

cp "$KIT_HOST/rails/verifier/review.sh" rails/verifier/review.sh 2>/dev/null || true
cp "$KIT_HOST/rails/verifier/handoff_review.sh" rails/verifier/handoff_review.sh 2>/dev/null || true
chmod +x rails/verifier/*.sh 2>/dev/null || true

gcount() { local n; n="$(grep -ic "$1" "$2" 2>/dev/null)" && echo "$n" || echo "${n:-0}"; }

LEDGER="rails/incidents/adjudications.jsonl"

# --- the flag records cleanly with the D57 shape ----------------------------
OUT="$(python3 rails/verifier/adjudicate.py flag . D-test reviewer_false_positive \
  "claimed a CONTRACT FAIL against an unstated constraint" 2>&1)"; RC=$?
_assert "flag reviewer_false_positive: exit 0" 0 "$RC"
_assert "record appended" 1 "$(wc -l < "$LEDGER" 2>/dev/null | tr -d ' ')"

python3 - <<'PY' > /tmp/case46_fields.$$ 2>/dev/null
import json
r = json.loads(open("rails/incidents/adjudications.jsonl").readlines()[-1])
print(r.get("kind"))
print(1 if "dispatch_type" in r else 0)
print(1 if "subsystem" in r else 0)
print(1 if r.get("tree_hash") not in (None, "", "UNKNOWN") else 0)
print(1 if r.get("actor") else 0)
print(r.get("dispatch"))
PY
{ read -r K; read -r DT; read -r SS; read -r TH; read -r AC; read -r DI; } < /tmp/case46_fields.$$
rm -f /tmp/case46_fields.$$
_assert "kind=reviewer_false_positive" "reviewer_false_positive" "$K"
_assert "D57: dispatch_type field travels" 1 "$DT"
_assert "D57: subsystem field travels" 1 "$SS"
_assert "D57: tree_hash populated" 1 "$TH"
_assert "D57: actor attributed" 1 "$AC"
_assert "dispatch recorded" "D-test" "$DI"

# --- the kind is VALIDATED: bogus kind rejected, nothing appended -----------
python3 rails/verifier/adjudicate.py flag . D-test reviewer_was_mean "nope" \
  >/dev/null 2>&1
_assert "bogus kind rejected (exit 2)" 2 "$?"
_assert "ledger unchanged after rejection" 1 \
  "$(wc -l < "$LEDGER" | tr -d ' ')"

# --- CORPUS FENCE: the stream is never read back into the reviewer ----------
# (case 32 proved the GATE never consumes reviewer output; this proves the
#  REVIEWER never consumes the judgment stream. Both directions stay severed.)
for f in .claude/agents/reviewer.md \
         rails/verifier/review.sh \
         rails/verifier/handoff_review.sh \
         rails/verifier/render_review_summary.py; do
  _assert "fence: $f never reads adjudications" 0 "$(gcount 'adjudic' "$f")"
  _assert "fence: $f never reads the incident stream" 0 "$(gcount 'incidents/' "$f")"
  _assert "fence: $f never reads stats.jsonl" 0 "$(gcount 'stats\.jsonl' "$f")"
done

finish
