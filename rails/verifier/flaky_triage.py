#!/usr/bin/env python3
"""
flaky_triage.py <root>  -- re-run the suite N times, NAME the unstable tests,
and emit the manifest entry to quarantine each (Job 9b Part 4).

FIND, DON'T FIX: it proposes; a HUMAN declares (moves the test into the lane
dir and adds the entry to rails/verifier/flaky_lane.json). It NEVER
auto-quarantines and NEVER retries-until-green -- retrying a flaky test until
it passes hides a real failure behind a green, the inflation failure the kit
exists to prevent. L10: honest about what a flaky suite can and cannot prove.

The body lives here rather than a bash heredoc so it reads and tests on its
own; flaky_triage.sh is a thin shim that resolves <root>, cds into it, and
execs this. Read-only on your work tree. Lives in the trust layer; not
agent-editable.
"""
import datetime, json, os, re, shutil, subprocess, sys
root = sys.argv[1]
try:
    cfg = json.load(open(os.path.join(root, "rails", "config.json")))
except Exception:
    cfg = {}
test_cmd = cfg.get("test_cmd", "")
n = int(cfg.get("flaky_runs", 3) or 3)
if not test_cmd:
    print("flaky_triage: no test_cmd in rails/config.json -- set it (or run rails init), then re-run.")
    sys.exit(2)

print("flaky_triage: re-running the suite %dx to find unstable tests." % n)
print("(find-don't-fix: nothing is quarantined automatically; a human decides.)\n")


def outcomes(text):
    """Per-test pass/fail across unittest -v and pytest -v output."""
    res = {}
    for m in re.finditer(r'^(\S+ \([\w.]+\)) \.\.\. (ok|FAIL|ERROR|skipped)', text, re.M):
        res[m.group(1)] = "pass" if m.group(2) == "ok" else m.group(2)
    for m in re.finditer(r'^(\S+::\S+)\s+(PASSED|FAILED|ERROR|SKIPPED)', text, re.M):
        res[m.group(1)] = "pass" if m.group(2) == "PASSED" else m.group(2)
    return res


# case-23 class (D60): triage must grade the bytes on disk -- sweep cached
# bytecode once, and keep the repeated runs from repopulating it. A same-second
# same-size source edit otherwise leaves a stale pyc that every run reads,
# inverting the very flake investigation this tool exists for.
for _dp, _dns, _ in os.walk(root):
    _dns[:] = [d for d in _dns if d not in (".git", "node_modules")]
    if "__pycache__" in _dns:
        shutil.rmtree(os.path.join(_dp, "__pycache__"), ignore_errors=True)
        _dns.remove("__pycache__")
runs = []
for _ in range(n):
    # test_cmd is the operator's own command from rails/config.json -- running
    # the configured suite is the kit's job (verify.sh runs the same one). It is
    # NOT an injection surface: config.json is guard-protected (agent-read-only),
    # and inside isolate/ it is mounted read-only. The shell is required -- real
    # configs use redirects/pipes (e.g. the shipped jest example "... 2>&1"), so
    # shlex.split-without-a-shell would break them.
    r = subprocess.run(["bash", "-c", test_cmd], capture_output=True, text=True, cwd=root,
                       env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
    runs.append(outcomes((r.stdout or "") + (r.stderr or "")))

seen_any = set().union(*runs) if runs else set()
flaky = []
for t in sorted(seen_any):
    results = {run.get(t, "absent") for run in runs}
    if len(results) > 1:           # different result run-to-run == unstable
        flaky.append((t, sorted(results)))

if not seen_any:
    print("could not parse per-test results (need a verbose runner: pytest -v / "
          "unittest -v). Set test_cmd to a verbose form and re-run.")
    sys.exit(0)
if not flaky:
    print("no flaky tests across %d runs -- every test was consistent. The suite "
          "looks deterministic; no quarantine needed." % n)
    sys.exit(0)

print("%d UNSTABLE test(s) across %d runs (different result run-to-run):" % (len(flaky), n))
for t, results in flaky:
    print("  %s: %s" % (t, results))
today = datetime.date.today().isoformat()
print("\nTo quarantine one (a HUMAN decision -- the kit will not):")
print("  1. move its test file into the lane dir (config flaky_glob), a tree edit")
print("     the gated suite no longer collects;")
print("  2. add an entry to rails/verifier/flaky_lane.json:")
print(json.dumps([{
    "test_id": flaky[0][0],
    "path": "<lane path after you move it>",
    "date": today,
    "reason": "<why it flakes -- and a fix dispatch beats a permanent quarantine>",
}], indent=2))
print("\nNothing was changed. The lane runs NON-GATING and names its results in "
      "the verdict; a quarantined test that decays into a real failure stays "
      "visible. The kit never retries a flaky test until it passes.")
