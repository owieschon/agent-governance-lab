#!/usr/bin/env bash
# Draft-vs-verdict integrity (Job 5 DELTA 1 / 5.A, D57): the agent's
# hypothesized_mechanism + minimal_repro land on the incident explicitly
# marked DRAFT; the human verdict is a NEW append carrying actor attribution
# (the incident append-only law: a verdict is a new record, never an edit of
# the draft). Proven here:
#   - the draft fields record verbatim and carry hypothesis_status DRAFT;
#   - a record without the optional fields still carries the schema (empty);
#   - the human verdict appends a NEW record with actor + verbatim text, and
#     the draft is BYTE-UNCHANGED after it;
#   - a second verdict appends again (correction history stays);
#   - the real guards (guard_files/guard_bash, the way case 12 drives them)
#     block every rewrite path of an existing record -- draft AND verdict --
#     while a NEW record path stays writable;
#   - verdict records never read as unlinked incidents (no false block on
#     the governor stamp).
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

jget() {  # jget <json-file> <key> -> JSON-encoded value (null when absent)
  python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])).get(sys.argv[2])))' "$1" "$2"
}
rget() {  # rget <json-file> <key> -> raw string value
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"
}

# the agent records an incident WITH the draft fields
python3 rails/verifier/incident.py record . D-test blocked full_suite \
  "claimed the suite was green" "suite exits 1" treeD \
  "the model conflated catalog ids with SKUs" \
  "echo PIPE-104 | python3 -m src.main" >/dev/null 2>&1
REC="$(grep -l '"tree_hash": "treeD"' rails/incidents/INC-*.json 2>/dev/null | head -1)"
_assert "incident with draft fields exists" 1 "$([ -n "$REC" ] && [ -f "$REC" ] && echo 1 || echo 0)"
_assert "hypothesized_mechanism recorded verbatim" \
  '"the model conflated catalog ids with SKUs"' "$(jget "$REC" hypothesized_mechanism)"
_assert "minimal_repro recorded verbatim" \
  '"echo PIPE-104 | python3 -m src.main"' "$(jget "$REC" minimal_repro)"
_assert "hypothesis is explicitly marked DRAFT" '"DRAFT"' "$(jget "$REC" hypothesis_status)"

# a record WITHOUT the optional fields still carries the schema (empty, no crash)
_assert "record without draft fields exits 0" 0 \
  "$(python3 rails/verifier/incident.py record . D-bare blocked stop_gate c o treeE >/dev/null 2>&1; echo $?)"
RECB="$(grep -l '"tree_hash": "treeE"' rails/incidents/INC-*.json 2>/dev/null | head -1)"
_assert "no draft supplied -> empty hypothesized_mechanism" '""' "$(jget "$RECB" hypothesized_mechanism)"
_assert "no draft supplied -> empty minimal_repro"          '""' "$(jget "$RECB" minimal_repro)"

# the human verdict is APPENDED as a NEW record; the draft stays byte-identical
INCID="$(rget "$REC" id)"
cp "$REC" "$REC.before"
_assert "human verdict (corrected) exits 0" 0 \
  "$(python3 rails/verifier/incident.py verdict . "$INCID" corrected owen \
       "actually a tokenizer artifact, not conflation" >/dev/null 2>&1; echo $?)"
VF="$(ls "rails/incidents/$INCID".verdict-*.json 2>/dev/null | head -1)"
_assert "the verdict is a NEW record (its own file)" 1 \
  "$([ -n "$VF" ] && [ -f "$VF" ] && echo 1 || echo 0)"
_assert "verdict carries the actor (whose verdict it is)" '"owen"' "$(jget "$VF" actor)"
_assert "verdict references its incident" "\"$INCID\"" "$(jget "$VF" incident_id)"
_assert "verdict carries the human text verbatim" \
  '"actually a tokenizer artifact, not conflation"' "$(jget "$VF" note)"
_assert "verdict records its kind" '"corrected"' "$(jget "$VF" verdict)"
_assert "the DRAFT is byte-unchanged after the verdict" 0 \
  "$(cmp -s "$REC" "$REC.before"; echo $?)"

# correction history STAYS: a second verdict appends, never replaces
python3 rails/verifier/incident.py verdict . "$INCID" confirmed owen \
  "on reflection the draft was right" >/dev/null 2>&1
_assert "a second verdict appends (history retained)" 2 \
  "$(ls "rails/incidents/$INCID".verdict-*.json 2>/dev/null | wc -l | tr -d ' ')"
_assert "the draft is STILL byte-unchanged" 0 "$(cmp -s "$REC" "$REC.before"; echo $?)"

# a verdict must point at a real incident
_assert "verdict on an unknown incident refuses (exit 2)" 2 \
  "$(python3 rails/verifier/incident.py verdict . INC-nope confirmed owen x >/dev/null 2>&1; echo $?)"
# and at a valid status
_assert "verdict with an unknown status refuses (exit 2)" 2 \
  "$(python3 rails/verifier/incident.py verdict . "$INCID" maybe owen x >/dev/null 2>&1; echo $?)"

# the append-only guard blocks every rewrite path of an EXISTING record
RELREC="rails/incidents/$(basename "$REC")"
_assert "agent Edit of the draft -> blocked" 2 "$(agent_edit "$RELREC")"
expect_blocked "agent shell-rewrite of the draft" "$(agent_bash "echo rewritten > $RELREC")"
expect_blocked "agent shell-delete of the draft"  "$(agent_bash "rm $RELREC")"
RELV="rails/incidents/$(basename "$VF")"
_assert "agent Edit of an existing verdict -> blocked" 2 "$(agent_edit "$RELV")"
# ... while a NEW record path stays writable (append-only, not frozen)
_assert "a NEW record path stays agent-writable" 0 "$(agent_edit "rails/incidents/INC-brandnew.json")"

# verdict records are not incidents: they never read as unlinked (no false
# block on the stamp). Link the two real incidents (the human act), then the
# gate must clear even though the verdict files carry no linked_case.
python3 - "$REC" "$RECB" <<'PY'
import json, sys
for p in sys.argv[1:]:
    r = json.load(open(p))
    r["linked_case"] = "core/42_draft_vs_verdict"
    json.dump(r, open(p, "w"), indent=2)
PY
rm -f "$REC.before"
_assert "linked incidents + verdict records -> stamp gate clear" 0 \
  "$(python3 rails/verifier/incident.py check . >/dev/null 2>&1; echo $?)"

# the dashboards must agree with the gate: a verdict append is not an
# incident, so scoreboard/status report zero UNLINKED and count only the
# two real incidents (display contradicting the gate is the violation).
_assert "scoreboard counts only real incidents (not verdict appends)" 1 \
  "$(bash rails/verifier/scoreboard.sh 2>/dev/null | grep -Ec 'incidents recorded: +2$')"
_assert "scoreboard accretion clear (verdicts never UNLINKED)" 1 \
  "$(bash rails/verifier/scoreboard.sh 2>/dev/null | grep -c 'clear (all incidents linked')"
_assert "status: verdict appends never read as UNLINKED" 1 \
  "$(bash rails/verifier/status.sh 2>/dev/null | grep -c 'incidents: 2 recorded, 0 UNLINKED')"
finish
