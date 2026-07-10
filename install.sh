#!/usr/bin/env bash
#
# install.sh [--update] /path/to/target/repo
#
# Default (install): copies the rails kit into a repo, never clobbering --
# existing files are kept; an existing .claude/settings.json gets a
# settings.rails.json to merge; an existing CLAUDE.md gets the rails block
# appended between markers (once).
#
# --update: propagate a NEW kit revision into an already-installed repo.
# OVERWRITES the trust layer (hooks, verifier scripts, eval harness, core
# cases, commands, OPERATING.md) to kit-canonical, while PRESERVING every
# per-repo file: config.json (new keys merged in, existing values kept),
# baseline.json, load_bearing.txt, registry.json, DEPARTURES.md, project
# cases, and all of dispatches/evidence/handoff/incidents. CLAUDE.md's rails
# block is re-synced between its markers. The fingerprint changes, so re-run
# the eval afterward to re-stamp.
set -euo pipefail

MODE="install"
ARGS=()
for a in "$@"; do
  case "$a" in
    --update) MODE="update" ;;
    *) ARGS+=("$a") ;;
  esac
done
TARGET="${ARGS[0]:?usage: install.sh [--update] /path/to/target/repo}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -d "$TARGET/.git" ] || { echo "warning: $TARGET is not a git repo (continuing)"; }

mkdir -p "$TARGET/.claude/hooks" "$TARGET/.claude/commands" \
         "$TARGET/.claude/agents" \
         "$TARGET/rails/verifier" "$TARGET/rails/verifier/postures" \
         "$TARGET/rails/dispatches/inbox" "$TARGET/rails/dispatches/active" \
         "$TARGET/rails/dispatches/archive" "$TARGET/rails/evidence" \
         "$TARGET/rails/handoff" "$TARGET/rails/incidents" "$TARGET/docs" \
         "$TARGET/rails/observers/state" "$TARGET/rails/observers/fixtures" \
         "$TARGET/rails/notify"

copy_if_absent() {  # keep target if it exists (preserve per-repo / first install)
  if [ -e "$2" ]; then echo "  keep   $2 (exists)"; else cp "$1" "$2"; echo "  add    $2"; fi
}

place() {  # trust-layer file: overwrite on --update, keep-if-absent on install
  if [ "$MODE" = "update" ]; then
    if [ -e "$2" ] && cmp -s "$1" "$2"; then echo "  same   $2";
    else cp "$1" "$2"; echo "  sync   $2"; fi
  else
    copy_if_absent "$1" "$2"
  fi
}

echo "${MODE}ing 3xit2 into $TARGET"

# hooks + commands (trust layer)
for f in guard_bash.py guard_files.py gate_stop.py; do
  place "$SRC/.claude/hooks/$f" "$TARGET/.claude/hooks/$f"
done
for f in dispatch.md go.md verify.md handoff.md status.md why.md receipt.md rails-demo.md rails-init.md; do
  place "$SRC/.claude/commands/$f" "$TARGET/.claude/commands/$f"
done

# reviewer agent definition (native CC subagent -- deference rider: if the
# user already has a reviewer-shaped subagent, keep theirs and offer the
# posture guards around it rather than installing a competitor)
if [ -f "$SRC/.claude/agents/reviewer.md" ]; then
  copy_if_absent "$SRC/.claude/agents/reviewer.md" "$TARGET/.claude/agents/reviewer.md"
fi

# /rails skill (orientation; not in the fingerprint set)
mkdir -p "$TARGET/.claude/skills/rails"
place "$SRC/.claude/skills/rails/SKILL.md" "$TARGET/.claude/skills/rails/SKILL.md"

# settings: never clobber a live settings.json; always offer the latest for merge
if [ -e "$TARGET/.claude/settings.json" ]; then
  cp "$SRC/.claude/settings.json" "$TARGET/.claude/settings.rails.json"
  echo "  NOTE   .claude/settings.json exists; wrote settings.rails.json -- merge the hooks block manually"
else
  cp "$SRC/.claude/settings.json" "$TARGET/.claude/settings.json"
  echo "  add    .claude/settings.json"
fi

