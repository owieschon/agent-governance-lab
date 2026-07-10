#!/usr/bin/env python3
"""
adjudicate.py -- precision adjudication + attention signals (Job 8 Part B).

One append-only stream, rails/incidents/adjudications.jsonl, holds four
record kinds (one schema family, the D23 corpus shape: timestamp, dispatch,
dispatch_type, subsystem, tree_hash, actor on every record):

  firing      -- a human RESOLVED a gate-fire/verify-FAIL and adjudicated it:
                 true_catch     the check stopped real badness. It worked.
                 false_block    the work was fine; the check was wrong/brittle.
                 manifest_fault the work was fine but the manifest was wrong, so
                                the check fired correctly on bad inputs. NOT
                                counted against the check's precision.
  approval    -- a handoff review concluded: approved yes/no + review_minutes
                 (supplied by the human at the gate; null if skipped, never
                 estimated -- the denominator for the approval-fatigue signal).
  observation -- a config-default observation (e.g. one per session: which
                 posture ran vs the shipped default) -- the L1 default-fitness
                 event source.
  reviewer_false_positive -- a human flagged a WRONG reviewer finding at the
                 handoff gate (D58). Ground truth that MEASURES the reviewer;
                 it is NEVER read back into reviewer prompting, the rubric, or
                 the trigger scripts (corpus fence, case 46 grep-proves it --
                 forbidden, not deferred). Same record family, no schema fork:
                 the D57 context (dispatch_type, subsystem, tree_hash, actor)
                 travels automatically.

The precision/attention signals are ONE mechanism: a rolling window over a threshold
(window_signal), pointed at different events. This is the deliberate reuse
the product principles require (L1 default-fitness == check precision == the
fatigue denominator); do not build a parallel system.

Signals are routed find-don't-fix: nothing here auto-disables, auto-tunes,
or blocks. `status` surfaces them; the human decides whether to fix the
check, the config, or dispatch hygiene. A check that has never fired has
UNDEFINED precision -- surfaced as "unproven in practice", never as perfect.

Human-supplied: a human runs `record`/`approval`; the agent does not
adjudicate its own firings. The stream is append-only and guard-protected
(rails/incidents/). Lives in the trust layer; not agent-editable.

CLI:
  adjudicate.py record   <proj> <check> <dispatch> <adjudication> [note...]
  adjudicate.py approval <proj> <dispatch> <yes|no> <minutes|skip> [note...]
  adjudicate.py observe  <proj> <field> <value> <default> <session-key>
  adjudicate.py flag     <proj> <dispatch> <kind> [note...]   # kinds: FLAG_KINDS
  adjudicate.py signals  <proj>       # all status lines (precision, fatigue,
                                      # default-fitness), plain text
"""
import datetime
import json
import os
import subprocess
import sys

VALID = ("true_catch", "false_block", "manifest_fault")
FLAG_KINDS = ("reviewer_false_positive",)
WINDOW = 20        # rolling window per check / per field (spec B2 default)
MIN_N = 3          # below this, a window is too thin to mean anything (L10)
FATIGUE_WINDOW = 10
FATIGUE_MIN_TIMED = 5     # need this many timed reviews before the mean means
FATIGUE_MEAN_MIN = 2.0    # mean review_minutes at/below this trends-toward-zero
FATIGUE_APPROVE_RATE = 0.9


def _path(proj):
    return os.path.join(proj, "rails", "incidents", "adjudications.jsonl")


def _read(path):
    rows = []
    try:
        with open(path) as f:
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


def _tree_hash(proj):
    try:
        r = subprocess.run(
            ["python3", os.path.join(proj, "rails", "verifier", "treehash.py")],
            capture_output=True, text=True, cwd=proj, timeout=30)
        return r.stdout.strip() or "UNKNOWN"
    except Exception:
        return "UNKNOWN"


def _dispatch_context(proj, dispatch):
    """Optional manifest keys (D23 corpus shape): type, subsystem."""
    for state in ("active", "archive"):
        p = os.path.join(proj, "rails", "dispatches", state, dispatch, "manifest.json")
        try:
            m = json.load(open(p))
            return str(m.get("type", "") or ""), str(m.get("subsystem", "") or "")
        except Exception:
            continue
    return "", ""


def _base(proj, dispatch, kind, note=""):
    dtype, subsystem = _dispatch_context(proj, dispatch) if dispatch else ("", "")
    return {
        "kind": kind,
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "dispatch": dispatch,
        "dispatch_type": dtype,
        "subsystem": subsystem,
        "tree_hash": _tree_hash(proj),
        "actor": os.environ.get("USER", "unknown"),
        "note": note,
    }


