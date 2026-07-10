# Operating the rails

The daily shape: you spend your time at two points, approving the dispatch and
reviewing the handoff (release). Everything between is the loop inside the rails.

## The cycle

1. **Drop.** Drag specs, constraints, DoDs, tickets, design notes into
   `rails/dispatches/inbox/`. Any format; the dispatcher reads them all.

2. **Dispatch.** Run `/dispatch`. Claude turns the inbox into
   `rails/dispatches/active/<id>/` with a dispatch.md, a manifest.json
   carrying the proof obligations (live-path greps, required tests,
   break plan), and patch files for the breaks. It then stops.

3. **Approve.** Read the dispatch summary in chat. Make the rails-worthiness
   call yourself: hard verifier? bounded blast radius? boundaries approached?
   Does the problem match the repo's `scope` line? If yes, say so; your
   explicit chat approval is the release, and the loop records `APPROVED` and
   proceeds. If no, say no and it does not build. The decision is yours; the
   loop handles the keystrokes.

4. **Go.** Run `/go` and walk away. It runs `doctor.sh` first and stops if
   the install is unhealthy. Then the loop writes failing tests, builds,
   runs the verifier, iterates. The session cannot end without a fresh PASS
   verdict or an explicit BLOCKED declaration.

5. **Review the handoff.** It reads as a standalone change report: summary,
   scope, decisions with trade-offs, verification evidence, risks and
   follow-ups. Approve in chat and the loop executes the release for you:
   commit (conventional form, dispatch id + evidence path on the trailer),
   push if you ask, report the hash, `remote_ref.sh <branch>` to confirm it
   landed, and archive the dispatch dir. The proposals that need your hands
   (dependencies, migrations, a baseline SHRINK) it names, it does not do.
   `/status` shows the live picture any time.

6. **Promote tests.** If the dispatch produced tests worth gating all
   future work on, add their paths to `rails/verifier/load_bearing.txt`.
   Only you can; the agent cannot edit its own judge.

## The reviewer (optional, config-gated, OFF by default)

With no `reviewer_model` key in `rails/config.json`, the handoff is exactly
what it was before the reviewer existed: zero new output, zero spend. A
second model's cost is your budget call, so the kit keeps working
single-model with the reviewer off until you add the key
(`"reviewer_model": "<model id>"`).

With the key set, `/handoff` launches the read-only reviewer subagent
concurrently while the report is written. Its findings render INTO the
handoff doc, capped to fit your existing read: three lines -- contract
failures first (severity-ordered), then judgment observations, never
interleaved -- then "N more in artifacts"; the full report lands in
`rails/evidence/<id>/review_findings.md`. Re-rendering is a read: it never
respawns the reviewer or overwrites the findings. If the reviewer
errors, times out, or the model is down, the doc carries one line --
`review: unavailable` -- and the handoff proceeds; a hung reviewer is killed
(it can never stall the pipeline, and the verifier never reads its output:
cases 32 and 43-45 prove both directions). On demand: `rails review <id>`
(an alias; the primary path needs no verb).

Flag a wrong finding at the handoff gate:

    python3 rails/verifier/adjudicate.py flag . <id> reviewer_false_positive "<finding title>"