# verifier: trust-layer SCRIPTS overwrite on update; the per-repo baseline and
# load-bearing list are always preserved.
for f in verify.sh remote_ref.sh treehash.py fingerprint.py demonstrated_red.py \
         incident.py stats.py stats.sh doctor.sh scoreboard.sh scoreboard.py scoreboard_metrics.sql status.sh status.py \
         snapshot.sh snapshot.py basis.sh observe.py \
         oracle_independence.py exercised_assertions.py adjudicate.py \
         why.sh why.py receipt.sh receipt.py nextstep_lint.py demo.sh init.sh \
         eject.sh freshness.py flaky_triage.sh flaky_triage.py \
         review.sh handoff_review.sh render_review_summary.py pre-push.sh; do
  place "$SRC/rails/verifier/$f" "$TARGET/rails/verifier/$f"
done
for f in load_bearing.txt baseline.json flaky_lane.json; do
  copy_if_absent "$SRC/rails/verifier/$f" "$TARGET/rails/verifier/$f"   # per-repo: preserve
done

# posture files (role kernel): trust-layer, overwrite on update
for f in "$SRC"/rails/verifier/postures/*.json; do
  [ -f "$f" ] && place "$f" "$TARGET/rails/verifier/postures/$(basename "$f")"
done

# observers (Job 4): runner + transforms + definitions are governor-adjacent
# (agent-read-only, D59) -> place (overwrite on update). Per-repo observer
# STATE (dedup memory, logs) is never touched; it ships git-ignored.
for f in run_observer.sh run_observer.py extract.py sentry.json phoenix.json langsmith.json \
         posthog.json ci.json deps.json drift.json; do
  place "$SRC/rails/observers/$f" "$TARGET/rails/observers/$f"
done
for f in "$SRC"/rails/observers/fixtures/*.jsonl; do
  [ -f "$f" ] && place "$f" "$TARGET/rails/observers/fixtures/$(basename "$f")"
done
copy_if_absent "$SRC/rails/observers/state/.gitignore" "$TARGET/rails/observers/state/.gitignore"
touch "$TARGET/rails/observers/state/.gitkeep"
chmod +x "$TARGET/rails/observers/run_observer.sh" "$TARGET/rails/observers/extract.py"

# notify (Job 4C): push surfacing, default OFF in config.json
place "$SRC/rails/notify/notify.sh" "$TARGET/rails/notify/notify.sh"
chmod +x "$TARGET/rails/notify/notify.sh"

# config.json: install copies the template; update MERGES new keys (e.g. scope)
# without touching existing per-repo values (test_cmd, count_regex, ...).
if [ "$MODE" = "update" ] && [ -e "$TARGET/rails/config.json" ]; then
  python3 - "$SRC/rails/config.json" "$TARGET/rails/config.json" <<'PY'
import json, sys
src = json.load(open(sys.argv[1]))
try:
    dst = json.load(open(sys.argv[2]))
except Exception:
    dst = {}
added = [k for k in src if k not in dst]
for k in added:
    dst[k] = src[k]
json.dump(dst, open(sys.argv[2], "w"), indent=2)
print("  merge  rails/config.json (added: " + (", ".join(added) if added else "none") + ")")
PY
else
  copy_if_absent "$SRC/rails/config.json" "$TARGET/rails/config.json"
fi
copy_if_absent "$SRC/rails/dispatches/TEMPLATE.md" "$TARGET/rails/dispatches/TEMPLATE.md"
for d in dispatches/inbox dispatches/active dispatches/archive evidence handoff incidents; do
  touch "$TARGET/rails/$d/.gitkeep"
done
place "$SRC/docs/OPERATING.md" "$TARGET/docs/OPERATING.md"
copy_if_absent "$SRC/GOVERNOR_LOG.md" "$TARGET/GOVERNOR_LOG.md"  # append-only, per-repo

# adversarial eval: harness + CORE + KITDEV cases overwrite on update;
# DEPARTURES.md (per-repo departures) and cases/project/ are preserved.
# kitdev cases (installer/eject tooling) ship so a target can NAME them as
# N/A in run_eval -- reported, never silently dropped; they never run in a
# target (no install.sh there) and never gate its governor proof.
mkdir -p "$TARGET/rails/adversarial/cases/core" \
         "$TARGET/rails/adversarial/cases/project" \
         "$TARGET/rails/adversarial/cases/kitdev"
for f in run_eval.sh fixture.sh lib.sh accrete.sh case_template.sh; do
  place "$SRC/rails/adversarial/$f" "$TARGET/rails/adversarial/$f"
done
copy_if_absent "$SRC/rails/adversarial/DEPARTURES.md" "$TARGET/rails/adversarial/DEPARTURES.md"
for f in "$SRC"/rails/adversarial/cases/core/*.sh; do
  place "$f" "$TARGET/rails/adversarial/cases/core/$(basename "$f")"
done
for f in "$SRC"/rails/adversarial/cases/kitdev/*.sh; do
  [ -e "$f" ] || continue
  place "$f" "$TARGET/rails/adversarial/cases/kitdev/$(basename "$f")"
done
# Prune: core + kitdev are kit-canonical (fully overwritten), so a case the
# kit no longer ships (e.g. recategorized core -> kitdev) must not linger in
# the target and silently re-fail. project/ is per-repo and never pruned.
for scope in core kitdev; do
  for f in "$TARGET"/rails/adversarial/cases/$scope/*.sh; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    if [ ! -e "$SRC/rails/adversarial/cases/$scope/$base" ]; then
      echo "  prune  rails/adversarial/cases/$scope/$base (no longer shipped by the kit)"
      rm -f "$f"
    fi
  done
done
chmod +x "$TARGET/rails/adversarial/"*.sh "$TARGET/rails/adversarial/cases/core/"*.sh
[ -n "$(ls "$TARGET"/rails/adversarial/cases/kitdev/*.sh 2>/dev/null)" ] && \
  chmod +x "$TARGET/rails/adversarial/cases/kitdev/"*.sh

# CLAUDE.md: install appends the block once; update re-syncs it between markers.
if [ -e "$TARGET/CLAUDE.md" ] && grep -q "3XIT2 BEGIN" "$TARGET/CLAUDE.md"; then
  if [ "$MODE" = "update" ]; then
    python3 - "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md" <<'PY'
import re, sys
block = open(sys.argv[1]).read().strip()
p = sys.argv[2]; txt = open(p).read()
new = re.sub(r"<!-- 3XIT2 BEGIN.*?3XIT2 END -->",
             lambda m: block, txt, flags=re.S)
open(p, "w").write(new)
print("  sync   CLAUDE.md (rails block re-synced between markers)")
PY
  else
    echo "  keep   CLAUDE.md (rails block already present)"
  fi
elif [ -e "$TARGET/CLAUDE.md" ]; then
  { echo ""; cat "$SRC/CLAUDE.md"; } >> "$TARGET/CLAUDE.md"
  echo "  append CLAUDE.md (rails block)"
else
  cp "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md"
  echo "  add    CLAUDE.md"
fi

chmod +x "$TARGET/rails/verifier/"*.sh "$TARGET/rails/verifier/treehash.py" "$TARGET/.claude/hooks/"*.py

# ---- pre-push hook: structural push gate (fires at git layer) ----
# If a .git directory exists and no pre-push hook is present, install ours.
# If a pre-push hook already exists, warn but do not clobber (the user may
# have their own). On --update, always overwrite with the latest.
if [ -d "$TARGET/.git/hooks" ]; then
  if [ "$MODE" = "update" ]; then
    cp "$SRC/rails/verifier/pre-push.sh" "$TARGET/.git/hooks/pre-push"
    chmod +x "$TARGET/.git/hooks/pre-push"
    echo "  sync   .git/hooks/pre-push (structural push gate)"
  elif [ ! -f "$TARGET/.git/hooks/pre-push" ]; then
    cp "$SRC/rails/verifier/pre-push.sh" "$TARGET/.git/hooks/pre-push"
    chmod +x "$TARGET/.git/hooks/pre-push"
    echo "  add    .git/hooks/pre-push (structural push gate)"
  else
    echo "  keep   .git/hooks/pre-push (exists; verify it blocks without ALICE_PUSH_OK=1)"
  fi
fi

if [ "$MODE" = "update" ]; then
cat <<'NEXT'

updated. next steps:
  1. review the synced trust layer in git (it overwrote hooks/verifier/eval).
  2. RE-PROVE THE GOVERNOR (fingerprint changed):
       bash rails/adversarial/run_eval.sh
  3. if the suite or count changed, re-seed the baseline from a known-good run.
NEXT
else
cat <<'NEXT'

next steps:
  1. edit rails/config.json  (scope, test_cmd, count_regex, collect_cmd, main_branch)
  2. seed the baseline from a known-good run:
       bash rails/verifier/verify.sh BOOTSTRAP --update-baseline
  3. PROVE THE GOVERNOR: bash rails/adversarial/run_eval.sh
     (verify.sh refuses to certify any dispatch until this has passed;
      re-run it after any human edit to the trust layer)
  4. restart Claude Code in the repo (picks up .claude/settings.json),
     accept the workspace trust dialog
  5. drop specs into rails/dispatches/inbox/ and run /dispatch
NEXT
fi
