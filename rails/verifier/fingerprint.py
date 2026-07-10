#!/usr/bin/env python3
"""
Prints a fingerprint of the governor: every file whose change could alter
what the checks catch. verify.sh refuses to gate work if this fingerprint
does not match the one stamped by the last full adversarial-eval pass
(spec section 4: a framework change runs the eval BEFORE it takes force).

Covered: rails/verifier/**, .claude/hooks/**, .claude/settings.json,
rails/adversarial/** (excluding registry.json, which is the stamp itself).
Deliberately NOT covered: rails/config.json (per-repo adapter; the eval
proves mechanisms in its own sandbox, so adapter changes do not invalidate
the mechanism proof).

Lives in the trust layer; not agent-editable.
"""
import hashlib
import os
import sys

root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
if len(sys.argv) > 1:
    root = sys.argv[1]

targets = ["rails/verifier", ".claude/hooks", "rails/adversarial"]
single_files = [".claude/settings.json"]
# registry.json is the stamp itself (its presence must not change the very
# fingerprint it records).
EXCLUDE_NAMES = {"registry.json", "__pycache__"}

entries = []
for t in targets:
    base = os.path.join(root, t)
    if not os.path.isdir(base):
        continue
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_NAMES]
        for fn in sorted(filenames):
            if fn in EXCLUDE_NAMES or fn.endswith(".pyc"):
                continue
            p = os.path.join(dirpath, fn)
            entries.append(os.path.relpath(p, root))
for f in single_files:
    if os.path.isfile(os.path.join(root, f)):
        entries.append(f)

# --untracked: list fingerprint-scope files git does not track. The walk above
# hashes the FILESYSTEM, so an untracked file silently joins the fingerprint a
# stamp blesses -- content no reviewer ever saw in a diff (the 2026-06-10
# process-gap incident). This mode makes that inclusion visible; run_eval
# prints it at stamp time and doctor.sh warns on it.
if "--untracked" in sys.argv:
    import subprocess
    try:
        r = subprocess.run(["git", "-C", root, "ls-files"],
                           capture_output=True, text=True, timeout=10)
        tracked = set(r.stdout.splitlines()) if r.returncode == 0 else None
    except Exception:
        tracked = None
    if tracked is not None:
        for rel in sorted(set(entries)):
            if rel not in tracked:
                print(rel)
    sys.exit(0)

h = hashlib.sha256()
for rel in sorted(set(entries)):
    h.update(rel.encode())
    try:
        with open(os.path.join(root, rel), "rb") as fh:
            h.update(fh.read())
    except Exception:
        h.update(b"?")

sys.stdout.write(h.hexdigest())