def _append(proj, rec):
    os.makedirs(os.path.dirname(_path(proj)), exist_ok=True)
    with open(_path(proj), "a") as f:
        f.write(json.dumps(rec) + "\n")
    return rec


def record(proj, check, dispatch, adjudication, note=""):
    if adjudication not in VALID:
        raise ValueError(f"adjudication must be one of {VALID}")
    rec = _base(proj, dispatch, "firing", note)
    rec["check"] = check
    rec["adjudication"] = adjudication
    return _append(proj, rec)


def approval(proj, dispatch, approved, minutes, note=""):
    """minutes: a number, or None when the human skipped -- never estimated."""
    rec = _base(proj, dispatch, "approval", note)
    rec["approved"] = bool(approved)
    rec["review_minutes"] = minutes
    return _append(proj, rec)


def flag(proj, dispatch, kind, note=""):
    """A wrong reviewer finding, flagged by the human at the handoff gate
    (D58). The kind is validated; the actor and the D57 dispatch context are
    attributed by _base -- no schema fork. This stream MEASURES the reviewer;
    no code path may read it back into reviewer prompting (corpus fence,
    case 46)."""
    if kind not in FLAG_KINDS:
        raise ValueError(f"flag kind must be one of {FLAG_KINDS}")
    return _append(proj, _base(proj, dispatch, kind, note))


def observe(proj, field, value, default, session_key):
    """One default-fitness observation per (field, session_key) -- idempotent,
    so the gating layer can call this on every session stop without spam."""
    for r in _read(_path(proj)):
        if r.get("kind") == "observation" and r.get("field") == field \
                and r.get("session_key") == session_key:
            return None
    rec = _base(proj, "", "observation")
    rec["field"] = field
    rec["value"] = value
    rec["default"] = default
    rec["session_key"] = session_key
    return _append(proj, rec)


def window_signal(events, key_of, outcome_of, bad, window=WINDOW, min_n=MIN_N):
    """The ONE rolling-window-over-threshold core (precision, fitness, fatigue
    all point this at different events). events: chronological. Returns
    {key: (bad_count, n)} for keys whose last <window> outcomes are a strict
    majority bad, with at least min_n outcomes (below min_n the sample is too
    thin to support the flag -- L10). Keys with zero events are absent:
    undefined, not perfect; the caller surfaces those separately."""
    by_key = {}
    for e in events:
        by_key.setdefault(key_of(e), []).append(outcome_of(e))
    flagged = {}
    for k, outs in by_key.items():
        w = outs[-window:]
        bad_n = sum(1 for o in w if bad(o))
        if len(w) >= min_n and bad_n * 2 > len(w):
            flagged[k] = (bad_n, len(w))
    return flagged


def precision(proj):
    """(under_review, unproven). manifest_fault is excluded from the
    computation -- it is attributed to the manifest layer, not the check."""
    rows = _read(_path(proj))
    firings = [r for r in rows if r.get("kind") == "firing"]
    counted = [r for r in firings if r.get("adjudication") != "manifest_fault"]
    under = window_signal(
        counted, lambda r: r.get("check"), lambda r: r.get("adjudication"),
        lambda o: o == "false_block")
    fired = {r.get("check")
             for r in _read(os.path.join(proj, "rails", "evidence", "stats.jsonl"))}
    adjudicated = {r.get("check") for r in firings}
    unproven = sorted(c for c in fired if c and c not in adjudicated)
    return under, unproven


def fatigue(proj):
    """The rubber-stamp signal: mean review_minutes trending toward zero while
    the approval rate stays at/near 100% over the window. A signal to the
    human about their OWN attention -- surfaced plainly, never a block.
    Returns (line_or_None, honesty_line_or_None)."""
    apps = [r for r in _read(_path(proj)) if r.get("kind") == "approval"]
    w = apps[-FATIGUE_WINDOW:]
    if not w:
        return None, None
    timed = [r["review_minutes"] for r in w
             if isinstance(r.get("review_minutes"), (int, float))]
    rate = sum(1 for r in w if r.get("approved")) / len(w)
    if len(w) >= FATIGUE_MIN_TIMED and len(timed) * 2 < len(w):
        return None, (f"review timing mostly unrecorded ({len(timed)} of "
                      f"{len(w)} recent reviews timed) -- the approval-fatigue "
                      "signal cannot compute; record minutes at the handoff "
                      "gate to enable it")
    if len(timed) >= FATIGUE_MIN_TIMED:
        mean = sum(timed) / len(timed)
        if mean <= FATIGUE_MEAN_MIN and rate >= FATIGUE_APPROVE_RATE:
            return (f"attention: mean review time {mean:.1f} min with "
                    f"{rate:.0%} approval over the last {len(w)} reviews -- "
                    "this is the rubber-stamp shape. Consider slowing one "
                    "review down or sampling a handoff at full depth"), None
    return None, None


