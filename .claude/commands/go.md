---
description: Run the build loop against the approved dispatch until the verifier says PASS
---

Run the rails loop. Arguments (optional dispatch id): $ARGUMENTS

Preconditions, check them first:
- Exactly one dispatch dir in `rails/dispatches/active/` (or the one named
  in the arguments) and it contains the `APPROVED` marker (the recorded
  human release). No marker = not approved = stop and say so.
- Run `bash rails/verifier/doctor.sh`. If any item FAILs, STOP and surface
  it -- a dispatch built on an unhealthy install cannot certify anything.
  Repair the install (or hand back to the human) before building.

Then loop, fully autonomously, inside these rails:

1. Read `dispatch.md` and `manifest.json` for the dispatch. Plan briefly.
2. Write `DECISIONS.md` in the dispatch dir BEFORE implementing: every
   consequential choice gets Context, Options considered, Trade-offs,
   Choice & grounds, Reversibility (the senior-engineer standard in
   CLAUDE.md). The verifier's `decisions` check requires it.

   Drift containment (no silent departures):
   - Any decision made MID-DISPATCH is written to DECISIONS.md at the MOMENT
     it is made -- stating the original plan, the departure, and, if it came
     from the human, a verbatim quote of their approval. Not deferred to the
     handoff; written when it happens.
   - If a decision changes the manifest (live paths, load-bearing tests,
     break plan), STOP and surface a manifest amendment for re-approval.
     Absorbing a manifest change silently is a violation.
   - After ANY stopping-point discussion (a question answered, a decision
     taken, an amendment approved), your FIRST act on resume is a three-line
     restatement in chat: (1) the original dispatch goal, (2) the decision
     just made, (3) the next action. Do this before touching code.
3. Write the load-bearing tests FIRST (new files; you cannot edit existing
   load-bearing tests). Make them fail for the right reason before
   implementing: red before green, by construction.
4. Implement. Wire the new code into the live path named by the manifest's
   greps, not beside it.
5. Run `bash rails/verifier/verify.sh <id>`. Read the verdict (the default
   is one line; `bash rails/verifier/why.sh <id>` renders the full detail).
   Fix what failed. Repeat 4-5 until the verdict is PASS. Do not argue with
   the verifier and do not touch it; if you believe a check is wrong, that is
   a boundary event: write it up and declare BLOCKED.

   Adjudication at resolution (one question, asked once): whenever a gate
   fire or verify-FAIL needed the HUMAN to resolve it (they overrode,
   re-scoped, corrected the manifest, or judged the check wrong -- not your
   ordinary fix-and-rerun loop), ask them to adjudicate it in one word and
   record their answer verbatim:
       python3 rails/verifier/adjudicate.py record . <check> <id> \
           <true_catch|false_block|manifest_fault> [their note]
   true_catch = the check stopped real badness; false_block = the work was
   fine, the check was wrong or brittle; manifest_fault = the check fired
   correctly on a wrong manifest (not counted against the check). The checks
   are heuristics and fallible; this is how their precision is measured. You
   never adjudicate your own firings -- the answer is the human's, verbatim.
6. On PASS, immediately produce the handoff (follow
   `.claude/commands/handoff.md`), then stop.

The rails you are inside (these are enforced by hooks, not requests):
- No merge, push, rebase, amend, hard reset, force-anything.
- No commits inside the loop: it stops at the commit boundary and produces
  the handoff. The commit happens at the release step, after the human
  approves the handoff in chat -- then it is executed for them (CLAUDE.md).
- No HEAD-moving git ops while unpushed/uncommitted work exists.
- No dependency adds, no schema/data migrations: propose them in the
  handoff instead.
- `rails/verifier/`, `.claude/hooks/`, settings, and every file in
  `load_bearing.txt` are read-only to you.
- You cannot end the session while this dispatch is active unless the
  verifier verdict is a FRESH PASS or you have written
  `rails/handoff/<id>.BLOCKED.md` stating exactly what you need.

If you hit a wall three times on the same check, stop tunneling: write the
BLOCKED file with what you tried, what failed, and the decision or change
you need from the human.
