#!/usr/bin/env python3
"""
run_observer.py <root> <name> <def.json> <candidates> <ts> <filed-out>  --
the dedup + rate-limit + templating core of the observer runner (Job 4A).

An observer is an outer loop pointed at the world instead of the repo. Its
constitution (D59): the ONLY write privilege is creating NEW files in
rails/dispatches/inbox/ plus its own state under rails/observers/state/. This
never overwrites an existing inbox item (the create-only law guard_files
enforces on agents), never edits code, never touches the governor. Observers
PROPOSE; the human approves; the inner loop implements.

The shell (run_observer.sh) does the fail-safe-to-human prelude -- resolving
the definition, the requires_cmd / credential checks, fetching candidates (live
query or --dry-run fixture) -- and the push surfacing after. This stage takes
those candidates and the run's timestamp as argv, files up to the rate limit,
carries the rest as overflow, and writes the filed count to <filed-out> for the
shell. The body lives here rather than a bash heredoc so it reads and tests on
its own. Lives in the trust layer; not agent-editable.
"""
import hashlib, json, os, sys

root, name, defp, candp, ts, filedf = sys.argv[1:7]
d = json.load(open(defp))
dedup_field = d.get("dedup_field") or "id"
rate = int(d.get("rate_limit") or 3)
source = d.get("source", name)
trigger = d.get("trigger", "")

state_path = os.path.join(root, "rails", "observers", "state", name + ".json")
try:
    state = json.load(open(state_path))
except Exception:
    state = {}
filed_ids = state.get("filed", {})
overflow = state.get("overflow", [])

# queue: carried overflow first (oldest findings drain first), then new
# candidates; drop anything already filed or duplicated within the queue.
queue, seen, malformed = [], set(), 0
for c in overflow:
    if not isinstance(c, dict):
        continue
    k = str(c.get(dedup_field, ""))
    if k and k not in filed_ids and k not in seen:
        seen.add(k)
        queue.append(c)
for line in open(candp, errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        c = json.loads(line)
        k = str(c.get(dedup_field, ""))
    except Exception:
        malformed += 1
        continue
    if not k or k in filed_ids or k in seen:
        continue
    seen.add(k)
    queue.append(c)

inbox = os.path.join(root, "rails", "dispatches", "inbox")
os.makedirs(inbox, exist_ok=True)

# Every filed item is TEMPLATED: source, trigger that fired, raw evidence
# REFERENCE (link or id, never bulk-pasted payloads), the observer's one-line
# problem statement, a SUGGESTED-PRIORITY line. Items are suggestions only.
TEMPLATE = """# Observer proposal: {title}

- Source: {source} (observer: {name})
- Trigger: {trigger}
- Evidence: {evidence}
- Problem: {problem}
- SUGGESTED-PRIORITY: {priority}

Filed {ts} by rails/observers/run_observer.sh. A suggestion only: the human
dispatch gate decides; /dispatch consumes this file into a dispatch.
"""

filed_now, carried = 0, []
for c in queue:
    k = str(c.get(dedup_field))
    if filed_now >= rate:
        carried.append(c)  # overflow: carried in state, never dropped
        continue
    fn = "obs-%s-%s.md" % (name, hashlib.sha256(k.encode()).hexdigest()[:8])
    dest = os.path.join(inbox, fn)
    if os.path.exists(dest):
        # create-only, honored structurally: an EXISTING inbox item is never
        # overwritten (the guard law, mirrored). Mark filed so it never
        # re-queues; the human resolves the name collision if it matters.
        filed_ids[k] = ts
        continue
    body = TEMPLATE.format(
        title=str(c.get("title", k)), source=source, name=name,
        trigger=trigger, evidence=str(c.get("evidence", "")),
        problem=str(c.get("problem", "")),
        priority=str(c.get("priority", "P3")), ts=ts)
    with open(dest, "w") as f:
        f.write(body)
    filed_ids[k] = ts
    filed_now += 1

json.dump({"filed": filed_ids, "overflow": carried, "last_run": ts},
          open(state_path, "w"), indent=2)
extra = (", %d malformed candidate line(s) skipped" % malformed) if malformed else ""
with open(os.path.join(root, "rails", "observers", "state", name + ".log"), "a") as lg:
    lg.write("%s run: filed %d, overflow carried %d%s\n"
             % (ts, filed_now, len(carried), extra))
print("observer %s: filed %d item(s), %d carried in overflow"
      % (name, filed_now, len(carried)))
open(filedf, "w").write(str(filed_now))
