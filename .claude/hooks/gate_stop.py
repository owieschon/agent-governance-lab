#!/usr/bin/env python3
"""
Stop gate: the deterministic loop driver.

While a dispatch is active, the session is not allowed to end unless ONE of:
  1. rails/evidence/<dispatch-id>/verdict.json exists, status == PASS, and its
     tree_hash matches the CURRENT working tree (i.e. nothing changed since
     the verifier last ran). Stale green is not green.
  2. rails/handoff/<dispatch-id>.BLOCKED.md exists: the agent has formally
     declared it is blocked and stated exactly what it needs from the human.

This replaces "trust the model's claim that it's done" with "the exogenous
verifier said PASS against this exact tree." It is the mechanized version of
the framework's definition of done.

Exit 0 = allow the stop. Exit 2 = block the stop; stderr tells the agent
what proof is missing.
"""
import glob
import json
import os
import subprocess
import sys


def block(msg: str):
    print(msg, file=sys.stderr)
    sys.exit(2)


try:
    data = json.load(sys.stdin)
except Exception:
    # Fail OPEN here, deliberately -- the opposite of guard_bash/guard_files,
    # which fail closed. The asymmetry is by blast radius: a PreToolUse guard
    # that fails closed denies one command (safe); a Stop hook that fails closed
    # cannot end the session (a brick). Claude Code, not the agent, supplies this
    # hook's stdin, so a malformed event is a harness/contract problem the agent
    # cannot fix -- trapping it serves no one. Unverified work is still caught:
    # the verifier's PASS and the evidence ledger are unaffected by this path.
    sys.exit(0)

# Required loop-safety: if we already blocked once and the agent is stopping
# again as a result of hook processing, let it through rather than spin.
if data.get("stop_hook_active"):
    sys.exit(0)

proj = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def read_posture():
    # Posture is read ONLY here (the gating layer) and in the ceremony commands
    # -- NEVER in verify.sh or the checks (that would neuter verification, the
    # Part A invariant). It governs GATING LOUDNESS only: in quiet, a missing or
    # failed verdict is REPORTED, not blocked. Missing key -> standard, so a
    # pre-posture install keeps its full gating. The catastrophic FLOOR
    # (guard_bash: no push/force/merge/credentials/irreversible) is posture-
    # INDEPENDENT and is not reachable from here.
    try:
        return json.load(open(os.path.join(proj, "rails", "config.json"))).get("posture", "standard")
    except Exception:
        return "standard"


posture = read_posture()

# L1 default-fitness observation (Job 8 Part B5): one record per session of
# which posture actually ran vs the shipped default. The gating layer is the
# one place posture is already read, so the observation costs nothing new.
# Idempotent per session (adjudicate.observe dedups); best-effort -- a
# recording hiccup never blocks a stop. The stream is a MIRROR the operator
# reads in /status; it is never wired to a gate (D23).
try:
    sys.path.insert(0, os.path.join(proj, "rails", "verifier"))
    import datetime as _dt
    import adjudicate as _adj
    _key = data.get("session_id") or _dt.date.today().isoformat()
    _adj.observe(proj, "posture", posture, "quiet", str(_key))
except Exception:
    pass

# observe mode (D63): at session end, RECORD claim-vs-reality (did the agent
# leave verified work?) and never block. The stop gate is the cleanest place to
# catch "declared done without proof" -- the central go-quietly-wrong signal.
try:
    sys.path.insert(0, os.path.join(proj, "rails", "verifier"))
    import observe as _observe
    OBSERVE = _observe.mode(proj) == "observe"
except Exception:
    _observe = None
    OBSERVE = False

active = sorted(glob.glob(os.path.join(proj, "rails", "dispatches", "active", "*")))
active = [d for d in active if os.path.isdir(d)]
if not active:
    sys.exit(0)


