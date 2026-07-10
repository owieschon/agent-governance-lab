#!/usr/bin/env python3
"""
status.py <root>  -- read-only operator dashboard (backs the /status command).

Surfaces, at a glance: active dispatches and their state, BLOCKED handoffs
with reasons, incidents lacking a linked_case, whether the governor is proven
(with stamp age), baseline age, and the last verify verdict. It computes
nothing the verifier did not already establish -- every line is a view over
the on-disk ledger (rails/evidence/, rails/incidents/, rails/handoff/) plus
the registry stamp and baseline. Read-only; safe to run any time.

The body lives here rather than in a bash heredoc so it is readable and
testable on its own; status.sh is a thin shim that resolves <root> and execs
this. Lives in the trust layer; not agent-editable.
"""
import datetime, glob, json, os, sys

root = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc)


def load(p):
    try:
        return json.load(open(p))
    except Exception:
        return None


def age(dt):
    secs = (now - dt).total_seconds()
    for unit, n in (("d", 86400), ("h", 3600), ("m", 60)):
        if secs >= n:
            return f"{int(secs // n)}{unit} ago"
    return "just now"


def mtime_age(p):
    try:
        return age(datetime.datetime.fromtimestamp(os.path.getmtime(p), datetime.timezone.utc))
    except Exception:
        return "unknown"


def current_tree():
    import subprocess
    try:
        return subprocess.run(["python3", os.path.join(root, "rails", "verifier", "treehash.py")],
                              capture_output=True, text=True, cwd=root, timeout=30).stdout.strip()
    except Exception:
        return "UNKNOWN"


print("==================== 3xit2 status ====================\n")

# governor
reg = load(os.path.join(root, "rails", "adversarial", "registry.json"))
if not reg:
    print("  governor:   NOT PROVEN (no registry.json -- run the eval)")
else:
    rid = reg.get("run_id", "")
    when = "unknown"
    try:
        when = age(datetime.datetime.strptime(rid, "%Y%m%dT%H%M%SZ").replace(
            tzinfo=datetime.timezone.utc))
    except Exception:
        when = mtime_age(os.path.join(root, "rails", "adversarial", "registry.json"))
    print(f"  governor:   proven, stamped {when} "
          f"(fingerprint {str(reg.get('last_proven_fingerprint',''))[:12]}...)")

# baseline
bp = os.path.join(root, "rails", "verifier", "baseline.json")
b = load(bp)
if b:
    print(f"  baseline:   test_count={b.get('test_count','?')}, updated {mtime_age(bp)}")
else:
    print("  baseline:   MISSING (seed with verify.sh BOOTSTRAP --update-baseline)")

# active dispatches
tree = current_tree()
active = sorted(d for d in glob.glob(os.path.join(root, "rails", "dispatches", "active", "*"))
                if os.path.isdir(d))
print(f"\n  active dispatches: {len(active)}")
for d in active:
    did = os.path.basename(d)
    approved = os.path.exists(os.path.join(d, "APPROVED"))
    v = load(os.path.join(root, "rails", "evidence", did, "verdict.json"))
    if not v:
        state = "no verdict yet"
    elif v.get("status") != "PASS":
        state = f"last verdict {v.get('status','?')}"
    elif v.get("tree_hash") != tree:
        state = "PASS but STALE (tree changed since verify)"
    else:
        state = "PASS (fresh)"
    print(f"      {did}: {'approved' if approved else 'NOT approved'}, {state}")

# blocked handoffs
blocked = sorted(glob.glob(os.path.join(root, "rails", "handoff", "*.BLOCKED.md")))
print(f"\n  blocked handoffs: {len(blocked)}")
for p in blocked:
    first = ""
    try:
        for ln in open(p):
            if ln.strip():
                first = ln.strip()
                break
    except Exception:
        pass
    print(f"      {os.path.basename(p)}: {first[:90]}")

# incidents (human_verdict appends are verdicts on incidents, not incidents --
# same skip the incident.py gate applies, so display never contradicts it)
incs = [load(p) for p in glob.glob(os.path.join(root, "rails", "incidents", "*.json"))]
incs = [i for i in incs if i and i.get("kind") != "human_verdict"]
unlinked = [i for i in incs if not str(i.get("linked_case") or "").strip()]
print(f"\n  incidents: {len(incs)} recorded, {len(unlinked)} UNLINKED")
for i in unlinked:
    print(f"      {i.get('id','?')} [{i.get('trigger','?')}] dispatch={i.get('dispatch','?')} "
          f"-- needs linked_case")

# precision / attention signals (Job 8 Part B). All three are ONE mechanism
# (a rolling window over a threshold) pointed at different events: check
# precision, approval fatigue, default fitness. Routed find-don't-fix: they
# flag, the human decides; nothing here auto-disables or blocks.
#
# Forward note (DELTA-2, D23): these per-check/per-window primitives,
# aggregated over time, would constitute rigor-decay detection -- precision
# trending down, review-minutes toward zero at ~100% approval, work bypassing
# dispatch. That aggregation is deliberately NOT built. Its guardrail is
# non-negotiable: rigor-decay signals are a MIRROR an operator chooses to look
# into, never a number reported up a hierarchy or wired to a gate or
# incentive. A scored, reported rigor metric gets managed, and a managed
# rigor-score is rigor decay with a green light.
import subprocess as _sp
try:
    _sig = _sp.run(["python3", os.path.join(root, "rails", "verifier", "adjudicate.py"),
                    "signals", root], capture_output=True, text=True, timeout=30).stdout.strip()
except Exception:
    _sig = ""
print("\n  signals (precision / attention / defaults):")
if _sig:
    for ln in _sig.splitlines():
        print(f"      {ln}")
else:
    print("      none. (Checks with no adjudicated firings are unproven in "
          "practice, not proven precise.)")

# quarantine lane (Job 9b): declared-flaky tests + staleness pressure (a long
# quarantine with no fix is a debt the operator should see -- L10 freshness
# sibling). Read-only summary; the lane runs non-gating in verify.
man = load(os.path.join(root, "rails", "verifier", "flaky_lane.json"))
if isinstance(man, list) and man:
    import datetime as _dt
    today = _dt.date.today()
    olds = []
    for e in man:
        try:
            olds.append((today - _dt.date.fromisoformat(str(e.get("date",""))[:10])).days)
        except Exception:
            pass
    oldest = (" (oldest %dd)" % max(olds)) if olds else ""
    print(f"\n  flaky lane: {len(man)} test(s) quarantined{oldest} -- non-gating; "
          "a long quarantine with no fix dispatch is a debt to clear")

# last verdict overall
verdicts = sorted(glob.glob(os.path.join(root, "rails", "evidence", "*", "verdict.json")),
                  key=lambda p: os.path.getmtime(p) if os.path.exists(p) else 0)
if verdicts:
    lv = load(verdicts[-1])
    if lv:
        print(f"\n  last verify: {lv.get('dispatch','?')} -> {lv.get('status','?')} "
              f"({mtime_age(verdicts[-1])})")
print()
