#!/usr/bin/env bash
# Receipt provenance (Job 8 Part C3): a receipt is RENDERING over verified
# data. Proven here: (1) no PASS verdict -> no receipt (with the next step);
# (2) on PASS it renders with a provenance whose evidence content hash equals
# an independent recomputation; (3) re-rendering an unchanged run is
# byte-identical (deterministic -- provenance survives re-render); (4) the
# hash tracks the evidence bytes (a perturbed evidence file changes it);
# (5) a non-PASS verdict refuses (no receipt for unverified work).
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# 1. no verdict yet -> refused, and the refusal carries the next step
ERR="$(bash rails/verifier/receipt.sh D-test 2>&1 >/dev/null; true)"
_assert "no verdict -> no receipt" 1 \
  "$(bash rails/verifier/receipt.sh D-test >/dev/null 2>&1; echo $?)"
_assert "refusal states the next step (run verify)" 1 \
  "$(printf '%s' "$ERR" | grep -c 'verify.sh D-test')"

# 2. verified work renders, and the provenance hash is real
printf '# Toy add stays correct on the live path\n' > rails/dispatches/active/D-test/dispatch.md
_assert "clean dispatch verifies (PASS)" 0 "$(run_verify)"
_assert "receipt renders on PASS" 0 \
  "$(bash rails/verifier/receipt.sh D-test >/dev/null 2>&1; echo $?)"
R="rails/handoff/D-test.receipt.md"
_assert "receipt file exists" 1 "$([ -f "$R" ] && echo 1 || echo 0)"
_assert "receipt carries a provenance section" 1 "$(grep -c '^## Provenance' "$R")"
RH="$(sed -n 's/.*evidence content hash (sha256): \([0-9a-f]*\).*/\1/p' "$R")"
IH="$(python3 - <<'PY'
import hashlib, os
h = hashlib.sha256()
d = "rails/evidence/D-test"
for fn in sorted(os.listdir(d)):
    p = os.path.join(d, fn)
    if os.path.isfile(p):
        h.update(fn.encode()); h.update(open(p, "rb").read())
print(h.hexdigest())
PY
)"
_assert "provenance hash equals independent recomputation" "$IH" "$RH"

# 3. deterministic: re-render of an unchanged run is byte-identical
cp "$R" "$R.first"
bash rails/verifier/receipt.sh D-test >/dev/null 2>&1
_assert "re-render is byte-identical (provenance survives re-render)" 0 \
  "$(cmp -s "$R" "$R.first"; echo $?)"

# 4. the hash tracks the evidence bytes
echo "perturb" >> rails/evidence/D-test/full_suite.log
bash rails/verifier/receipt.sh D-test >/dev/null 2>&1
RH2="$(sed -n 's/.*evidence content hash (sha256): \([0-9a-f]*\).*/\1/p' "$R")"
_assert "perturbed evidence changes the provenance hash" 1 \
  "$([ "$RH2" != "$RH" ] && echo 1 || echo 0)"

# 5. a non-PASS verdict refuses: receipts render verified work only
python3 - <<'PY'
import json
p = "rails/evidence/D-test/verdict.json"
v = json.load(open(p)); v["status"] = "FAIL"
json.dump(v, open(p, "w"), indent=2)
PY
_assert "non-PASS verdict -> no receipt" 1 \
  "$(bash rails/verifier/receipt.sh D-test >/dev/null 2>&1; echo $?)"
finish
