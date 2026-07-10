---
description: Package the change as a standalone review report at the commit boundary, then stop for the human's review/commit decision
---

Produce the handoff for the active dispatch (or the one named): $ARGUMENTS

Preconditions: `rails/evidence/<id>/verdict.json` exists with status PASS.
If not, run /verify first; if it fails, fix it or declare BLOCKED instead.

Then, BEFORE writing the report, run
`bash rails/verifier/handoff_review.sh launch <id>` -- the reviewer (if one
is configured via `reviewer_model` in rails/config.json) works concurrently
while you write; when none is configured the call is silent and instant.

Write `rails/handoff/<id>.md` as a STANDALONE professional change report. A
reviewer, client, or interviewer should be able to read it cold. Sections,
in this exact order:

1. **Summary** -- the lead paragraph is a CONTRACT, not a style note: a PM
   or customer-success reader must be able to read it cold and learn (a)
   what was done, (b) whether it is verified, and (c) what that verification
   does and does not guarantee. 3-6 sentences, plain language, NO internal
   jargon (no "dispatch", "rails", "load-bearing", "demonstrated-red",
   "manifest", "governor" here). All evidence lives below the fold; none of
   it leaks into the lead.
2. **Scope** -- what this change touches and, explicitly, what it does NOT.
   Name the blast radius. List the files changed at a glance.
3. **Decisions** -- the consequential choices with their trade-offs: for each,
   the options considered, what was chosen, and why. Draw from DECISIONS.md;
   include any mid-course departures and the approval that authorized them.
4. **Verification evidence** -- how we know it works: the verifier verdict
   (status, tree hash, each check's result verbatim), the DoD checklist mapped
   item-by-item to its proof (a check, a log line, a grep hit), and the diff
   (`git diff --stat` plus `git status --short` for untracked; name the branch).
5. **Risks and follow-ups** -- what you are unsure about, what could break,
   and anything deferred: dependencies to add, migrations to run, verifier or
   gating-check changes proposed, boundary events. New eval cases you propose
   for any failure this surfaced go here.
6. **Review** -- only when a reviewer is configured: include VERBATIM the
   output of `bash rails/verifier/handoff_review.sh render <id>` (either the
   capped findings block -- full report in
   `rails/evidence/<id>/review_findings.md` -- or the single
   "review: unavailable" line). If it prints nothing, omit this section
   entirely. The review never blocks the handoff and the verifier never reads
   it; it is for the human's eyes. If the human calls a finding wrong, record
   it: `python3 rails/verifier/adjudicate.py flag . <id>
   reviewer_false_positive "<finding title>"` -- their words, never your
   paraphrase.

Then STOP and surface the report in chat for review.

Release: the human's explicit approval in chat is the release. When they
answer -- approve OR reject -- ask ONE
follow-up: "about how many minutes did this review take? (a number, or skip)"
and record their answer verbatim, never estimated, never filled in:

    python3 rails/verifier/adjudicate.py approval . <id> <yes|no> <minutes|skip>

(This is the denominator for the approval-fatigue signal in /status -- a
mirror for the human about their own attention, never a gate.)

On approval, YOU execute -- commit (conventional-commit format with the
dispatch id in the body and the evidence path on a trailer, per CLAUDE.md),
and if asked, push; then report the commit hash and, where relevant, confirm
landed with `bash rails/verifier/remote_ref.sh <branch>`. Render the receipt
(`bash rails/verifier/receipt.sh <id>`) and name its path. Finally move the
dispatch dir to `rails/dispatches/archive/`. If execution fails at any step,
STOP and surface it; do not improvise around it.
