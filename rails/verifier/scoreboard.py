#!/usr/bin/env python3
"""
scoreboard.py <root>  -- program-level scoreboard (read-only).

The numbers here are aggregates over an append-only event ledger
(rails/evidence/: one verdict.json per dispatch + stats.jsonl) plus the
incident ledger -- which is exactly the shape SQL expresses best. So the
loaders below pull the JSONL/JSON into three in-memory tables and the metrics
are computed by the query in METRICS_SQL: completion count, first-pass verify
rate, and mean iterations-to-green, as group-by / conditional aggregation over
those rows.

sqlite3 is used deliberately: it ships in the Python standard library, so the
kit stays zero-dependency (no DuckDB/Postgres, nothing to install) while the
aggregation reads as plain SQL rather than hand-rolled dict counting. The data
is small; the point is legibility of the metric definitions, not scale.
"""
import glob
import json
import os
import re
import sqlite3
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
sys.path.insert(0, os.path.join(ROOT, "rails", "verifier"))
try:
    import freshness
except Exception:
    freshness = None


def _load_queries():
    """The metric SQL lives in scoreboard_metrics.sql (a first-class, readable
    artifact), split into named sections by `-- name: <key>` lines."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "scoreboard_metrics.sql")
    queries, name, buf = {}, None, []
    for line in open(path).read().splitlines():
        m = re.match(r"--\s*name:\s*(\w+)\s*$", line)
        if m:
            if name:
                queries[name] = "\n".join(buf).strip()
            name, buf = m.group(1), []
        elif name:
            buf.append(line)
    if name:
        queries[name] = "\n".join(buf).strip()
    return queries


Q = _load_queries()


def _load_json(path):
    try:
        return json.load(open(path))
    except Exception:
        return None


def _build_db():
    """Pull the ledgers into an in-memory SQLite DB: one row per fact."""
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    db.executescript(
        """
        CREATE TABLE verdicts  (dispatch TEXT PRIMARY KEY, status TEXT);
        CREATE TABLE runs      (dispatch TEXT, source TEXT, iteration INTEGER);
        CREATE TABLE incidents (id TEXT, trigger TEXT, dispatch TEXT, linked_case TEXT);
        """
    )

    # latest verdict per dispatch (one verdict.json per dispatch dir; the
    # PRIMARY KEY upsert keeps the last one read, matching prior behavior)
    for p in glob.glob(os.path.join(ROOT, "rails", "evidence", "*", "verdict.json")):
        v = _load_json(p)
        if v and v.get("dispatch"):
            db.execute(
                "INSERT OR REPLACE INTO verdicts(dispatch, status) VALUES (?, ?)",
                (v["dispatch"], v.get("status")),
            )

    # every gate rejection, append-only (verify.sh / gate_stop.py write these)
    try:
        with open(os.path.join(ROOT, "rails", "evidence", "stats.jsonl")) as f:
            for ln in f:
                ln = ln.strip()
                if not ln:
                    continue
                try:
                    r = json.loads(ln)
                except Exception:
                    continue
                db.execute(
                    "INSERT INTO runs(dispatch, source, iteration) VALUES (?, ?, ?)",
                    (r.get("dispatch"), r.get("source"), int(r.get("iteration", 0))),
                )
    except Exception:
        pass

    # incident ledger; human_verdict appends are verdicts ON incidents, not
    # incidents themselves -- skip them so the count cannot contradict the
    # incident.py gate (same exclusion the gate applies).
    for p in glob.glob(os.path.join(ROOT, "rails", "incidents", "*.json")):
        i = _load_json(p)
        if not i or i.get("kind") == "human_verdict":
            continue
        db.execute(
            "INSERT INTO incidents(id, trigger, dispatch, linked_case) VALUES (?, ?, ?, ?)",
            (i.get("id"), i.get("trigger"), i.get("dispatch"), i.get("linked_case")),
        )
    return db


# The metric SQL lives in scoreboard_metrics.sql (loaded into Q above): one
# grouping yields completion count, first-pass rate, and mean iterations-to-green;
# a second counts incidents and how many are still unlinked.
METRICS_SQL = Q["metrics"]
INCIDENTS_SQL = Q["incidents"]
UNLINKED_SQL = Q["unlinked"]


def main():
    db = _build_db()
    m = db.execute(METRICS_SQL).fetchone()
    n_done = m["n_done"] or 0
    first_pass = m["first_pass"] or 0
    mean_iters = m["mean_iters"] or 0.0

    inc = db.execute(INCIDENTS_SQL).fetchone()
    n_incidents = inc["n_incidents"] or 0
    unlinked = db.execute(UNLINKED_SQL).fetchall()

    archived = [d for d in glob.glob(os.path.join(ROOT, "rails", "dispatches", "archive", "*"))
                if os.path.isdir(d)]

    print("==================== 3xit2 scoreboard ====================\n")
    print(f"  dispatches completed (PASS verdict):  {n_done}")
    print(f"  dispatches archived:                  {len(archived)}")
    # Cold-start (L10): a rate over a thin sample is not meaningful -- 100%
    # first-pass over one dispatch says nothing. Raw COUNTS are always honest;
    # derived RATES appear only past the meaning threshold, else a
    # forward-pointing line (never a misleading number or a sad n/a).
    if freshness and not freshness.meaningful(n_done):
        print("  first-pass verify rate:               "
              + freshness.state(n_done, "a first-pass rate"))
        print("  mean iterations to green:             (same -- needs more completed dispatches)")
    else:
        print(f"  first-pass verify rate:               {first_pass}/{n_done} "
              f"({100*first_pass//n_done}%)")
        print(f"  mean iterations to green:             {mean_iters:.2f}")
    print()
    print(f"  incidents recorded:                   {n_incidents}")
    if n_incidents == 0:
        print("  accretion status:                     clear (no incidents)")
    elif unlinked:
        print(f"  accretion status:                     {len(unlinked)} UNLINKED "
              "(governor will not re-stamp until linked)")
        for i in unlinked:
            print(f"      - {i['id'] or '?'} [{i['trigger'] or '?'}] dispatch={i['dispatch'] or '?'}")
    else:
        print("  accretion status:                     clear (all incidents linked to cases)")
    print()


if __name__ == "__main__":
    main()
