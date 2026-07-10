#!/usr/bin/env python3
"""
Prints a hash of the project work-tree state: HEAD + staged + unstaged + every
untracked file's NAME AND CONTENT. The verifier stamps its verdict with this;
the stop gate recomputes it. If they differ, the green is stale and the work
that was proven is no longer the work on disk.

Single source of truth for freshness. Lives in the trust layer; not
agent-editable.
"""
import hashlib
import os
import subprocess
import sys


def out(args):
    try:
        r = subprocess.run(["git"] + args, capture_output=True, text=True, timeout=30)
        return r.stdout
    except Exception:
        return "?"


# Exclude the whole trust layer (rails/) from the freshness hash. rails/ is the
# kit, not the work being verified: it is agent-read-only (the guards), and its
# integrity is covered by the fingerprint (governor_proven) and the manifest /
# oracle freeze -- freshness does not need to watch it. Crucially, the kit's own
# state under rails/ (evidence, the incident + adjudication ledgers, the
# registry stamp, dispatch snapshots) CHURNS as the verifier and stop gate run,
# so including it made a fresh verdict recompute differently than it was stamped
# and read as stale. Freshness watches the project. (rails/evidence exclusion
# generalized; found by adversarial cases 08 and 54.)
EXC = ":(exclude)rails"
root = (out(["rev-parse", "--show-toplevel"]) or "").strip() or "."

h = hashlib.sha256()
for args in (
    ["rev-parse", "HEAD"],
    ["diff", "--", ".", EXC],
    ["diff", "--cached", "--", ".", EXC],
):
    h.update(out(args).encode("utf-8", "replace"))

# Untracked files: hash NAME *and* CONTENT. Hashing names alone let an agent get
# a PASS with an untracked file present, then swap its content for arbitrary
# code without busting the stamp -- the stale PASS would stand against code that
# changed (V6). Sorted for a deterministic hash.
untracked = out(["ls-files", "--others", "--exclude-standard", "--", ".", EXC])
for rel in sorted(filter(None, (ln.strip() for ln in untracked.splitlines()))):
    h.update(("U:" + rel).encode("utf-8", "replace"))
    try:
        with open(os.path.join(root, rel), "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
    except Exception:
        h.update(b"<unreadable>")

sys.stdout.write(h.hexdigest())
