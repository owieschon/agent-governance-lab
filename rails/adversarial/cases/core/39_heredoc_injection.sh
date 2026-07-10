#!/usr/bin/env bash
# Heredoc injection in verify.sh verdict block: the verdict heredoc uses
# unquoted <<PYEOF, so DETAIL values containing triple-quotes (""") escape
# the Python string and crash the verdict writer. No verdict.json is produced,
# which is a DOS on the verification system. The fix uses quoted <<'PYEOF'.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

# ---- honest neighbor: normal verify works ----
_assert "clean verify PASS" 0 "$(run_verify)"
VERDICT_OK="$(python3 -c "
import json
try:
    v = json.load(open('$SANDBOX/rails/evidence/D-test/verdict.json'))
    print('valid' if 'status' in v else 'invalid')
except Exception:
    print('invalid')
")"
_assert "clean verdict is valid JSON" "valid" "$VERDICT_OK"

# ---- injection: a test name with triple-quotes crashes the verdict writer ----
# The load_bearing detail includes test names from the manifest. A test name
# containing """ escapes the Python string in the unquoted heredoc.
python3 -c "
import json
m = json.load(open('$SANDBOX/rails/dispatches/active/D-test/manifest.json'))
m['load_bearing_tests'].append('test_with_\"\"\"_injection')
json.dump(m, open('$SANDBOX/rails/dispatches/active/D-test/manifest.json', 'w'), indent=2)
"
# Remove prior verdict so we can tell if the new one was written
rm -f "$SANDBOX/rails/evidence/D-test/verdict.json"

# Run verify — the heredoc will crash on the """ in the DETAIL
( cd "$SANDBOX" && bash rails/verifier/verify.sh D-test >/dev/null 2>&1 ) || true

INJECT_VALID="$(python3 -c "
import json
try:
    v = json.load(open('$SANDBOX/rails/evidence/D-test/verdict.json'))
    print('valid' if 'status' in v and 'checks' in v else 'invalid')
except Exception:
    print('missing')
")"
_assert "triple-quote injection -> verdict.json still produced and valid" "valid" "$INJECT_VALID"

# ---- restore clean manifest ----
python3 -c "
import json
m = json.load(open('$SANDBOX/rails/dispatches/active/D-test/manifest.json'))
m['load_bearing_tests'] = ['test_add_positive']
json.dump(m, open('$SANDBOX/rails/dispatches/active/D-test/manifest.json', 'w'), indent=2)
"

finish
