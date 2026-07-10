#!/usr/bin/env bash
# Exhaust context (Job 5 DELTA 1, D57): every durable exhaust record carries
# enough CONTEXT for a year-later segmentation -- dispatch type/subsystem from
# the manifest (OPTIONAL keys: empty strings when absent, never a crash),
# alongside timestamp/dispatch/tree_hash. Proven here:
#   (a) an incident on a dispatch whose manifest sets type/subsystem carries
#       both + the core context; a manifest WITHOUT the keys (or no manifest
#       at all) yields empty strings and exit 0 -- the non-fatal contract;
#   (c) stats.jsonl lines written by a verify run carry
#       dispatch_type/subsystem/tree_hash alongside the existing fields, and
#       verdict.json itself is stamped with type/subsystem;
#   (d) per-run verdict history: each verify run leaves its own per-run
#       verdict file AND the canonical verdict.json consumers read;
#   (e) economics fields exist and are null when the harness exposes no
#       usage -- never estimated, never defaulted (the review_minutes rule);
#   (f) no exhaust writer references releases.jsonl (a CLOSED ledger, D55).
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

jget() {  # jget <json-file> <key> -> JSON-encoded value (null when absent)
  python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])).get(sys.argv[2])))' "$1" "$2"
}
sget() {  # sget <key> -> JSON value from the LAST stats.jsonl line, or "absent"
  python3 -c '
import json,sys
rows=[json.loads(l) for l in open("rails/evidence/stats.jsonl") if l.strip()]
k=sys.argv[1]; r=rows[-1]
print("absent" if k not in r else json.dumps(r[k]))' "$1"
}

# (a) manifest WITH type/subsystem -> the incident carries both + core context
python3 - <<'PY'
import json
p = "rails/dispatches/active/D-test/manifest.json"
m = json.load(open(p)); m["type"] = "feature"; m["subsystem"] = "parser"
json.dump(m, open(p, "w"), indent=2)
PY
python3 rails/verifier/incident.py record . D-test blocked stop_gate \
  "agent declared BLOCKED" "third strike on full_suite" treeA >/dev/null 2>&1
REC="$(grep -l '"tree_hash": "treeA"' rails/incidents/INC-*.json 2>/dev/null | head -1)"
_assert "incident record exists" 1 "$([ -n "$REC" ] && [ -f "$REC" ] && echo 1 || echo 0)"
_assert "incident carries dispatch_type from the manifest" '"feature"' "$(jget "$REC" dispatch_type)"
_assert "incident carries subsystem from the manifest"     '"parser"'  "$(jget "$REC" subsystem)"
_assert "incident still carries dispatch"                  '"D-test"'  "$(jget "$REC" dispatch)"
_assert "incident still carries tree_hash"                 '"treeA"'   "$(jget "$REC" tree_hash)"
_assert "incident carries a timestamp" 1 \
  "$(python3 -c "import json;print(1 if json.load(open('$REC')).get('timestamp') else 0)")"

# (a2) manifest WITHOUT the keys -> empty strings, exit 0 (non-fatal contract)
mkdir -p rails/dispatches/active/D-noctx
printf '{"id": "D-noctx"}\n' > rails/dispatches/active/D-noctx/manifest.json
_assert "manifest without the keys -> record exits 0 (never crashes)" 0 \
  "$(python3 rails/verifier/incident.py record . D-noctx blocked stop_gate c o treeB >/dev/null 2>&1; echo $?)"
REC2="$(grep -l '"tree_hash": "treeB"' rails/incidents/INC-*.json 2>/dev/null | head -1)"
_assert "missing type key -> empty string"      '""' "$(jget "$REC2" dispatch_type)"
_assert "missing subsystem key -> empty string" '""' "$(jget "$REC2" subsystem)"

# (a3) no manifest at all -> still empty strings, exit 0
_assert "no manifest at all -> record exits 0" 0 \
  "$(python3 rails/verifier/incident.py record . D-ghost blocked stop_gate c o treeC >/dev/null 2>&1; echo $?)"
REC3="$(grep -l '"tree_hash": "treeC"' rails/incidents/INC-*.json 2>/dev/null | head -1)"
_assert "no manifest -> empty dispatch_type" '""' "$(jget "$REC3" dispatch_type)"

# (c)+(e) a FAILING verify run fires the stats writer; its lines carry context
sed_i 's/a + b/a - b/' src/mod.py
_assert "broken suite -> verify FAILs (the stats writer fires)" 1 "$(run_verify)"
V="rails/evidence/D-test/verdict.json"
_assert "verdict.json is stamped with dispatch_type" '"feature"' "$(jget "$V" dispatch_type)"
_assert "verdict.json is stamped with subsystem"     '"parser"'  "$(jget "$V" subsystem)"
TREE="$(jget "$V" tree_hash)"
_assert "stats line carries dispatch_type"           '"feature"' "$(sget dispatch_type)"
_assert "stats line carries subsystem"               '"parser"'  "$(sget subsystem)"
_assert "stats line tree_hash matches the verdict's" "$TREE"     "$(sget tree_hash)"
_assert "input_tokens EXISTS and is null when no usage is exposed (never estimated)" \
  null "$(sget input_tokens)"
_assert "output_tokens EXISTS and is null when no usage is exposed (never estimated)" \
  null "$(sget output_tokens)"
# the stop-gate writer obeys the same null rule -- no guessing path anywhere
python3 rails/verifier/stats.py stop . D-test stop_gate >/dev/null 2>&1
_assert "stop-source line carries dispatch_type too" '"feature"' "$(sget dispatch_type)"
_assert "stop-source line tokens are null too"       null        "$(sget input_tokens)"
_assert "no stats line EVER carries a defaulted token count" 0 \
  "$(grep -c '"input_tokens": 0' rails/evidence/stats.jsonl)"

# (d) verdict history: two more runs leave BOTH per-run copies + the canonical
sed_i 's/a - b/a + b/' src/mod.py
N0="$(ls rails/evidence/D-test/verdict.*.json 2>/dev/null | wc -l | tr -d ' ')"
# manifest was amended (type/subsystem) above; re-snapshot so the freeze matches
( cd "$SANDBOX" && bash rails/verifier/snapshot.sh D-test ) >/dev/null 2>&1
_assert "restored tree -> verify PASS (run 1)" 0 "$(run_verify)"
sleep 1  # distinct stamps keep the per-run names chronologically sortable
_assert "verify PASS (run 2)" 0 "$(run_verify)"
N2="$(ls rails/evidence/D-test/verdict.*.json 2>/dev/null | wc -l | tr -d ' ')"
_assert "each verify run left its own per-run verdict file" "$((N0 + 2))" "$N2"
_assert "canonical verdict.json still exists where consumers expect it" 1 \
  "$([ -f "$V" ] && echo 1 || echo 0)"
LATEST="$(ls rails/evidence/D-test/verdict.*.json 2>/dev/null | tail -1)"
_assert "latest per-run copy is byte-identical to the canonical verdict" 0 \
  "$(cmp -s "$LATEST" "$V"; echo $?)"

# (f) no exhaust writer references releases.jsonl (zero new dependence, D55)
_assert "no exhaust writer references releases.jsonl" 0 \
  "$(grep -l 'releases.jsonl' rails/verifier/incident.py rails/verifier/stats.py \
       rails/verifier/adjudicate.py rails/verifier/verify.sh \
       rails/verifier/receipt.sh 2>/dev/null | wc -l | tr -d ' ')"
finish
