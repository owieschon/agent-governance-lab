---
name: rails
description: Orient in an 3xit2 repo -- report the current trust-layer state and the single next action. Use when the user asks "where am I", "what's the rails state", "what should I do next" in a repo that has 3xit2 installed, or types /rails.
---

# /rails — where am I, what next

You are orienting someone in a repo that runs the 3xit2 trust layer. Your
job is to answer two questions and nothing more: **what state is this repo in,
and what is the single next action.** Route to the existing commands; never
reimplement their logic, never dump the whole system.

## Do this

1. Run `bash rails/verifier/status.sh` and read it. That is the source of truth
   for state (governor proven?, active dispatches, blocked handoffs, incidents,
   precision/attention signals, last verdict). Do not recompute any of it.
2. Present the dashboard verbatim, then add ONE line: the single most important
   next action, chosen from the state. Use this precedence (first that applies):
   - governor NOT proven / fingerprint drift → `bash rails/adversarial/run_eval.sh`
   - an UNLINKED incident → a human links it to the eval case that covers it
   - a BLOCKED handoff → read it; it states what the human must decide
   - an active dispatch with a stale/missing PASS → `/go` (or `/verify`)
   - no config seeded yet (fresh repo) → `rails init`
   - nothing pending → suggest `/dispatch` on the next task, or `rails demo` if
     they have never seen a catch
3. If they ask to go deeper on any one thing, route them: `/status` (dashboard),
   `bash rails/verifier/why.sh <id>` (a verdict in full), `bash
   rails/verifier/scoreboard.sh` (program-level history), `rails receipt <id>`
   (a shareable receipt), `rails review <id>` → `bash
   rails/verifier/handoff_review.sh render <id>` (the reviewer's capped
   findings for a dispatch; config-gated, non-blocking). Answer the question
   they asked, scoped to it — never a data dump.

## Do not

- Do not modify anything; this is read-only orientation.
- Do not run the eval, commit, or any state-changing command on your
  own — name it as the next action and let the human choose.
- Do not explain concepts they have not asked about or hit yet. Name the next
  action; the rest is one question away when they reach for it.
