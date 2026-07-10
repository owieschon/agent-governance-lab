#!/usr/bin/env bash
# Observer runner contract + notify default-off (D59 second half, Bundle 4
# phase B). The runner is the one piece of observer machinery that ACTS, so
# its contract is proven with a FIXTURE observer (no live network):
#   - files only TEMPLATED inbox items (source/trigger/evidence/problem/
#     SUGGESTED-PRIORITY), create-only (an existing item is never overwritten);
#   - dedups against its state (a second run files nothing new);
#   - rate-limits floods: 5 candidates -> 3 filed + overflow carried in state,
#     drained on the next run, never dropped;
#   - a credential-less SaaS observer is a silent-and-logged skip (exit 0):
#     a cron run never breaks because a key is absent;
#   - drift (the local self-check observer) files only on a failing/stale repo.
# notify.sh must be OFF by default: an unconfigured or token-less install
# sends nothing, ever; enabled sends ONE batched line per observer run (repo,
# event, artifact path -- no payloads, no secrets written to any file).
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

RUN="rails/observers/run_observer.sh"
NOTIFY="rails/notify/notify.sh"
INBOX="rails/dispatches/inbox"
mkdir -p "$INBOX"

# --- shipped surface exists ---------------------------------------------------
_assert "runner shipped" 1 "$([ -f "$RUN" ] && echo 1 || echo 0)"
_assert "extract.py shipped" 1 "$([ -f rails/observers/extract.py ] && echo 1 || echo 0)"
_assert "notify.sh shipped" 1 "$([ -f "$NOTIFY" ] && echo 1 || echo 0)"
NDEF=0
for d in sentry phoenix langsmith posthog ci deps drift; do
  [ -f "rails/observers/$d.json" ] && NDEF=$((NDEF + 1))
done
_assert "all 7 observer definitions shipped" 7 "$NDEF"
_assert "no definition carries a credential VALUE (env var NAMES only)" 0 \
  "$(grep -lE '(api_key|token|secret)"\s*:\s*"[A-Za-z0-9_-]{20,}' rails/observers/*.json 2>/dev/null | wc -l | xargs)"

# --- a curl stub so notify behavior is observable without network -------------
STUB="$(mktemp -d)"
cat > "$STUB/curl" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STUB/sent.log"
EOF
chmod +x "$STUB/curl"
sent_lines() { if [ -f "$STUB/sent.log" ]; then wc -l < "$STUB/sent.log" | xargs; else echo 0; fi; }
TOK="SECRETTOK123"

# --- RED: notify is OFF by default (no notify block in config) ----------------
PATH="$STUB:$PATH" TELEGRAM_RAILS_BOT_TOKEN="$TOK" TELEGRAM_RAILS_CHAT_ID=42 \
  bash "$NOTIFY" observer_filed "x" >/dev/null 2>&1; rc=$?
_assert "unconfigured notify: exit 0" 0 "$rc"
_assert "unconfigured notify: sends NOTHING" 0 "$(sent_lines)"

# enable notify in the sandbox config (harness plays the human)
python3 - <<'PY'
import json
p = "rails/config.json"; c = json.load(open(p))
c["notify"] = {"enabled": True, "channel": "telegram",
               "events": ["observer_filed", "stamp_invalidated"]}
json.dump(c, open(p, "w"), indent=2)
PY

# --- RED: enabled but token-less = quiet no-op (token-less installs untouched)
PATH="$STUB:$PATH" bash "$NOTIFY" observer_filed "x" >/dev/null 2>&1; rc=$?
_assert "enabled + token-less notify: exit 0" 0 "$rc"
_assert "enabled + token-less notify: sends nothing" 0 "$(sent_lines)"

# --- RED: an event NOT in the events list does not send ------------------------
PATH="$STUB:$PATH" TELEGRAM_RAILS_BOT_TOKEN="$TOK" TELEGRAM_RAILS_CHAT_ID=42 \
  bash "$NOTIFY" dispatch_blocked "x" >/dev/null 2>&1; rc=$?
