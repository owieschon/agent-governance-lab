# Dispatch: <id>

> One dispatch = one rails-worthy task. A dispatch is rails-worthy only if it
> passes the human judgment gate: it has a hard verifier AND a bounded blast
> radius. If either is missing, it stays in human hands and never becomes a
> dispatch.

## Problem
What is wrong or missing, in one paragraph. Link or quote the inbox sources
this came from (specs, constraints, tickets).

## Desired outcome
The end state, stated as observable behavior, not implementation.

## Definition of done
Done = ALL of (green + count >= baseline + live-path proven + demonstrated-red):
1. Full suite runs to completion, exit 0, count >= baseline.
2. The named load-bearing tests collected and ran by name.
3. Live-path greps prove the new code runs in the path that ships.
4. Demonstrated-red: each break in the plan turns its test red, and green
   again after restore.
Plus the task-specific criteria below:
- [ ] <criterion 1>
- [ ] <criterion 2>

## Constraints
Anything the implementation must not do: APIs that must not change,
invariants that must hold (e.g. fact gates, eval isolation), performance
or dependency constraints.

## Blast radius (the human judgment gate, filled by human)
- Verifier hardness: hard / soft -- why
- Blast radius: bounded / large -- why
- Boundaries this task approaches (what the guards block; the
  governor-change trigger): none / list them
- Verdict: RAILS-WORTHY / KEEP IN HUMAN HANDS

## Notes
Anything else the loop needs: pointers into the codebase, prior art,
naming, gotchas.

---

`manifest.json` (sibling file) carries the machine-readable proof
obligations. Skeleton:

```json
{
  "id": "<id>",
  "decisions_required": true,
  "live_path_greps": [
    { "pattern": "new_function\\(", "path": "src/entrypoint_or_pipeline.py" }
  ],
  "load_bearing_tests": [
    "tests/test_new_behavior.py::test_the_specific_claim"
  ],
  "break_plan": [
    {
      "desc": "bypass the new guard",
      "files": ["src/the_module.py"],
      "apply": "patch -p1 < rails/dispatches/active/<id>/breaks/bypass.patch",
      "expect_fail_cmd": "pytest tests/test_new_behavior.py -q"
    }
  ]
}
```

Rules for the manifest:
- `break_plan` may not be empty. A dispatch with no way to demonstrate red
  has no proof.
- `apply` may be a `patch` invocation (patch files live in `breaks/` next to
  this file) or a `sed -i` one-liner. It must touch only the files listed in
  `files` (the verifier backs up and restores exactly those).
- `expect_fail_cmd` is the targeted test command. It must be green before
  the break and red after, or the check fails.
- `live_path_greps` must point at the SHIPPING path (the entrypoint,
  pipeline, or route), not at the test file.