def default_fitness(proj):
    """L1 default-fitness via the SAME window mechanism: a field whose recent
    observations are majority overridden flags 'default under review'."""
    obs = [r for r in _read(_path(proj)) if r.get("kind") == "observation"]
    flagged = window_signal(
        obs, lambda r: r.get("field"),
        lambda r: (r.get("value"), r.get("default")),
        lambda o: o[0] != o[1])
    out = []
    for field, (b, n) in sorted(flagged.items()):
        defaults = {r.get("default") for r in obs if r.get("field") == field}
        d = next(iter(defaults)) if len(defaults) == 1 else "?"
        out.append((field, b, n, d))
    return out


def catch_account(proj, check, dispatch, note):
    """The screenshot-shaped catch account (C4): factual, dry, one or two
    lines, stating what was caught in concrete terms. Rendering over what the
    verifier already established -- the detail comes from the verdict."""
    detail = ""
    try:
        v = json.load(open(os.path.join(proj, "rails", "evidence", dispatch,
                                        "verdict.json")))
        detail = (v.get("checks", {}).get(check, {}) or {}).get("detail", "")
    except Exception:
        pass
    lines = [f"CAUGHT: {check} blocked {dispatch}."]
    second = note.strip() or detail.strip()
    if second:
        lines.append(f"  {second}")
    return "\n".join(lines)


def signals(proj):
    """Every Part B status line, plain text. Empty output = nothing to flag."""
    out = []
    under, unproven = precision(proj)
    for c, (b, n) in sorted(under.items()):
        out.append(f"under review: precision -- {c}: {b} of {n} recent "
                   "adjudicated firings were false_block. Decide: fix the "
                   "check, the config, or dispatch hygiene (it never "
                   "auto-disables)")
    for c in unproven:
        out.append(f"unproven in practice -- {c} has fired but no firing has "
                   "been adjudicated yet (undefined precision, not perfect); "
                   "adjudicate resolved blocks with adjudicate.py record")
    line, honesty = fatigue(proj)
    if line:
        out.append(line)
    if honesty:
        out.append(honesty)
    for field, b, n, d in default_fitness(proj):
        out.append(f"default under review: {field} -- {b} of {n} recent "
                   f"sessions overrode the shipped default '{d}'. If the "
                   "override is the real common case, change the default "
                   "(rails/config.json); a default fought routinely is wrong")
    return "\n".join(out)


def _main(argv):
    if len(argv) >= 6 and argv[1] == "record":
        proj, check, dispatch, adj = argv[2:6]
        note = " ".join(argv[6:])
        try:
            record(proj, check, dispatch, adj, note)
        except ValueError as e:
            print(e, file=sys.stderr)
            return 2
        if adj == "true_catch":
            print(catch_account(proj, check, dispatch, note))
        else:
            print(f"adjudicated {check} on {dispatch}: {adj}")
        return 0
    if len(argv) >= 6 and argv[1] == "approval":
        proj, dispatch, yn, mins = argv[2:6]
        note = " ".join(argv[6:])
        minutes = None
        if mins not in ("skip", "null", ""):
            try:
                minutes = float(mins)
            except ValueError:
                print("minutes must be a number or 'skip' (never estimated)",
                      file=sys.stderr)
                return 2
        approval(proj, dispatch, yn == "yes", minutes, note)
        print(f"approval recorded for {dispatch}: {yn}"
              + (f", {minutes} min review" if minutes is not None
                 else ", review time skipped"))
        return 0
    if len(argv) >= 5 and argv[1] == "flag":
        proj, dispatch, kind = argv[2:5]
        note = " ".join(argv[5:])
        try:
            flag(proj, dispatch, kind, note)
        except ValueError as e:
            print(e, file=sys.stderr)
            return 2
        print(f"flagged {kind} on {dispatch}")
        return 0
    if len(argv) == 7 and argv[1] == "observe":
        r = observe(proj=argv[2], field=argv[3], value=argv[4],
                    default=argv[5], session_key=argv[6])
        print("observed" if r else "(already observed this session)")
        return 0
    if len(argv) == 3 and argv[1] == "signals":
        s = signals(argv[2])
        if s:
            print(s)
        return 0
    print("usage: adjudicate.py record|approval|observe|flag|signals ... "
          "(see module docstring)", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