The flag rides the same append-only adjudication stream as everything else
and records the reviewer's wrong findings (a rendered trend view over them is
future work, not yet computed). Feeding it back into reviewer prompting is
forbidden: the corpus informs you, it never trains the claimant (case 46
grep-proves no read-back exists). Calibrate your weight on findings
accordingly. The best monitor AUC in SHADE-Arena is ~0.87 (that number is from
SHADE-Arena's setting, not a measurement of this reviewer), so expect misses.

## Outer loops: observers (event-initiated intake)

An observer is an outer loop pointed at the world instead of the repo:
Sentry issues, failed CI runs, dependency advisories, the kit's own decay.
It is find-don't-fix turned outward, feeding the SAME human-gated pipeline:
observers file proposals into `rails/dispatches/inbox/`, you approve at
`/dispatch`, the inner loop implements. The dispatch gate does not move.

### Rules (guard-enforced)

- An observer's ONLY write privilege is creating NEW files in
  `rails/dispatches/inbox/` and its own state under
  `rails/observers/state/`. Existing inbox items are create-only for EVERY
  agent: never edited, overwritten, renamed, or deleted (cases 47-49 prove
  the guards; the runner honors the same law structurally).
- An observer never implements, never edits code, never runs `/go`, never
  touches `rails/verifier/`, hooks, evidence, incidents, or existing inbox
  items. `rails/observers/` itself (definitions, runner, transforms) is
  agent-read-only -- governor-adjacent, because it shapes what you see at
  the approval gate. You edit definitions; agents cannot.
- Every filed item is templated: source, the trigger that fired, an
  evidence REFERENCE (link or id, never bulk-pasted payloads), a one-line
  problem statement, and a SUGGESTED-PRIORITY line. Items are suggestions
  only.
- Rate limit: at most 3 items per observer per run; overflow is carried in
  state for the next run, never dropped. A noisy source must not flood the
  inbox. Dedup state means the same finding never files twice.
- Credentials are ENV VARS ONLY and never written to any file by any code
  path; a definition file carries the env var NAME only. A missing
  credential (or missing tool, or failing query) is a silent-and-logged
  skip -- exit 0, one line in `rails/observers/state/<name>.log` -- so a
  scheduled run never breaks because a key is absent.

### Running and adding observers

    bash rails/observers/run_observer.sh <name> [--dry-run]

Shipped: `sentry`, `phoenix`, `langsmith`, `posthog` (SaaS -- `--dry-run`
works out of the box from `rails/observers/fixtures/`, no credentials, no
network), `ci` (GitHub Actions via `gh`), `deps` (pip-audit / npm audit vs
lockfiles; it NEVER auto-updates -- every advisory becomes a proposal),
`drift` (weekly self-check: doctor result, baseline age, stamp age,
unlinked incidents -- files only on a failing/stale condition).

To add one: write `rails/observers/<name>.json` (keys documented at the
top of `run_observer.sh`: source, trigger, `query_cmd` emitting candidate
JSONL, `dedup_field`, `rate_limit`, `env_var` NAME, optional `fixture`),
dry-run it against a fixture first, then add a schedule line. Trigger
thresholds live in `rails/observers/extract.py`.

### Proposed schedules (PROPOSED ONLY -- the kit never installs these)

You choose which observers to enable and on what schedule; export the
tokens in the scheduler's environment, never in a file. Rotation
discipline matters double once tokens sit in a cron environment. Example
crontab lines (launchd users: wrap the same command in a LaunchAgent
plist with the env vars in `EnvironmentVariables`):

    # every 15 min: CI failures on main (cheapest, highest value)
    */15 * * * * cd /path/to/repo && bash rails/observers/run_observer.sh ci
    # hourly: production error/trace observers (tokens from the cron env)
    0 * * * *    cd /path/to/repo && bash rails/observers/run_observer.sh sentry
    20 * * * *   cd /path/to/repo && bash rails/observers/run_observer.sh phoenix
    # weekly: advisories + the kit watching its own decay
    0 9 * * 1    cd /path/to/repo && bash rails/observers/run_observer.sh deps
    30 9 * * 1   cd /path/to/repo && bash rails/observers/run_observer.sh drift

### Anti-patterns (each with its ground)

- **No observer-to-/go path.** An observer that triggers implementation
  collapses the human dispatch gate. Observers propose; only your approval
  builds.
- **No observer edits rails/.** Guard-enforced (cases 47/49). An outer
  loop that can rewrite the verifier, the guards, or its own definitions
  lets the governor modify itself over the network.
- **No meta-loop** (observers that create observers). A definition under
  `rails/observers/` is governor-adjacent; observers spawning observers lets
  the governor modify itself, and it un-bounds the volume the rate limit bounds.
- **Fail safe to the human.** A broken observer logs and exits 0; it never
  invents work, never blocks the pipeline, never errors a cron run into
  silence. When in doubt the failure shape is "a line in the state log a
  human reads", not "an action".

### Push surfacing: notify

`rails/notify/notify.sh <event> <artifact-path>` sends ONE Telegram line
per event -- repo, event, artifact path; no payloads, no diffs, no secrets.
Default OFF (`notify.enabled: false` in `rails/config.json`), so
token-less installs are untouched. To enable: flip `enabled`, then export
`TELEGRAM_RAILS_BOT_TOKEN` and `TELEGRAM_RAILS_CHAT_ID` -- env vars only,
never in a file, and the token must belong to a DEDICATED bot created for
rails (never reuse another bot's token). Wired today: `observer_filed`
(batched, one message per observer run) and `stamp_invalidated` (detected
on doctor.sh's existing fingerprint-vs-stamp check -- verify.sh, the gate,
never calls notify by design; case 50 proves it). The remaining events in
the config list are reserved hook points, not yet wired.

## Driving the loop: Stop gate vs /goal vs /loop

Three mechanisms, layered:

- **The Stop gate (this kit) is the primary driver.** It is deterministic:
  exit code of verify.sh against the current tree hash. No model judges
  done-ness. This is the framework's core demand (exogenous verifier) and
  it works on any Claude Code version with hooks.

- **/goal is optional.** Native Claude Code: set a completion condition and
  Claude keeps working turn after turn, with a small evaluator model checking
  the transcript. Useful for a turn/effort envelope on top of the gate. If
  you use it, make the condition point at the exogenous check:

      /goal bash rails/verifier/verify.sh D-2026-06-09-x exits 0 and
      rails/handoff/D-2026-06-09-x.md exists. Do not modify anything
      under rails/verifier/.

  Remember its limit: the evaluator only judges what Claude surfaced in
  the conversation. The Stop gate does not have that limit, which is why
  it stays primary.

- **/loop is for recurrence, not completion.** It re-runs a prompt on a
  time interval. Use it for drift detection, not building:

      /loop run /verify and summarize any check that changed since the
      last run

  every night against a long-lived branch, or a periodic triage pass over
  the issue tracker. /goal = until-done; /loop = on-a-schedule. Different
  mechanisms; do not swap them.

## Where dynamic workflows fit: find, don't fix

Dynamic workflows are Claude writing a JavaScript orchestration script
that fans tens to hundreds of subagents out in parallel, in the
background, with the script (not the conversation) holding the plan.
That is leverage with one catch the framework already names: subagents in a
workflow run with edits auto-approved. So the rule is:

**Workflows get read-heavy, find-don't-fix jobs. Dispatches get the fixes.**

Good workflow jobs (run them on a branch you can discard, or before
approving a dispatch):

- **Adversarial review of a handoff.** Before you commit a big diff:

      ultracode: review the diff currently in my working tree against
      rails/dispatches/active/<id>/dispatch.md. Fan out independent
      reviewers for correctness, for security, for the constraints
      section, and for whether the live-path greps in manifest.json
      actually cover the shipping path. Have a second wave try to refute
      each finding. Report only findings that survive, with file:line.
      Do not edit any file.

- **Codebase-wide audits** (auth checks, error handling, invariant
  usage) whose findings become inbox items, which become dispatches.

- **Plan drafting from independent angles** before you write a big
  dispatch, so the manifest's break plan covers the real failure modes.

When a workflow run is good, save it (`/workflows`, select, press `s`) to
`.claude/workflows/` so the whole repo gets the same orchestration as a
command, and consider pairing the triage ones with /loop.

What workflows must never do here: edit code on your working branch,
touch rails/, or "fix while auditing." A generator that both finds and
patches can weaken the safety layer it is auditing.

## Cost discipline

Workflows and /goal both consume meaningfully more tokens than
conversational work. Gauge a workflow on a small slice first (one
directory, one question). Set token budgets in the prompt ("use 10k
tokens"). For routine dispatches, plain /go with the Stop gate is the
cheapest loop you have.

## When the verifier is wrong

It happens: a check is too strict, a baseline is stale, a grep pattern
rotted. The agent will tell you (it is instructed to recommend, never
edit). You edit `rails/verifier/`, you re-run, and the change is visible
in git history. Every weakening of the trust layer is a human act with a diff.

## Proving the governor: the adversarial eval

The trust layer is itself code, so it gets a known-bad suite that proves every
check fires. `bash rails/adversarial/run_eval.sh`
builds disposable sandboxes running your repo's ACTUAL trust-layer files,
injects one violation per known class (weaken-a-check first), asserts the
relevant gate fires, and asserts clean work is not false-positived. On a
full pass it stamps `rails/adversarial/registry.json` with the governor's
fingerprint.

The `governor_proven` check makes verify.sh refuse to certify any dispatch
when the trust layer's fingerprint differs from the last proven one, or the
recorded environment changed. The re-proof triggers are a gate, not a calendar
reminder:

- **Framework change**: you edit a check or a hook -> every dispatch
  fails `governor_proven` until you re-run the eval. The change literally
  does not take force unproven.
- **Environment change**: the registry records the Python, bash, and Claude
  Code versions at proof time; a recorded change closes the gate the same
  way. The bash version matters because the whole trust layer is bash and
  the kit runs on stock-macOS bash 3.2; a proof produced under one shell
  does not silently gate work run under another.
- **New failure mode**: something broken-but-green escaped -> run
  `bash rails/adversarial/accrete.sh <slug>` and write the case. The
  template fails until written, keeping the register honest. The health
  metric: every past escape has a case that would catch it today. Agents
  propose new cases in handoffs; only you accrete them, because the eval
  is part of the governor and the agent cannot touch the governor.

It runs locally in seconds and burns no tokens. The eval found three real
holes in this kit's own first version: forgeable verdicts, softenable test
commands, and a stale-bytecode false green inside demonstrated-red.

## Changing the governor

Changing the governor is the highest-blast-radius edit there is. Two rules
hold:

1. **The trust layer is agent-read-only.** The guards block the loop from
   editing `rails/verifier/`, `.claude/hooks/`, settings, and
   `rails/adversarial/`. The agent states the change it wants; you make it.
2. **A changed governor certifies nothing until re-proven.** If the
   trust-layer fingerprint differs from the one stamped at the last full
   eval pass, `verify.sh` refuses to certify dispatches until
   `bash rails/adversarial/run_eval.sh` passes again and re-stamps.

Reviewing the governor diff before you make it is your judgment; there is no
mechanical release ceremony. Read removals harder than additions: a removed
`deny()` or a removed eval case is the governor getting weaker.

### Reading the log

`GOVERNOR_LOG.md` (repo root) is the append-only historical ledger of
releases made while the release ceremony existed (it was retired 2026-06-12
by operator decision). The agent cannot edit past lines.

## clean_room: the pre-merge posture

`verify.sh` has a `clean_room` mode -- set `RAILS_CLEAN_ROOM=1` -- that re-runs
the suite in a fresh `git worktree` at HEAD (committed state only, no
working-tree files or caches) and requires the same pass count. It catches a
green that depends on an uncommitted file, a cache, or a stale build product.
It is OFF by default because it **doubles suite time**: it is the pre-merge / CI
posture, not the inner-loop one. Turn it on in your CI verify step (a repo's CI,
not the kit's eval, which already proves the check via case 17).
