#!/usr/bin/env bash
#
# eject.sh [--purge-history] [--yes] -- remove the 3xit2 trust layer.
#
# The complement of install: a tool you cannot cleanly leave is one you cannot
# safely adopt.
#
# Symmetry with install.sh: eject removes EXACTLY what install OVERWRITES (the
# `place` set -- the canonical trust layer), and PRESERVES EXACTLY what install
# keeps via copy_if_absent (the per-repo adapter + history). So
# install-after-eject round-trips to fresh-install + preserved history.
#   REMOVED:   hooks, verifier trust scripts, eval harness + core cases,
#              rails commands, agents/reviewer.md, postures/,
#              docs/OPERATING.md, the CLAUDE.md rails block,
#              and the rails hook entries in .claude/settings.json (surgical --
#              any other hooks you added are left intact).
#   PRESERVED (default): config.json, baseline.json, load_bearing.txt,
#              registry.json, DEPARTURES.md, cases/project/, and all per-repo
#              history (dispatches, evidence, handoff, incidents, GOVERNOR_LOG).
#   --purge-history ALSO removes the preserved set (a full teardown).
#
# Preserved history is left INERT: with the verifier gone nothing reads it, so a
# post-eject repo behaves like a never-installed one. If you re-install, the
# fingerprint gate decides whether a preserved eval stamp still counts: an
# UNCHANGED governor keeps its proof; a CHANGED one demands a fresh eval.
#
# Agent-inert: the loop can NEVER run this -- guard_bash blocks it. Ejecting the
# trust layer is the ultimate self-protection breach; it is a human act only.
# Lives in the trust layer; not agent-editable.
#
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PURGE=0; YES=0
for a in "$@"; do
  case "$a" in
    --purge-history) PURGE=1 ;;
    --yes) YES=1 ;;
    *) echo "usage: eject.sh [--purge-history] [--yes]" >&2; exit 2 ;;
  esac
done
cd "$ROOT"
say() { printf '%s\n' "$*"; }

REMOVED=(); KEPT=()
rm_path() { if [ -e "$1" ]; then rm -rf "$1"; REMOVED+=("$1"); fi; }
keep_note() { [ -e "$1" ] && KEPT+=("$1"); }

# what install OVERWRITES (the place set) -> remove
HOOKS="guard_bash.py guard_files.py gate_stop.py"
CMDS="dispatch.md go.md verify.md handoff.md status.md why.md receipt.md rails-demo.md rails-init.md"
VERIF_SCRIPTS="verify.sh remote_ref.sh treehash.py fingerprint.py demonstrated_red.py \
incident.py stats.py stats.sh doctor.sh scoreboard.sh scoreboard.py scoreboard_metrics.sql status.sh status.py \
snapshot.sh snapshot.py basis.sh oracle_independence.py exercised_assertions.py \
adjudicate.py why.sh why.py receipt.sh receipt.py nextstep_lint.py demo.sh init.sh freshness.py eject.sh \
flaky_triage.py \
review.sh handoff_review.sh render_review_summary.py pre-push.sh"
ADV_HARNESS="run_eval.sh fixture.sh lib.sh accrete.sh case_template.sh"
OBSERVERS="run_observer.sh run_observer.py extract.py sentry.json phoenix.json langsmith.json \
posthog.json ci.json deps.json drift.json"

if [ "$YES" -ne 1 ]; then
  say "This removes the 3xit2 trust layer from $ROOT."
  [ "$PURGE" -eq 1 ] && say "--purge-history: per-repo history (dispatches/evidence/incidents/GOVERNOR_LOG) will ALSO be removed."
  say "Per-repo config and history are preserved by default. Re-run with --yes to proceed."
  exit 1
fi

for f in $HOOKS;         do rm_path ".claude/hooks/$f"; done
for f in $CMDS;          do rm_path ".claude/commands/$f"; done
for f in $VERIF_SCRIPTS; do rm_path "rails/verifier/$f"; done
for f in $ADV_HARNESS;   do rm_path "rails/adversarial/$f"; done
[ -d rails/adversarial/cases/core ] && { rm -rf rails/adversarial/cases/core; REMOVED+=("rails/adversarial/cases/core/"); }
# pre-push hook (structural push gate installed into .git/hooks/)
if [ -f .git/hooks/pre-push ] && grep -q "3xit2" .git/hooks/pre-push 2>/dev/null; then
  rm -f .git/hooks/pre-push; REMOVED+=(".git/hooks/pre-push (structural push gate)")