_assert "event outside the events list: exit 0, not sent" 0 "$rc"
_assert "event outside the events list: sends nothing" 0 "$(sent_lines)"

# --- the fixture observer: 5 candidates, rate limit 3 --------------------------
mkdir -p rails/observers/state
cat > rails/observers/obstest.json <<'EOF'
{
  "name": "obstest",
  "source": "eval fixture",
  "trigger": "fixture candidates present",
  "query_cmd": "",
  "fixture": "rails/observers/state/obstest.fixture.jsonl",
  "dedup_field": "id",
  "rate_limit": 3,
  "env_var": ""
}
EOF
python3 - <<'PY'
import json
with open("rails/observers/state/obstest.fixture.jsonl", "w") as f:
    for n in range(1, 6):
        f.write(json.dumps({"id": "cand-%d" % n, "title": "finding %d" % n,
                            "evidence": "https://example.test/%d" % n,
                            "problem": "problem statement %d" % n,
                            "priority": "P2"}) + "\n")
PY

# create-only, structurally: plant a HUMAN file at the exact filename the
# runner would use for cand-1; the runner must never overwrite it.
H1="$(python3 -c 'import hashlib; print(hashlib.sha256(b"cand-1").hexdigest()[:8])')"
SENTINEL="$INBOX/obs-obstest-$H1.md"
echo "SENTINEL human file" > "$SENTINEL"

obstest_count() { ls "$INBOX" 2>/dev/null | grep -c '^obs-obstest-'; }

# run 1: 5 candidates, dest of cand-1 exists -> 3 NEW files, 1 carried
PATH="$STUB:$PATH" TELEGRAM_RAILS_BOT_TOKEN="$TOK" TELEGRAM_RAILS_CHAT_ID=42 \
  bash "$RUN" obstest --dry-run >/dev/null 2>&1; rc=$?
_assert "run1: exit 0" 0 "$rc"
_assert "run1: rate limit -> 3 new items (4 with the sentinel)" 4 "$(obstest_count)"
_assert "run1: sentinel inbox item NOT overwritten (create-only)" 1 \
  "$(grep -c 'SENTINEL human file' "$SENTINEL")"
_assert "run1: overflow marker carried in state (1 candidate)" 1 \
  "$(python3 -c 'import json; print(len(json.load(open("rails/observers/state/obstest.json")).get("overflow", [])))')"
H2="$(python3 -c 'import hashlib; print(hashlib.sha256(b"cand-2").hexdigest()[:8])')"
ITEM="$INBOX/obs-obstest-$H2.md"
_assert "templated: Source line" 1 "$(grep -c '^- Source: eval fixture' "$ITEM" 2>/dev/null)"
_assert "templated: Trigger line" 1 "$(grep -c '^- Trigger: fixture candidates present' "$ITEM" 2>/dev/null)"
_assert "templated: Evidence reference (link, not payload)" 1 "$(grep -c '^- Evidence: https://example.test/2' "$ITEM" 2>/dev/null)"
_assert "templated: one-line Problem statement" 1 "$(grep -c '^- Problem: problem statement 2' "$ITEM" 2>/dev/null)"
_assert "templated: SUGGESTED-PRIORITY line" 1 "$(grep -c '^- SUGGESTED-PRIORITY: P2' "$ITEM" 2>/dev/null)"
_assert "run1: ONE batched notify message per run" 1 "$(sent_lines)"
_assert "notify line names event + artifact path" 1 \
  "$(grep -c 'observer_filed.*rails/dispatches/inbox' "$STUB/sent.log")"

# run 2: overflow drains (carried, not dropped); already-filed are deduped
PATH="$STUB:$PATH" TELEGRAM_RAILS_BOT_TOKEN="$TOK" TELEGRAM_RAILS_CHAT_ID=42 \
  bash "$RUN" obstest --dry-run >/dev/null 2>&1; rc=$?
