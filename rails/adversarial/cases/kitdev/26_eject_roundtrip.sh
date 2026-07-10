#!/usr/bin/env bash
# eject round-trip + the registry-expiry seam (Job 9b Part 3):
# install -> eject -> re-install must round-trip to fresh-install + preserved
# history, and preserved trust must EXPIRE when it should. Uses the REAL
# installer (KIT_HOST) against a throwaway repo, so it exercises install<->eject
# symmetry, not a reimplementation.
source "$(dirname "$0")/../../lib.sh"
H="${KIT_HOST:?case 26 needs KIT_HOST (the kit root)}"

T="$(mktemp -d)/repo"; mkdir -p "$T"
( cd "$T" && git init -q && git -c user.email=e@e -c user.name=n commit --allow-empty -qm init )

bash "$H/install.sh" "$T" >/dev/null 2>&1
_assert "install placed the hooks" 1 "$([ -f "$T/.claude/hooks/guard_bash.py" ] && echo 1 || echo 0)"

# stamp a proof (stand-in for run_eval) so a registry exists to preserve
FP1="$(python3 "$H/rails/verifier/fingerprint.py" "$T")"
python3 -c "import json,sys; json.dump({'last_proven_fingerprint':sys.argv[1]}, open(sys.argv[2],'w'))" \
  "$FP1" "$T/rails/adversarial/registry.json"

# eject (preserve history)
bash "$T/rails/verifier/eject.sh" --yes >/dev/null 2>&1
_assert "ejected: hooks gone"                 0 "$([ -e "$T/.claude/hooks/guard_bash.py" ] && echo 1 || echo 0)"
nwired() { if [ -f "$1" ]; then grep -c 'gate_stop.py' "$1" 2>/dev/null; else echo 0; fi; }
_assert "ejected: settings un-wired (file removed or emptied)" 0 "$(nwired "$T/.claude/settings.json")"
_assert "preserved: registry stamp (inert)"   1 "$([ -f "$T/rails/adversarial/registry.json" ] && echo 1 || echo 0)"

# re-install the SAME kit
bash "$H/install.sh" "$T" >/dev/null 2>&1
FP2="$(python3 "$H/rails/verifier/fingerprint.py" "$T")"
STAMP="$(python3 -c "import json;print(json.load(open('$T/rails/adversarial/registry.json'))['last_proven_fingerprint'])")"
_assert "round-trip: hooks restored"                          1 "$([ -f "$T/.claude/hooks/guard_bash.py" ] && echo 1 || echo 0)"
_assert "round-trip: same kit -> fingerprint unchanged"   "$FP1" "$FP2"
_assert "round-trip: preserved stamp still valid (trust legitimately survives)" "$STAMP" "$FP2"

# the seam: a CHANGED governor post-round-trip must NOT keep the old stamp's
# blessing -- the fingerprint diverges, so a fresh run_eval is demanded.
echo "# a governor change after the round-trip" >> "$T/rails/verifier/verify.sh"
FP3="$(python3 "$H/rails/verifier/fingerprint.py" "$T")"
_assert "changed governor post-round-trip -> stamp no longer matches (fresh eval demanded)" \
  1 "$([ "$FP3" != "$STAMP" ] && echo 1 || echo 0)"
rm -rf "$(dirname "$T")"
finish
