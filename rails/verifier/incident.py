#!/usr/bin/env python3
"""
incident.py -- the incident ledger (rails/incidents/).

An incident is a durable, tamper-evident record of a governance event that
must not be silently forgotten:
  - a dispatch ended BLOCKED, or
  - verify.sh flipped PASS -> FAIL on an UNCHANGED tree hash (a check that
    once certified the exact same tree now rejects it: either the old PASS
    was wrong or the new FAIL is -- both demand a human look).

Records are append-only. The trust layer (verify.sh, gate_stop.py) WRITES
them; the agent may not edit or delete an existing one (guard_files.py /
guard_bash.py enforce that). A human links each incident to the eval case
that now covers its failure shape by setting "linked_case"; run_eval.sh
refuses to re-stamp the governor while any incident is still unlinked --
the accretion rule, mechanized: a class that bit us once does not get
forgotten until a test guarantees it cannot bite twice.

Records carry the D23 corpus context (dispatch_type/subsystem from the
dispatch manifest -- OPTIONAL keys, empty strings when absent, never a
crash) plus two agent-drafted fields: hypothesized_mechanism and
minimal_repro, marked hypothesis_status DRAFT until a human rules. The
human verdict is a NEW append (its own record, actor-attributed); the
draft is never edited -- the correction history stays (D57).

CLI:
  python3 incident.py record <proj> <dispatch> <trigger> <check> \\
                             <claimed> <observed> <tree_hash> \\
                             [hypothesized_mechanism] [minimal_repro]
  python3 incident.py verdict <proj> <incident-id> <confirmed|corrected> \\
                              <actor> [text...]   # human-run; a NEW append
  python3 incident.py check  <proj>        # exit 1 if any incident unlinked

Lives in the trust layer; not agent-editable.
"""
import datetime
import glob
import json
import os
import sys

# process_gap: a hole in the kit's own process caught in the field (e.g. an
# untracked file silently inside the stamped fingerprint, 2026-06-10) -- same
# accretion contract as the others: it stays unlinked-and-blocking until an
# eval case covers the shape.
VALID_TRIGGERS = ("blocked", "pass_to_fail_unchanged_tree", "process_gap")
VALID_VERDICTS = ("confirmed", "corrected")


def _incidents_dir(proj):
    return os.path.join(proj, "rails", "incidents")


def _dispatch_context(proj, dispatch):
    """Optional manifest keys (D23 corpus shape): type, subsystem.
    Deliberately duplicated from adjudicate.py (D57): a cross-import between
    trust-layer files would couple their load paths for ten lines of code.
    Empty strings when a manifest omits the keys or does not exist -- the
    exhaust contract is non-fatal by design."""
    for state in ("active", "archive"):
        p = os.path.join(proj, "rails", "dispatches", state, dispatch, "manifest.json")
        try:
            m = json.load(open(p))
            return str(m.get("type", "") or ""), str(m.get("subsystem", "") or "")
        except Exception:
            continue
    return "", ""


def _load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def record(proj, dispatch, trigger, check, claimed, observed, tree_hash,
           hypothesized_mechanism="", minimal_repro=""):
    """Append one incident, idempotent on (dispatch, trigger, tree_hash).

    Returns the record path, or None if a matching open record already exists
    (so repeated verify/stop runs on the same state do not spam the ledger).
    """
    d = _incidents_dir(proj)
    os.makedirs(d, exist_ok=True)
    for existing in glob.glob(os.path.join(d, "*.json")):
        r = _load(existing)
        if r and r.get("kind") == "human_verdict":
            continue  # verdict appends are not incidents
        if r and (r.get("dispatch"), r.get("trigger"), r.get("tree_hash")) == (
            dispatch, trigger, tree_hash
        ):
            return None  # already recorded this exact event
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    stamp = ts.replace(":", "").replace("-", "").split(".")[0] + "Z"
    safe_dispatch = "".join(c if c.isalnum() or c in "-_" else "_" for c in dispatch)
    dtype, subsystem = _dispatch_context(proj, dispatch)
    rec = {
        "id": f"INC-{stamp}-{safe_dispatch}",
        "timestamp": ts,
        "dispatch": dispatch,
        "dispatch_type": dtype,
        "subsystem": subsystem,
        "trigger": trigger,
        "check": check,
        "claimed": claimed,
        "observed": observed,
        "tree_hash": tree_hash,
        # Agent-drafted at incident time; a human verdict NEVER edits these
        # (it appends its own record via verdict()). DRAFT only when a
        # hypothesis was actually drafted -- never a fake status.
        "hypothesized_mechanism": str(hypothesized_mechanism or ""),
        "minimal_repro": str(minimal_repro or ""),
        "hypothesis_status": "DRAFT" if hypothesized_mechanism else None,
        "linked_case": None,
    }
    path = os.path.join(d, rec["id"] + ".json")
    # never clobber: if the id collides, suffix it
    n = 1
    while os.path.exists(path):
        path = os.path.join(d, f"{rec['id']}-{n}.json")
        n += 1
    with open(path, "w") as f:
        json.dump(rec, f, indent=2)
    return path


