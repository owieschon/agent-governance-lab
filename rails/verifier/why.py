#!/usr/bin/env python3
"""
why.py <verdict.json> <dispatch-id>  -- the expansion behind the one-line
verdict (Job 8 C1).

Renders the LAST verdict for a dispatch in full: every check, its detail, the
tree/commit/fingerprint it was stamped against, and where the evidence lives.
Pure rendering over rails/evidence/<id>/verdict.json -- it computes nothing and
asserts nothing the verifier did not already establish. Read-only.

The verdict-path resolution (single-dispatch auto-select, existence guard)
stays in why.sh, which resolves the path and execs this with it; the body
lives here so it reads and tests on its own. Lives in the trust layer; not
agent-editable.
"""
import json, os, sys

v = json.load(open(sys.argv[1]))
did = sys.argv[2]
print(f"================ {v.get('status','?')} ({did}) ================")
print(f"  verified at:  {v.get('timestamp','?')}")
print(f"  commit:       {v.get('head','?')}")
print(f"  tree hash:    {v.get('tree_hash','?')}")
print(f"  governor:     {str(v.get('governor_fingerprint','(not recorded)'))[:16]}...")
print()
for name, c in (v.get("checks") or {}).items():
    icon = "PASS" if c.get("pass") else "FAIL"
    print(f"  [{icon}] {name}: {c.get('detail','')}")
print()
evid = os.path.dirname(sys.argv[1])
print(f"  evidence files: {evid}/")
for fn in sorted(os.listdir(evid)):
    print(f"    {fn}")
if v.get("status") != "PASS":
    print()
    print(f"  Next: fix the first FAIL above, then re-run bash rails/verifier/verify.sh {did}")
