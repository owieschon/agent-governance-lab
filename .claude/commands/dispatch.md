---
description: Turn inbox specs/constraints/DoDs into a structured dispatch, then stop for human approval
---

You are creating a dispatch: the unit of work this repo's rails run on.
Arguments (may be empty, may name a task or an inbox file): $ARGUMENTS

Steps:

1. Read EVERYTHING in `rails/dispatches/inbox/` plus anything named in the
   arguments. These are the human's specs, constraints, and definitions of
   done. Read `rails/dispatches/TEMPLATE.md` for the required shape.

2. If the material is ambiguous on anything that would change the manifest
   (which path ships, what the required behavior is, what counts as
   done), ask the human now. Do not guess proof obligations.

3. Create `rails/dispatches/active/<id>/` where `<id>` is
   `D-YYYY-MM-DD-<short-slug>`. Write:
   - `dispatch.md` following the template, including a filled-in blast-radius
     judgment (verifier hardness, blast radius, boundaries approached) with
     your recommended verdict. The human makes the final call.
   - `manifest.json` with concrete `live_path_greps`, `load_bearing_tests`,
     and a non-empty `break_plan`. Write the actual patch files under
     `breaks/`. The break plan is the proof design: for each behavioral
     claim the task makes, design the break that should turn a test red.
     Optionally set `"type"` (e.g. feature/fix/refactor) and `"subsystem"`
     (the contract surface touched) -- one word each; they travel into every
     durable record this dispatch produces (verdicts, incidents, stats,
     adjudications), so a year-later read of the ledger can segment by them.
   - Move (do not delete) the consumed inbox files into the dispatch dir
     under `sources/`.

4. Wrong-repo tripwire. Read `scope` from `rails/config.json`. State, in one
   line, why THIS problem belongs in THIS repo, alongside the repo name and
   `git remote get-url origin`. If the problem does not match the scope line,
   say so plainly and ask for confirmation before continuing -- a mismatch is
   a flag requiring the human's call, not a hard block.

5. Size check. If the manifest would carry more than 3 `live_path_greps` or
   more than 5 `break_plan` items, propose splitting it into sequential
   dispatches and present that split BEFORE asking for approval. The human
   can override and keep it whole.

6. STOP and surface for review IN CHAT: the problem, the DoD, the proof
   obligations, the blast-radius verdict, any boundary approached, the
   one-line scope justification, and (if triggered) the proposed split. Do
   not implement anything.

   The human's explicit approval in chat is the release. On approval, YOU
   execute it: create `rails/dispatches/active/<id>/APPROVED` (one line
   quoting the approval), then run `bash rails/verifier/snapshot.sh <id>` to
   freeze the approved manifest and the test/fixture hashes (verify.sh checks
   the live manifest against this freeze, so a later manifest amendment must go
   back through approval, which re-snapshots) and `bash rails/verifier/basis.sh
   <id>` to record the base commit (HEAD before you build) so the verifier can
   tie the break plan and live-path greps to the code the dispatch actually
   changes, and proceed to /go.

Hard rules:
- A dispatch without a break plan is not a dispatch.
- Where the problem admits more than one credible solution shape, the
  dispatch names the alternatives and why the chosen direction wins at
  spec level; finer-grained choices land in DECISIONS.md during /go.
  Manifests carry `"decisions_required": true` by default; only the
  human flips it for genuinely trivial work.
- If the task's correctness is a judgment call rather than a test outcome,
  or it must change a safety-critical invariant, recommend KEEP IN HUMAN
  HANDS and say why.
- New tests you plan to write should be listed in `load_bearing_tests`.
  After they exist and the human agrees they should gate future work, the
  HUMAN adds them to `rails/verifier/load_bearing.txt`. You cannot, by design.
