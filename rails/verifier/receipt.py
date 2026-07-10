#!/usr/bin/env python3
"""
receipt.py <root> <dispatch-id> <verdict.json> <out.md>  -- render the
shareable receipt (Job 8 Part C3).

A receipt is RENDERING over existing verified data: the claim, the plain
summary, the catch count, the decisions, and a PROVENANCE line (commit,
governor fingerprint, a content hash of the actual evidence files, and the
pointer back to the run). It computes and asserts NOTHING the verifier did not
already establish -- a receipt is a view of evidence, never a new source of it.
It renders only a PASS; there is no receipt for unverified work. Deterministic:
every field comes from the evidence on disk (the timestamp is the verdict's,
not the render clock), so re-rendering an unchanged run yields a byte-identical
receipt and the provenance still resolves.

The argument resolution (locating the verdict, ensuring the handoff dir) stays
in receipt.sh, which execs this; the body lives here so it reads and tests on
its own. Lives in the trust layer; not agent-editable.
"""
import hashlib, json, os, re, sys

root, did, vpath, out = sys.argv[1:5]
v = json.load(open(vpath))

if v.get("status") != "PASS":
    print(f"no receipt: the last verdict for {did} was "
          f"{v.get('status','?')}. Receipts render verified work only -- "
          f"run bash rails/verifier/verify.sh {did} to PASS first.",
          file=sys.stderr)
    sys.exit(1)


def read(p):
    try:
        return open(p, errors="replace").read()
    except Exception:
        return ""


def dispatch_file(name):
    for state in ("active", "archive"):
        p = os.path.join(root, "rails", "dispatches", state, did, name)
        if os.path.isfile(p):
            return p
    return None

# type/subsystem: the manifest's optional segmentation axes (D23/D57) --
# VIEW only; the receipt renders them, it never computes or asserts anything.
dtype = subsystem = ""
mp = dispatch_file("manifest.json")
if mp:
    try:
        _m = json.loads(read(mp))
        dtype = str(_m.get("type", "") or "")
        subsystem = str(_m.get("subsystem", "") or "")
    except Exception:
        pass

# claim: the dispatch's own title line
claim = f"(no dispatch.md found for {did})"
dp = dispatch_file("dispatch.md")
if dp:
    for ln in read(dp).splitlines():
        ln = ln.strip()
        if ln:
            claim = ln.lstrip("# ").strip()
            break

# plain summary: the handoff's lead (its no-jargon contract section)
summary = ("(no handoff written yet -- the plain-language summary lives "
           "there; run /handoff to produce it)")
htxt = read(os.path.join(root, "rails", "handoff", f"{did}.md"))
if htxt:
    m = re.search(r"\*\*Summary\*\*[ \t]*-*[ \t]*\n?(.*?)(?=\n\s*\d+\.\s*\*\*|\Z)",
                  htxt, re.S)
    if m:
        summary = " ".join(m.group(1).split())

# catches: true_catch adjudications for this dispatch (human-adjudicated)
catches = []
try:
    for ln in open(os.path.join(root, "rails", "incidents",
                                "adjudications.jsonl")):
        ln = ln.strip()
        if not ln:
            continue
        try:
            r = json.loads(ln)
        except Exception:
            continue
        if (r.get("kind") == "firing" and r.get("dispatch") == did
                and r.get("adjudication") == "true_catch"):
            catches.append((r.get("check", "?"), r.get("note", "")))
except Exception:
    pass

# decisions: the titles from the dispatch's DECISIONS.md
decisions = []
dd = dispatch_file("DECISIONS.md")
if dd:
    for ln in read(dd).splitlines():
        if ln.startswith("## "):
            decisions.append(ln[3:].strip())

# evidence content hash: sha256 over the sorted evidence files (path+bytes),
# the same shape as the governor fingerprint. This is where a v2 signature
# will attach. The receipt itself lives outside the evidence dir, so
# rendering does not perturb the hash it reports.
evid = os.path.join(root, "rails", "evidence", did)
h = hashlib.sha256()
for fn in sorted(os.listdir(evid)):
    p = os.path.join(evid, fn)
    if os.path.isfile(p):
        h.update(fn.encode())
        h.update(open(p, "rb").read())
ehash = h.hexdigest()

checks = v.get("checks") or {}
passed = [k for k, c in checks.items() if c.get("pass")]
suite = (checks.get("full_suite") or {}).get("detail", "")

lines = []
lines.append(f"# Receipt: {claim}")
lines.append("")
lines.append(summary)
lines.append("")
lines.append("## Verified")
if dtype or subsystem:
    lines.append(f"- type/subsystem: {dtype or '(unset)'} / "
                 f"{subsystem or '(unset)'}")
lines.append(f"- verdict: PASS ({len(passed)} of {len(checks)} checks), "
             f"{v.get('timestamp','?')}")
if suite:
    lines.append(f"- suite: {suite}")
lines.append(f"- checks: {', '.join(passed)}")
lines.append("")
lines.append("## Catches during this work")
if catches:
    lines.append(f"{len(catches)} block(s) adjudicated as a true catch:")
    for check, note in catches:
        lines.append(f"- {check}" + (f": {note}" if note else ""))
else:
    lines.append("none fired. (A check that never fired is unproven in "
                 "practice for this work, not proven perfect.)")
lines.append("")
lines.append("## Decisions")
if decisions:
    for d in decisions:
        lines.append(f"- {d}")
else:
    lines.append("(none recorded in the dispatch DECISIONS.md)")
lines.append("")
lines.append("## Provenance")
lines.append(f"- commit: {v.get('head','?')}")
lines.append(f"- governor fingerprint at verify time: "
             f"{v.get('governor_fingerprint','(not recorded)')}")
lines.append(f"- evidence content hash (sha256): {ehash}")
lines.append(f"- run: rails/evidence/{did}/ (tree {v.get('tree_hash','?')})")
lines.append("")
lines.append("Receipts carry their provenance; to trust one you didn't "
             "generate, follow it to its run. A receipt whose provenance "
             "doesn't resolve proves nothing.")
lines.append("")

open(out, "w").write("\n".join(lines))
print(out)
