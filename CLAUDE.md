<!-- 3XIT2 BEGIN (do not edit inside this block by agent) -->
# Operating rules: 3xit2

This repo runs dispatch-driven agent development. The loop proposes and
iterates; the verifier judges; the human releases.

## How work flows
- Work comes from dispatches in `rails/dispatches/active/<id>/`
  (dispatch.md + manifest.json). No dispatch, no autonomous building.
- `/dispatch` creates one from `rails/dispatches/inbox/`. `/go` runs the
  loop. `/verify` runs the verifier. `/handoff` packages for review.
  `/status` is a read-only dashboard.
- Approval is the human's explicit chat decision. On it, the loop records
  `APPROVED` in the dispatch dir (quoting the approval) and proceeds. No
  approval, no autonomous building.

## Definition of done (no exceptions)
green AND grep-proves-the-tested-code-is-on-the-live-path AND
demonstrated-red. `bash rails/verifier/verify.sh <id>` is the only judge of
done. The session cannot end mid-dispatch without a fresh PASS or a
`rails/handoff/<id>.BLOCKED.md`.

## Boundaries (hook-enforced; do not attempt, do not work around)
- No merge, push, force-push, rebase, amend, hard reset, history rewrite
  inside the build loop.
- No commits inside the build loop: it stops at the commit boundary and
  produces the handoff. Committing is a release act (see Release below).
- No HEAD-moving git ops (checkout/switch/reset/stash/clean) while
  unpushed or uncommitted work exists. Build on top of HEAD.
- No dependency adds/changes, no schema or data migrations, nothing that
  spends money, touches production, or contacts third parties. Propose
  these in the handoff.
- `rails/verifier/`, `.claude/hooks/`, settings files, `rails/adversarial/`,
  and every file in `rails/verifier/load_bearing.txt` are read-only to you.
  You may ADD tests in new files; you may never weaken or edit a gating check.
  If a check is wrong, say what should change; the human edits.
- `rails/incidents/` is append-only: write a NEW record, never edit or delete
  an existing one (a human links each to its eval case).

## Release
The human's job is the decision; executing it is yours. Surface the review
materials in chat (diff, DECISIONS.md, verifier verdict), STOP, and wait for
an explicit approval. On approval YOU execute: commit, push if asked, report
the hash. If execution fails, STOP and surface it; do not improvise.
- Commit format: conventional-commit subject (`type(scope): summary`), the
  dispatch id in the body, and the evidence path on a trailer line:

      feat(parser): handle quoted catalog ids

      Dispatch: D-2026-06-09-quoted-ids
      Evidence: rails/evidence/D-2026-06-09-quoted-ids/verdict.json

- The one execution-level act that stays human-only: LOWERING the test-count
  baseline (`--update-baseline --allow-shrink`) is the test-deletion
  laundering path. Raising the floor after approved work is delegable;
  report a needed shrink in the handoff for the human to run.
- Governor changes (`rails/verifier/`, `.claude/hooks/`, settings,
  `rails/adversarial/`) are human-made: the trust layer is agent-read-only,
  so you state exactly what should change and the human edits. A changed
  governor does not gate work until `bash rails/adversarial/run_eval.sh`
  passes again and re-stamps.

## Engineering judgment (senior-engineer standard)
Method is required even where it cannot be machine-graded; its disclosure
is machine-enforced (the `decisions` check).
- Before implementing anything non-trivial, write DECISIONS.md in the
  dispatch dir: for each consequential choice record Context, Options
  considered (at least two where two exist), Trade-offs, Choice & grounds,
  Reversibility. One paragraph each; this is an ADR, not an essay.
- Prefer the boring choice: smallest diff that meets the DoD, stdlib over
  dependency, data structure over cleverness, deletion over abstraction.
  Justify any departure in DECISIONS.md.
- Design for reversibility; when two options tie, take the one that is
  cheaper to undo.
- Handle errors at boundaries explicitly; no silent catches; failure
  modes named in DECISIONS.md when they are part of the trade-off.
- Name the blast radius of what you touch. If it grew past the dispatch's
  stated bound, that is a boundary event, not a footnote.
- Comments and the handoff explain WHY, not what. Confidence is stated
  with grounds; unfounded confidence in a handoff is an inflation
  violation.

## Disciplines
- Write the failing test before the code.
- A check that never met its condition proves nothing; not-exercised is not
  a pass.
- Never report committed/pushed as fact; the human verifies against the remote.
- Adversarial review (workflows, audits) surfaces failures; fixes go through a
  dispatch. When the adversarial eval or any audit finds a governor gap, you
  propose; the human edits and re-proves.
- Three failed attempts at the same check means write the BLOCKED file, not
  another workaround.
<!-- 3XIT2 END -->
