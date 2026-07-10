#!/usr/bin/env python3
"""
snapshot.py <root> <dispatch-id>  -- record test/fixture file hashes at
approval time.

Run when a dispatch is APPROVED. verify.sh's oracle_integrity check compares
the current hashes to this snapshot and FAILs on an undeclared test/fixture
mutation -- the scorer/oracle-tampering defense (the agent leaves the checks
intact and instruments the thing that grades it instead). Writes
rails/dispatches/active/<id>/.oracle_snapshot.json.

The body lives here rather than a bash heredoc so it reads and tests on its
own; snapshot.sh is a thin shim that resolves <root>/<id> and execs this.
Lives in the trust layer; not agent-editable.
"""
import json, sys, os, hashlib, glob
root, did = sys.argv[1], sys.argv[2]
cfg = {}
try:
    cfg = json.load(open(os.path.join(root, "rails", "config.json")))
except Exception:
    pass
globs = [g for g in [cfg.get("test_glob", ""), cfg.get("fixtures_glob", "")] if g]
files = set()
for g in globs:
    base = os.path.join(root, g)
    if os.path.isdir(base):
        for dp, _, fns in os.walk(base):
            if "__pycache__" in dp:
                continue
            for fn in fns:
                if fn.endswith(".pyc"):
                    continue
                files.add(os.path.relpath(os.path.join(dp, fn), root))
    else:
        for p in glob.glob(base, recursive=True):
            if os.path.isfile(p):
                files.add(os.path.relpath(p, root))
snap = {}
for rel in sorted(files):
    try:
        snap[rel] = hashlib.sha256(open(os.path.join(root, rel), "rb").read()).hexdigest()
    except Exception:
        pass
d = os.path.join(root, "rails", "dispatches", "active", did)
os.makedirs(d, exist_ok=True)
out = {"files": snap}
# Freeze the manifest too: the manifest defines the dispatch's proof
# obligations (break plan, live-path greps, declared test changes). Hashing it
# at approval lets verify.sh detect a post-approval rewrite -- the agent cannot
# author its own answer key after the human has signed off (any real amendment
# goes back through re-approval, which re-snapshots).
mp = os.path.join(d, "manifest.json")
if os.path.isfile(mp):
    out["manifest"] = hashlib.sha256(open(mp, "rb").read()).hexdigest()
json.dump(out, open(os.path.join(d, ".oracle_snapshot.json"), "w"), indent=2)
print(f"oracle snapshot: {len(snap)} test/fixture file(s)"
      + (" + manifest" if "manifest" in out else "") + f" hashed for {did}")
