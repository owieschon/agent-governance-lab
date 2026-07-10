#!/usr/bin/env python3
"""
stats.py -- rejection statistics (rails/evidence/stats.jsonl).

Every time a check rejects work, one JSON line is appended: which check
fired, on which dispatch, at which loop iteration, when, and from which
gate (verify | stop). The file is append-only and lives under
rails/evidence/, which is already outside the tree hash (treehash.py
excludes it) and outside the governor fingerprint -- so recording a
rejection never invalidates a verdict or the governor.

Each line also carries the D23 corpus context (dispatch_type/subsystem
from the manifest -- OPTIONAL keys, empty strings when absent -- plus
tree_hash) and the economics fields input_tokens/output_tokens. The
economics rule (D57, same as review_minutes): null where the harness does
not expose usage -- NEVER estimated, never defaulted. The only way a token
count lands here is a caller passing real usage explicitly.

"iteration" is the count of PRIOR rejecting runs of the same gate for the
same dispatch, plus one: it answers "how many times around the loop did
this dispatch keep failing this gate." All checks rejected in one verify
run share an iteration (they are the same trip around the loop).

CLI:
  python3 stats.py from_verdict <proj> <dispatch> <verdict.json>  # verify gate
  python3 stats.py stop <proj> <dispatch> <check>                 # stop gate
  python3 stats.py summary <proj>                                 # human report

Lives in the trust layer; not agent-editable.
"""
import datetime
import json
import os
import subprocess
import sys


def _path(proj):
    return os.path.join(proj, "rails", "evidence", "stats.jsonl")


def _dispatch_context(proj, dispatch):
    """Optional manifest keys (D23 corpus shape): type, subsystem.
    Deliberately duplicated from adjudicate.py (D57): a cross-import between
    trust-layer files would couple their load paths for ten lines of code.
    Empty strings when a manifest omits the keys -- non-fatal by design."""
    for state in ("active", "archive"):
        p = os.path.join(proj, "rails", "dispatches", state, dispatch, "manifest.json")
        try:
            m = json.load(open(p))
            return str(m.get("type", "") or ""), str(m.get("subsystem", "") or "")
        except Exception:
            continue
    return "", ""


def _tree_hash(proj):
    try:
        r = subprocess.run(
            ["python3", os.path.join(proj, "rails", "verifier", "treehash.py")],
            capture_output=True, text=True, cwd=proj, timeout=30)
        return r.stdout.strip() or "UNKNOWN"
    except Exception:
        return "UNKNOWN"


def _context(proj, dispatch, tree_hash, usage):
    """The shared per-line context block. usage comes only from a caller
    that actually HAS harness-exposed numbers; absent ones stay None --
    null in the line, never a guess (D57)."""
    dtype, subsystem = _dispatch_context(proj, dispatch)
    usage = usage or {}
    return {
        "dispatch_type": dtype,
        "subsystem": subsystem,
        "tree_hash": tree_hash,
        "input_tokens": usage.get("input_tokens"),
        "output_tokens": usage.get("output_tokens"),
    }


def _read(proj):
    rows = []
    try:
        with open(_path(proj)) as f:
            for ln in f:
                ln = ln.strip()
                if ln:
                    try:
                        rows.append(json.loads(ln))
                    except Exception:
                        pass
    except Exception:
        pass
    return rows


def _iteration(proj, source, dispatch):
    """1 + number of prior distinct rejecting runs of this gate for dispatch."""
    stamps = {
        r.get("timestamp")
        for r in _read(proj)
        if r.get("source") == source and r.get("dispatch") == dispatch
    }
    return len(stamps) + 1


def _append(proj, rows):
    os.makedirs(os.path.dirname(_path(proj)), exist_ok=True)
    with open(_path(proj), "a") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")


def from_verdict(proj, dispatch, verdict_path, usage=None):
    try:
        v = json.load(open(verdict_path))
    except Exception:
        return 0
    failed = [k for k, c in (v.get("checks") or {}).items() if not c.get("pass")]
    if not failed:
        return 0
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    it = _iteration(proj, "verify", dispatch)
    # tree_hash comes from the verdict itself: the stat describes THAT run.
    ctx = _context(proj, dispatch, v.get("tree_hash", "UNKNOWN"), usage)
    _append(proj, [
        dict({"source": "verify", "check": k, "dispatch": dispatch,
              "iteration": it, "timestamp": ts}, **ctx)
        for k in failed
    ])
    return len(failed)


def stop(proj, dispatch, check, usage=None):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    it = _iteration(proj, "stop", dispatch)
    ctx = _context(proj, dispatch, _tree_hash(proj), usage)
    _append(proj, [dict({"source": "stop", "check": check, "dispatch": dispatch,
                         "iteration": it, "timestamp": ts}, **ctx)])
    return 1


def summary(proj):
    rows = _read(proj)
    if not rows:
        print("no rejections recorded (rails/evidence/stats.jsonl is empty/absent)")
        return 0
    by_check, by_dispatch = {}, {}
    for r in rows:
        by_check[r.get("check", "?")] = by_check.get(r.get("check", "?"), 0) + 1
        by_dispatch[r.get("dispatch", "?")] = by_dispatch.get(r.get("dispatch", "?"), 0) + 1
    print(f"rejection stats  ({len(rows)} firings)\n")
    print("by check:")
    for k, n in sorted(by_check.items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {k}")
    print("\nby dispatch:")
    for k, n in sorted(by_dispatch.items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {k}")
    return 0


def _main(argv):
    if len(argv) == 5 and argv[1] == "from_verdict":
        return 0 if from_verdict(argv[2], argv[3], argv[4]) >= 0 else 1
    if len(argv) == 5 and argv[1] == "stop":
        stop(argv[2], argv[3], argv[4])
        return 0
    if len(argv) == 3 and argv[1] == "summary":
        return summary(argv[2])
    print("usage: stats.py from_verdict|stop|summary ...", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
