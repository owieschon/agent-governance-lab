---
description: Read-only operator dashboard -- active dispatches, blocks, incidents, governor, baseline, last verdict
---

Run `bash rails/verifier/status.sh` and present its output verbatim.

This is read-only: never modify anything. After the dashboard, if something
needs attention (an UNLINKED incident, a STALE pass, a NOT-PROVEN governor, a
missing baseline, a blocked handoff, an "under review" precision or default
signal, the rubber-stamp attention line), name the single most important next
action for the human -- one line, no speculation.

The signals section is a mirror, not a scoreboard. Forward note (recorded,
not built): aggregated over time these primitives would constitute
rigor-decay detection. The guardrail travels with the note: rigor-decay
signals are a mirror an operator chooses to look into, NEVER a number reported
up a hierarchy or wired to a gate or incentive. Do not build that aggregation;
if asked to, surface this guardrail first.
