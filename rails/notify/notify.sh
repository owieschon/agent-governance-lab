#!/usr/bin/env bash
#
# notify.sh <event> <artifact-path> -- push surfacing (Job 4C). Telegram,
# ONE line per event: repo, event, artifact path. No payloads, no diffs, no
# secrets in messages -- the message points at the artifact; it never
# carries it.
#
# Default OFF: with no "notify" block in rails/config.json, with
# "enabled": false, or with the token env vars unset, this exits 0 and
# sends nothing -- token-less installs are untouched. It also ALWAYS exits
# 0: a notification must never break its caller.
#
# Credentials are ENV VARS ONLY and never written to any file:
#   TELEGRAM_RAILS_BOT_TOKEN  bot token. Use a DEDICATED bot created for
#                             rails notifications; NEVER reuse an existing
#                             bot's token (a rails token that leaks or
#                             rotates must not take an unrelated bot's
#                             traffic down with it).
#   TELEGRAM_RAILS_CHAT_ID    the chat to deliver to.
#
# Callers wired today: run_observer.sh (observer_filed, batched -- one
# message per run) and doctor.sh (stamp_invalidated, on its existing
# fingerprint-vs-stamp check). verify.sh -- the gate -- never calls this by
# design; the config "events" list gates which events send.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVENT="${1:?usage: notify.sh <event> <artifact-path>}"
ARTIFACT="${2:-}"

# enabled AND this event in the configured events list? (read-only probe;
# any miss or parse failure is a quiet no-op)
GO="$(python3 -c 'import json, sys
try:
    n = json.load(open(sys.argv[1])).get("notify") or {}
except Exception:
    n = {}
print("yes" if n.get("enabled") and sys.argv[2] in (n.get("events") or []) else "no")' \
  "$ROOT/rails/config.json" "$EVENT" 2>/dev/null)" || GO="no"
[ "$GO" = "yes" ] || exit 0

TOKEN="${TELEGRAM_RAILS_BOT_TOKEN:-}"
CHAT="${TELEGRAM_RAILS_CHAT_ID:-}"
if [ -z "$TOKEN" ] || [ -z "$CHAT" ]; then
  echo "notify: enabled but TELEGRAM_RAILS_BOT_TOKEN / TELEGRAM_RAILS_CHAT_ID not set -- set them in the environment (never in a file), or set notify.enabled=false" >&2
  exit 0
fi

REPO="$(basename "$ROOT")"
TEXT="[$REPO] $EVENT: $ARTIFACT"
curl -sS -m 10 "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT}" \
  --data-urlencode "text=${TEXT}" >/dev/null 2>&1 \
  || echo "notify: telegram send failed (network or token) for '$TEXT' -- check the env vars and connectivity" >&2
exit 0
