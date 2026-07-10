#!/usr/bin/env python3
"""
extract.py <source> -- observer query transforms (Job 4B).

Reads a source's raw query output on stdin (except `drift`, which inspects
the repo it runs in directly) and emits CANDIDATE JSONL on stdout, one
object per line:

    {"id": ..., "title": ..., "evidence": ..., "problem": ..., "priority": ...}

run_observer.sh dedups candidates by the definition's dedup_field,
rate-limits, and renders the inbox template. Trigger THRESHOLDS live here so
the definition files stay declarative; D59 records the defaults (sentry: >5
users or regression; phoenix: p95 / fabrication-flag / token-spend, env-
tunable; npm: high+ severity; pip-audit: every advisory, it emits no
severity field; drift: 30-day staleness, RAILS_DRIFT_STALE_DAYS).

Evidence is always a REFERENCE (link or id), never a bulk payload. This file
is governor-adjacent (rails/observers/ is agent-read-only, D59); humans edit
thresholds. Find-don't-fix: nothing here mutates anything it observes.
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys


def emit(cid, title, evidence, problem, priority):
    sys.stdout.write(json.dumps({
        "id": str(cid), "title": str(title)[:120], "evidence": str(evidence),
        "problem": str(problem), "priority": priority}) + "\n")


def load_stdin():
    try:
        return json.load(sys.stdin)
    except Exception:
        return None


def week_bucket():
    y, w, _ = datetime.date.today().isocalendar()
    return "%dW%02d" % (y, w)


mode = sys.argv[1] if len(sys.argv) > 1 else ""

if mode == "sentry":
    # stdin: GET /api/0/projects/<org>/<project>/issues/ (JSON array).
    # Trigger: >5 users affected, or any regression on a resolved issue.
    for i in load_stdin() or []:
        if not isinstance(i, dict):
            continue
        users = int(i.get("userCount") or 0)
        regressed = str(i.get("substatus", "")).lower() == "regressed"
        if users > 5 or regressed:
            iid = i.get("id", "?")
            emit(iid, i.get("title", "?"),
                 i.get("permalink") or ("sentry issue %s" % iid),
                 "Sentry issue %s: %s, %d users affected since %s%s"
                 % (iid, i.get("title", "?"), users, i.get("firstSeen", "?"),
                    " (regression on a resolved issue)" if regressed else ""),
                 "P1" if regressed else "P2")

elif mode == "phoenix":
    # stdin: Arize Phoenix spans for the lookback window ({"data": [...]}).
    # Voice-agent containment watchdog: a fabrication catch in production
    # traces becomes an inbox item the same day. Three signals, env-tunable.
    d = load_stdin()
    spans = (d.get("data") if isinstance(d, dict) else d) or []
    spans = [s for s in spans if isinstance(s, dict)]
    wk = week_bucket()
    p95_max = int(os.environ.get("PHOENIX_P95_MS", "5000"))
    lats = sorted(float(s.get("latency_ms") or 0) for s in spans)
    if lats:
        p95 = lats[max(0, int(len(lats) * 0.95) - 1)]
        if p95 > p95_max:
            emit("phoenix-p95-" + wk, "latency p95 breach",
                 "Phoenix spans, lookback window (p95 %.0fms)" % p95,
                 "Phoenix: latency p95 %.0fms breaches the %dms threshold "
                 "(PHOENIX_P95_MS) over the lookback window" % (p95, p95_max),
                 "P2")
    flagged = [s for s in spans
               if any(re.search(r"hallucinat|fabricat", str(a.get("name", "")), re.I)
                      and str(a.get("label", "")).lower() in ("flagged", "true", "fail")
                      for a in (s.get("annotations") or []) if isinstance(a, dict))]
    if flagged:
        first = flagged[0]
        sid = str(first.get("id") or (first.get("context") or {}).get("span_id") or "?")
        emit("phoenix-fabrication-" + wk,
             "%d fabrication-flagged trace(s)" % len(flagged),
             "Phoenix span %s (first of %d)" % (sid, len(flagged)),
             "Phoenix: %d production trace(s) carry a hallucination/"
             "fabrication eval flag in the lookback window" % len(flagged),
             "P1")
    tok_max = int(os.environ.get("PHOENIX_TOKENS_MAX", "0"))  # 0 = signal off
    if tok_max:
        total = sum(int(s.get("token_count_total") or 0) for s in spans)
        if total > tok_max:
            emit("phoenix-cost-" + wk, "token-spend spike",
                 "Phoenix spans, lookback window (%d tokens)" % total,
                 "Phoenix: %d total tokens in the lookback window breaches "
                 "the %d threshold (PHOENIX_TOKENS_MAX) -- cost-per-trace "
                 "spike" % (total, tok_max), "P2")

elif mode == "langsmith":
    # stdin: POST /api/v1/runs/query filtered to errored runs ({"runs": [...]}).
    d = load_stdin()
    runs = (d.get("runs") if isinstance(d, dict) else d) or []
    for r in runs:
        if not isinstance(r, dict):
            continue
        if str(r.get("status", "")).lower() == "error" or r.get("error"):
            rid = r.get("id", "?")
            emit("ls-%s" % rid, "LangSmith failed run %s" % rid,
                 r.get("app_path") or ("langsmith run %s" % rid),
                 "LangSmith run %s errored on project %s: %s"
                 % (rid, r.get("session_id", "?"),
                    str(r.get("error", "?"))[:120]),
                 "P2")

elif mode == "posthog":
    # stdin: GET /api/projects/<id>/events/?event=$exception ({"results": [...]}).
    # Grouped per exception type per day -- product signal in, proposal out.
    d = load_stdin()
    events = (d.get("results") if isinstance(d, dict) else d) or []
    day = datetime.date.today().isoformat()
    by_type = {}
    for e in events:
        if not isinstance(e, dict):
            continue
        props = e.get("properties") or {}
        t = str(props.get("$exception_type")
                or props.get("$exception_message") or "unknown")[:80]
        by_type[t] = by_type.get(t, 0) + 1
    for t, n in sorted(by_type.items()):
        emit("ph-%s-%s" % (hashlib.sha256(t.encode()).hexdigest()[:8], day),
             "PostHog error events: %s" % t,
             "PostHog $exception events, last day (type %s)" % t,
             "PostHog: %d new error event(s) of type %s in the last day"
             % (n, t), "P2")

elif mode == "ci":
    # stdin: gh run list --json databaseId,displayTitle,url,createdAt (array).
    for r in load_stdin() or []:
        if not isinstance(r, dict):
            continue
        rid = r.get("databaseId", "?")
        emit("ci-%s" % rid, "CI failure: %s" % r.get("displayTitle", "?"),
             r.get("url", "?"),
             "CI run %s failed on main: %s (%s)"
             % (rid, r.get("displayTitle", "?"), r.get("createdAt", "?")),
             "P1")

elif mode == "pip":
    # stdin: pip-audit -f json against the requirements lockfile. pip-audit
    # emits no severity field, so EVERY advisory files (documented in the
    # definition's trigger). Never auto-updates anything.
    d = load_stdin()
    deps = (d.get("dependencies") if isinstance(d, dict) else d) or []
    for dep in deps:
        if not isinstance(dep, dict):
            continue
        for v in dep.get("vulns") or []:
            if not isinstance(v, dict):
                continue
            vid = v.get("id", "?")
            fixes = ", ".join(v.get("fix_versions") or []) or "none listed"
            emit("pip-%s-%s" % (dep.get("name", "?"), vid),
                 "pip advisory %s: %s" % (vid, dep.get("name", "?")),
                 "https://osv.dev/vulnerability/%s" % vid,
                 "Security advisory %s against %s %s (pip-audit vs lockfile; "
                 "fix versions: %s). Never auto-update -- propose the bump "
                 "as a dispatch." % (vid, dep.get("name", "?"),
                                     dep.get("version", "?"), fixes),
                 "P1")

elif mode == "npm":
    # stdin: npm audit --json vs package-lock.json. high+ severity only.
    d = load_stdin() or {}
    vulns = d.get("vulnerabilities") or {}
    for pkg, info in sorted(vulns.items()):
        if not isinstance(info, dict):
            continue
        sev = str(info.get("severity", "")).lower()
        if sev not in ("high", "critical"):
            continue
        emit("npm-%s-%s" % (pkg, sev), "npm advisory: %s (%s)" % (pkg, sev),
             "npm audit --json (package %s, range %s)"
             % (pkg, info.get("range", "?")),
             "Security advisory at %s severity against %s %s (npm audit vs "
             "package-lock.json). Never auto-update -- propose the bump as "
             "a dispatch." % (sev, pkg, info.get("range", "?")),
             "P1" if sev == "critical" else "P2")

elif mode == "drift":
    # No stdin: the kit watching its own decay, per installed repo (cwd --
    # run_observer.sh runs the query from the repo root). Files only on a
    # failing or stale condition; dedup per condition per ISO week so a
    # persisting condition re-surfaces weekly, never floods daily.
    root = os.getcwd()
    wk = week_bucket()
    stale_days = int(os.environ.get("RAILS_DRIFT_STALE_DAYS", "30"))
    now = datetime.datetime.now(datetime.timezone.utc)

    doctor = os.path.join(root, "rails", "verifier", "doctor.sh")
    if os.path.isfile(doctor):
        r = subprocess.run(["bash", doctor], capture_output=True, text=True)
        if r.returncode != 0:
            first = next((ln.strip() for ln in r.stdout.splitlines()
                          if "[FAIL]" in ln), "see doctor output")
            emit("doctor-fail-" + wk, "doctor.sh failing",
                 "bash rails/verifier/doctor.sh",
                 "Kit self-check: doctor.sh FAILs (%s)" % first[:160], "P1")

    bp = os.path.join(root, "rails", "verifier", "baseline.json")
    if os.path.isfile(bp):
        age = (now - datetime.datetime.fromtimestamp(
            os.path.getmtime(bp), datetime.timezone.utc)).days
        if age > stale_days:
            emit("baseline-stale-" + wk, "baseline %d days old" % age,
                 "rails/verifier/baseline.json",
                 "Kit self-check: the test-count baseline is %d days old "
                 "(threshold %d) -- re-seed it from a known-good run"
                 % (age, stale_days), "P3")

    regp = os.path.join(root, "rails", "adversarial", "registry.json")
    try:
        run_id = json.load(open(regp)).get("run_id", "")
        stamped = datetime.datetime.strptime(
            run_id, "%Y%m%dT%H%M%SZ").replace(tzinfo=datetime.timezone.utc)
        age = (now - stamped).days
        if age > stale_days:
            emit("stamp-stale-" + wk, "governor stamp %d days old" % age,
                 "rails/adversarial/registry.json",
                 "Kit self-check: the governor was last proven %d days ago "
                 "(threshold %d) -- re-run bash rails/adversarial/run_eval.sh"
                 % (age, stale_days), "P2")
    except Exception:
        pass  # no registry / no run_id: doctor already reports unproven

    inc = os.path.join(root, "rails", "verifier", "incident.py")
    if os.path.isfile(inc):
        r = subprocess.run(["python3", inc, "check", root],
                           capture_output=True, text=True)
        if r.returncode != 0:
            emit("unlinked-incidents-" + wk, "unlinked incident(s)",
                 "rails/incidents/",
                 "Kit self-check: unlinked incident record(s) block the next "
                 "governor stamp -- link each to its covering eval case",
                 "P2")

else:
    sys.stderr.write("extract.py: unknown source '%s' -- use one of: sentry "
                     "phoenix langsmith posthog ci pip npm drift\n" % mode)
    sys.exit(2)