fi
rm_path "docs/OPERATING.md"
rm_path ".claude/skills/rails"
# role kernel: postures + reviewer agent definition
rm_path "rails/verifier/postures"
rm_path ".claude/agents/reviewer.md"
# observers (Job 4): definitions/runner/transforms/fixtures + notify are the
# install place set -> removed; per-repo observer STATE is history -> preserved
for f in $OBSERVERS;     do rm_path "rails/observers/$f"; done
rm_path "rails/observers/fixtures"
rm_path "rails/observers/.gitkeep"
rm_path "rails/notify"

# CLAUDE.md: remove the rails block between its markers (leave the rest)
if [ -f CLAUDE.md ] && grep -q "3XIT2 BEGIN" CLAUDE.md; then
  python3 - <<'PY'
import re
t = open("CLAUDE.md").read()
new = re.sub(r"\n?<!-- 3XIT2 BEGIN.*?3XIT2 END -->\n?", "\n", t, flags=re.S)
open("CLAUDE.md", "w").write(new)
PY
  REMOVED+=("CLAUDE.md (rails block)")
fi

# settings.json: SURGICAL -- drop only hook entries that invoke a rails hook;
# keep every other hook and key the user added. Prune emptied arrays/objects.
if [ -f .claude/settings.json ]; then
  _S_RESULT="$(python3 - <<'PY'
import json
p = ".claude/settings.json"
try:
    s = json.load(open(p))
except Exception:
    raise SystemExit
RAILS = ("guard_bash.py", "guard_files.py", "gate_stop.py")
def is_rails(h):
    return any(r in json.dumps(h.get("hooks", h)) for r in RAILS)
hooks = s.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks):
        entries = [e for e in hooks[event] if not is_rails(e)]
        if entries:
            hooks[event] = entries
        else:
            del hooks[event]
    if not hooks:
        del s["hooks"]
# If nothing remains, the file was purely ours: remove it so a re-install
# restores it cleanly (install never clobbers an existing settings.json).
# If the user has other settings, keep the file (their config stays); a
# re-install then correctly offers settings.rails.json for a manual merge.
import os
if not s:
    os.remove(p)
    print("REMOVED_FILE")
else:
    json.dump(s, open(p, "w"), indent=2)
    print("EDITED")
PY
)"
  case "$_S_RESULT" in
    *REMOVED_FILE*) REMOVED+=(".claude/settings.json (was purely rails; removed)");;
    *)              REMOVED+=(".claude/settings.json (rails hook entries; other settings kept)");;
  esac
fi

# preserved per-repo set (history + adapter). --purge-history removes it too.
PRESERVE="rails/verifier/config.json rails/config.json rails/verifier/baseline.json \
rails/verifier/load_bearing.txt rails/adversarial/registry.json \
rails/adversarial/DEPARTURES.md rails/adversarial/cases/project \
rails/dispatches rails/evidence rails/handoff rails/incidents GOVERNOR_LOG.md \
rails/verifier/flaky_lane.json rails/observers/state"
if [ "$PURGE" -eq 1 ]; then
  for f in $PRESERVE; do rm_path "$f"; done
  # if rails/ is now empty of everything but stubs, leave the dir; harmless.
else
  for f in $PRESERVE; do keep_note "$f"; done
fi

say "ejected 3xit2 from $ROOT."
say ""
say "removed (${#REMOVED[@]}):"
for r in "${REMOVED[@]}"; do say "  - $r"; done
if [ "$PURGE" -eq 1 ]; then
  say ""
  say "per-repo history was PURGED (--purge-history)."
else
  say ""
  say "preserved (${#KEPT[@]}) -- per-repo config + history, now inert:"
  for k in "${KEPT[@]}"; do say "  keep $k"; done
  say ""
  say "Re-install (install.sh) restores the trust layer; a preserved eval stamp"
  say "stays valid only if the governor fingerprint is unchanged, else a fresh"
  say "run_eval.sh is required. To remove the preserved history too: eject.sh --purge-history --yes"
fi
