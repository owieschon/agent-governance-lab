#!/usr/bin/env python3
"""observe.py -- behavioral recorder for OBSERVE mode (D63).

The trust layer has two stances, set by `mode` in rails/config.json:

  enforce (default)  guards BLOCK at every boundary (the gating layer).
  observe            guards RECORD what they would have blocked and ALLOW it
                     -- EXCEPT a catastrophic floor that always blocks. The
                     behavior is the dataset: you cannot improve what you never
                     get to see, and halting-first means you never observe the
                     failure you were trying to prevent.

What still blocks in observe mode (the floor): the irreversible / outbound /
apparatus actions -- push, force, history-rewrite, hard-reset, credentials,
migrations, work-destroying HEAD moves, eject, baseline-shrink, and any write to
the trust layer's OWN apparatus (hooks, settings, verifier, eval). You cannot
observe-and-recover from those, and you cannot watch the agent if it can disable
the camera.

Observations append to rails/observations.jsonl -- OUTSIDE the governor
fingerprint, so recording never invalidates a verdict. Append-only; best-effort
(a recording hiccup must never break the tool call it is watching).
"""
import datetime
import json
import os
import sys

# The apparatus: editing any of these blinds or disables the trust layer itself,
# so it stays floor-blocked even in observe mode. (Governed CONTENT -- the
# agent's own tests/oracle, evidence, config, inbox -- is observable, not
# apparatus: watching the agent touch those is the point.)
APPARATUS_PREFIXES = ("rails/verifier", ".claude/hooks", "rails/adversarial")
APPARATUS_FILES = (".claude/settings.json", ".claude/settings.local.json")


def is_apparatus(rel: str) -> bool:
    rel = rel.replace(os.sep, "/")
    if rel.startswith("./"):           # strip a leading "./" ONLY -- never the
        rel = rel[2:]                  # leading dot of ".claude" (lstrip would)
    if rel in APPARATUS_FILES:
        return True
    return any(rel == p or rel.startswith(p + "/") for p in APPARATUS_PREFIXES)


def mode(proj: str) -> str:
    # Read the active mode from an agent-INVISIBLE location first
    # (.git/3xit2/mode). observe mode must not announce itself in config.json --
    # the agent reads config, and in observe mode the guard would even ALLOW
    # that read, so a mode flag there leaks the very fact it is observed (caught
    # in the first observe run: the agent saw "mode: observe" and said so). The
    # signal lives under .git/, which the worker does not browse and which never
    # enters the work tree or a push. Fall back to config, then enforce.
    try:
        p = os.path.join(proj, ".git", "3xit2", "mode")
        if os.path.isfile(p):
            v = open(p).read().strip()
            if v:
                return v
    except Exception:
        pass
    try:
        with open(os.path.join(proj, "rails", "config.json")) as f:
            return str(json.load(f).get("mode", "enforce"))
    except Exception:
        return "enforce"


def log_path(proj: str) -> str:
    """Where observations land. Inside .git/ when present -- the worker does not
    browse git internals, and the file never enters the work tree, git status, or
    a push, so it stays out of sight (unobtrusive observation: an agent that
    knows it is watched does not behave like one that does not). Falls back to a
    dot-file under rails/ for non-git repos."""
    gitdir = os.path.join(proj, ".git")
    if os.path.isdir(gitdir):
        d = os.path.join(gitdir, "3xit2")
        try:
            os.makedirs(d, exist_ok=True)
            return os.path.join(d, "observations.jsonl")
        except Exception:
            pass
    return os.path.join(proj, "rails", ".observations.jsonl")


def record(proj: str, kind: str, message: str, **ctx) -> None:
    """Append one observation. kind is a short class (bash_boundary,
    file_write, stop_unverified, ...); message is the boundary that was crossed;
    ctx carries the specifics (command, path, dispatch, verdict, tree_hash)."""
    rec = {
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "mode": "observe",
        "kind": kind,
        "message": message,
        "actor": os.environ.get("CLAUDE_AGENT_NAME", "worker"),
    }
    rec.update({k: v for k, v in ctx.items() if v is not None})
    try:
        with open(log_path(proj), "a") as f:
            f.write(json.dumps(rec) + "\n")
    except Exception:
        pass  # an observation must never break what it observes


if __name__ == "__main__":
    # Tiny CLI for rendering the log (used by status/why and by humans).
    proj = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()
    path = log_path(proj)
    if not os.path.exists(path):
        print("no observations recorded (rails/observations.jsonl is empty/absent)")
        sys.exit(0)
    rows = [json.loads(l) for l in open(path) if l.strip()]
    print(f"observations: {len(rows)}\n")
    for r in rows:
        print(f"  {r.get('ts','')[:19]}  {r.get('kind',''):18} {r.get('message','')[:90]}")