_assert "run2: exit 0" 0 "$rc"
_assert "run2: overflow drained -> 5 total" 5 "$(obstest_count)"
_assert "run2: overflow now empty" 0 \
  "$(python3 -c 'import json; print(len(json.load(open("rails/observers/state/obstest.json")).get("overflow", [])))')"
_assert "run2: second batched message" 2 "$(sent_lines)"

# run 3: full dedup -> zero new files, zero new messages
PATH="$STUB:$PATH" TELEGRAM_RAILS_BOT_TOKEN="$TOK" TELEGRAM_RAILS_CHAT_ID=42 \
  bash "$RUN" obstest --dry-run >/dev/null 2>&1; rc=$?
_assert "run3: exit 0" 0 "$rc"
_assert "run3: dedup -> zero new files" 5 "$(obstest_count)"
_assert "run3: nothing filed -> no notify (no spam)" 2 "$(sent_lines)"

# --- secrets never written to any file by any code path ------------------------
_assert "token value appears in NO file under rails/" 0 \
  "$(grep -rl "$TOK" rails 2>/dev/null | wc -l | xargs)"

# --- credential-less SaaS observer: silent-and-logged skip, exit 0 -------------
( unset SENTRY_API_TOKEN 2>/dev/null; bash "$RUN" sentry >/dev/null 2>&1 ); rc=$?
_assert "credential-less sentry: exit 0 (cron never breaks)" 0 "$rc"
_assert "credential-less sentry: zero inbox items" 0 "$(ls "$INBOX" | grep -c '^obs-sentry-')"
_assert "credential-less sentry: skip LOGGED, naming the env var" 1 \
  "$(grep -c 'SENTRY_API_TOKEN' rails/observers/state/sentry.log 2>/dev/null)"

# --- SaaS dry-run works out of the box (shipped fixture, no creds, no network) -
bash "$RUN" sentry --dry-run >/dev/null 2>&1; rc=$?
_assert "sentry --dry-run: exit 0 without credentials" 0 "$rc"
_assert "sentry --dry-run: files from the shipped fixture" 1 \
  "$([ "$(ls "$INBOX" | grep -c '^obs-sentry-')" -ge 1 ] && echo 1 || echo 0)"

# --- drift: the kit watching its own decay (real local query) ------------------
bash "$RUN" drift >/dev/null 2>&1; rc=$?
_assert "drift on a HEALTHY install: exit 0" 0 "$rc"
_assert "drift on a HEALTHY install: files nothing" 0 "$(ls "$INBOX" | grep -c '^obs-drift-')"
mv rails/verifier/baseline.json /tmp/baseline.$$ 2>/dev/null
bash "$RUN" drift >/dev/null 2>&1; rc=$?
_assert "drift on a FAILING install: exit 0" 0 "$rc"
_assert "drift on a FAILING install: files an item" 1 \
  "$([ "$(ls "$INBOX" | grep -c '^obs-drift-')" -ge 1 ] && echo 1 || echo 0)"
mv /tmp/baseline.$$ rails/verifier/baseline.json 2>/dev/null

# --- doctor.sh is the stamp-invalidated notify hook point (NOT verify.sh) ------
_assert "verify.sh never calls notify (the gate stays clean)" 0 \
  "$(grep -c 'notify' rails/verifier/verify.sh)"
echo "# governor drift for case 50" >> rails/verifier/verify.sh
PATH="$STUB:$PATH" TELEGRAM_RAILS_BOT_TOKEN="$TOK" TELEGRAM_RAILS_CHAT_ID=42 \
  bash rails/verifier/doctor.sh >/dev/null 2>&1 || true
_assert "doctor on an invalidated stamp: ONE stamp_invalidated message" 1 \
  "$(grep -c 'stamp_invalidated' "$STUB/sent.log" 2>/dev/null)"

rm -rf "$STUB"
finish