def tree_hash() -> str:
    """Single source of truth lives in rails/verifier/treehash.py."""
    try:
        r = subprocess.run(
            ["python3", os.path.join(proj, "rails", "verifier", "treehash.py")],
            capture_output=True,
            text=True,
            cwd=proj,
            timeout=30,
        )
        return r.stdout.strip()
    except Exception:
        return "UNKNOWN"


now = tree_hash()
stuck = []

def _ledger(*record_args):
    """Best-effort call into the trust-layer incident/stats modules."""
    try:
        sys.path.insert(0, os.path.join(proj, "rails", "verifier"))
        import incident  # noqa: E402
        return incident, __import__("stats")
    except Exception:
        return None, None


for d in active:
    did = os.path.basename(d)
    blocked_path = os.path.join(proj, "rails", "handoff", f"{did}.BLOCKED.md")
    if os.path.exists(blocked_path):
        # A BLOCKED dispatch is a governance event: record it (idempotent) so
        # the failure shape is not silently forgotten.
        inc, _ = _ledger()
        if inc is not None:
            try:
                reason = ""
                with open(blocked_path) as bf:
                    reason = bf.read(500).strip().replace("\n", " ")
            except Exception:
                reason = ""
            try:
                inc.record(
                    proj, did, "blocked", "stop_gate",
                    "agent declared BLOCKED and stopped",
                    reason or f"(see rails/handoff/{did}.BLOCKED.md)",
                    now,
                )
            except Exception:
                pass
        continue  # formally blocked: allowed to stop
    vpath = os.path.join(proj, "rails", "evidence", did, "verdict.json")
    try:
        with open(vpath) as f:
            v = json.load(f)
    except Exception:
        stuck.append((did, "no verifier verdict exists yet"))
        continue
    if v.get("status") != "PASS":
        stuck.append((did, f"last verdict was {v.get('status', 'UNKNOWN')}"))
        continue
    if v.get("tree_hash") != now or now == "UNKNOWN":
        stuck.append(
            (did, "verdict is STALE: the working tree changed after the last verifier run")
        )

if stuck:
    # Rejection stat: the stop gate is firing on these dispatches.
    _, stats = _ledger()
    if stats is not None:
        for did, _why in stuck:
            try:
                stats.stop(proj, did, "stop_gate")
            except Exception:
                pass
    detail = "; ".join(f"{d} ({why})" for d, why in stuck)
    if OBSERVE and _observe is not None:
        # Record the claim-vs-reality and let the session end -- silently, so the
        # worker is not tipped that its "done" was checked (observer effect would
        # corrupt the very behavior we are trying to characterize).
        for did, why in stuck:
            _observe.record(proj, "stop_unverified",
                            f"session ended with unverified work: {why}",
                            dispatch=did, tree_hash=now)
        sys.exit(0)
    if posture == "quiet":
        # Report, do not gate. verify still ran, evidence + the incident ledger
        # are intact; only the session-end block is relaxed. The verdict and
        # history remain fully adjudicable, so upgrading posture later changes
        # nothing about what was already verified.
        print("STOP NOTE (quiet posture -- reporting, not gating): an active "
              "dispatch lacks fresh proof: " + detail
              + ". Run rails/verifier/verify.sh to see the verdict.",
              file=sys.stderr)
        sys.exit(0)
    block(
        "STOP GATE: an active dispatch lacks fresh proof: "
        + detail
        + ".\n"
        "Done means all three: full suite ran to completion, live-path grep "
        "proved, demonstrated-red shown. Anything short of that is a claim, "
        "not a proof.\n"
        f"Run: bash rails/verifier/verify.sh {stuck[0][0]}\n"
        "Fix whatever fails and re-run until PASS, then produce the handoff "
        "(/handoff). If you are genuinely blocked (a boundary event, a missing "
        "human decision, a broken environment), write "
        "rails/handoff/<dispatch-id>.BLOCKED.md stating exactly what you need "
        "from the human, then stop."
    )

sys.exit(0)