def verdict(proj, incident_id, status, actor, note=""):
    """Append the HUMAN verdict on an incident's draft hypothesis as a NEW
    record (the incident append-only law: never an edit of the draft). Each
    further verdict appends again -- the correction history stays (D57).
    Returns the verdict path; raises ValueError on a bad status or an
    unknown incident."""
    if status not in VALID_VERDICTS:
        raise ValueError(f"verdict must be one of {VALID_VERDICTS}")
    d = _incidents_dir(proj)
    target = os.path.join(d, incident_id + ".json")
    r = _load(target)
    if r is None or r.get("id") != incident_id:
        raise ValueError(f"no incident '{incident_id}' in rails/incidents/")
    rec = {
        "kind": "human_verdict",
        "incident_id": incident_id,
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "actor": actor,
        "verdict": status,
        "note": note,
    }
    n = 1
    path = os.path.join(d, f"{incident_id}.verdict-{n}.json")
    while os.path.exists(path):
        n += 1
        path = os.path.join(d, f"{incident_id}.verdict-{n}.json")
    with open(path, "w") as f:
        json.dump(rec, f, indent=2)
    return path


def unlinked(proj):
    """Return a list of (id, path) for incidents lacking a linked_case.
    Human-verdict appends are NOT incidents and never read as unlinked."""
    out = []
    for p in sorted(glob.glob(os.path.join(_incidents_dir(proj), "*.json"))):
        r = _load(p)
        if r is None:
            out.append((os.path.basename(p), p))  # unreadable == unaccounted
            continue
        if r.get("kind") == "human_verdict":
            continue
        lc = r.get("linked_case")
        if not lc or not str(lc).strip():
            out.append((r.get("id", os.path.basename(p)), p))
    return out


def _main(argv):
    if len(argv) >= 2 and argv[1] == "record":
        if len(argv) < 9 or len(argv) > 11:
            print("usage: incident.py record <proj> <dispatch> <trigger> "
                  "<check> <claimed> <observed> <tree_hash> "
                  "[hypothesized_mechanism] [minimal_repro]", file=sys.stderr)
            return 2
        proj, dispatch, trigger, check, claimed, observed, tree_hash = argv[2:9]
        hyp = argv[9] if len(argv) > 9 else ""
        repro = argv[10] if len(argv) > 10 else ""
        if trigger not in VALID_TRIGGERS:
            print(f"unknown trigger '{trigger}'", file=sys.stderr)
            return 2
        path = record(proj, dispatch, trigger, check, claimed, observed,
                      tree_hash, hyp, repro)
        print(path or "(duplicate; not re-recorded)")
        return 0
    if len(argv) >= 6 and argv[1] == "verdict":
        proj, incident_id, status, actor = argv[2:6]
        note = " ".join(argv[6:])
        try:
            path = verdict(proj, incident_id, status, actor, note)
        except ValueError as e:
            print(e, file=sys.stderr)
            return 2
        print(path)
        return 0
    if len(argv) == 3 and argv[1] == "check":
        proj = argv[2]
        miss = unlinked(proj)
        if miss:
            print("UNLINKED INCIDENTS (set linked_case to the eval case that "
                  "now covers each, then re-run the eval):", file=sys.stderr)
            for iid, p in miss:
                print(f"  {iid}  ({os.path.relpath(p, proj)})", file=sys.stderr)
            return 1
        return 0
    print(__doc__.strip().splitlines()[0], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
