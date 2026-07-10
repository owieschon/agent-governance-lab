# 3xit2 — a trust layer for your coding agent

[![prove](https://github.com/owieschon/3xit2_demo/actions/workflows/prove.yml/badge.svg)](https://github.com/owieschon/3xit2_demo/actions/workflows/prove.yml)

**Status: working prototype / experiment.** It installs, its own test suite
runs green, and it does what this README says for the threat model described
under [Limitations](#limitations-read-this). It is not a security sandbox and
not a finished product. A self-audit of where it holds and where it does not
lives in [`AUDIT.md`](AUDIT.md); read it before trusting any guarantee here.

## The problem

When you let a coding agent run on its own, two things tend to go wrong:

1. **"Done" is the model's opinion.** The agent says a task is finished. It
   may have weakened a test, run a subset, or never exercised the code it
   "fixed." Nothing independent checked.
2. **The agent can reach past its lane.** It pushes, rewrites history, edits
   the very checks that judge it, or adds a dependency — all without a human
   deciding to let it.

This kit makes the first one mechanically verifiable and the second one harder
to do by accident, so a human can step back from the keystrokes while keeping
the decisions. It does not try to make an autonomous agent safe against itself
when it is actively trying to escape (see [Limitations](#limitations-read-this)).

## The idea in one paragraph

Claude Code already is the build loop. The hard part is the trust around it.
So this kit adds three things to a repo: **boundary guards** (Claude Code hooks
that block a fixed set of dangerous git and filesystem operations), a
**verifier** (a script that decides "done" by re-running the full test suite,
checking the count against a baseline, grep-proving the changed code is on the
live path, and proving a new test actually failed before the fix), and a **Stop
gate** (a hook that refuses to let a session end mid-task unless the verifier
has produced a fresh PASS against the current working tree). Judgment stays
human: the agent drafts, you approve in chat, and then the loop executes the
release. The trust layer is itself code, so it ships with an **adversarial
eval** that proves each check fires on the violation it is meant to catch.

## Architecture

Five layers, each a directory. Work flows left to right; the human sits at the
approval points.

```
            ┌─────────────────────────────────────────────────────────┐
            │                     Claude Code session                   │
            │                                                           │
  you  ──▶  │  .claude/commands/      .claude/hooks/      rails/verifier/
 (drop a    │  ┌──────────────┐       ┌──────────────┐    ┌───────────────┐
  spec)     │  │ /dispatch /go│       │ guard_bash   │    │   verify.sh   │
            │  │ /verify      │──────▶│ guard_files  │───▶│ (the keystone │
            │  │ /handoff     │       │ gate_stop    │    │  "done" judge)│
            │  └──────────────┘       └──────────────┘    └───────────────┘
            │     commands              boundary guards       verifier
            │   (orchestrate)         (block out-of-lane    (re-runs suite,
            │                          git/file ops)         proves the work)
            └───────────────────────────┬───────────────────────────────┘
                                         │  proves the trust layer itself
                          ┌──────────────┴───────────────┐
                          │  rails/adversarial/           │   rails/observers/
                          │  run_eval.sh + case suite     │   event → inbox
                          │  ("demonstrate the catch")    │   (outer loops)
                          └───────────────────────────────┘
```

| Directory | Layer | What lives there |
|---|---|---|
| `.claude/hooks/` | **Boundary guards** | `guard_bash.py`, `guard_files.py` (PreToolUse) and `gate_stop.py` (Stop). The only pieces Claude Code invokes automatically. |
| `.claude/commands/` | **Commands** | `/dispatch`, `/go`, `/verify`, `/handoff`, `/status` — the operator-facing workflow. |
| `rails/verifier/` | **Verifier** | `verify.sh` plus single-purpose Python helpers (`treehash.py`, `demonstrated_red.py`, `fingerprint.py`, …). Decides "done". |
| `rails/adversarial/` | **Adversarial eval** | `run_eval.sh` and one known-bad case per violation class. Proves the verifier and guards actually fire. |
| `rails/observers/` | **Observers** | Optional scheduled watchers (Sentry, CI, dependency advisories, …) that turn world events into proposals in the same human-gated inbox. |
| `rails/dispatches/`, `rails/evidence/`, `rails/handoff/` | **State** | Per-task working dirs, verifier output, and review packages. Git-ignored where per-machine. |

The core rule that ties it together: the agent cannot edit its own judge.
`rails/verifier/`, `.claude/hooks/`, the settings, and `rails/adversarial/` are
read-only to the loop (enforced by `guard_files.py`). You change the trust
layer; the agent only proposes changes.

## Requirements

`git`, `bash`, and `python3` on PATH. That is the whole dependency list. Every
script is standard-library Python or POSIX-ish bash, no packages to install.
Developed against stock macOS `bash` 3.2 and exercised in CI on Ubuntu `bash`
5, so it runs on both. The hooks target current Claude Code's hook contract;
`gh` is only needed for the optional GitHub-Actions observer.

## Install into a repo (about 2 minutes)

```bash
./install.sh /path/to/your/repo      # never clobbers existing files
cd /path/to/your/repo

$EDITOR rails/config.json            # set: scope, test_cmd, count_regex,
                                     #      collect_cmd, main_branch
bash rails/verifier/doctor.sh        # preflight: env, config, hooks, fingerprint

# seed the test-count baseline from a known-good suite run:
bash rails/verifier/verify.sh BOOTSTRAP --update-baseline

# prove the trust layer (stamps rails/adversarial/registry.json):
bash rails/adversarial/run_eval.sh
```

`doctor.sh` reports FAILs on a fresh install **by design** — the governor isn't
proven yet and `collect_cmd` is unset. That is the preflight telling you the
setup steps above still need to run, not a broken install; it goes green once
`config.json` is filled and `run_eval.sh` has stamped the registry.

Then restart Claude Code in the repo so it picks up `.claude/settings.json`,
and accept the workspace-trust dialog. If the repo already has a
`.claude/settings.json` or a `CLAUDE.md`, the installer writes a
`settings.rails.json` / appends a marked block instead of overwriting — see the
notes it prints.

## Try it without installing

```bash
bash rails/adversarial/run_eval.sh   # run the eval against the kit itself
```

This builds disposable sandboxes containing the kit's actual trust-layer files,
injects one violation per class, and checks that the right guard or verifier
check fires, and that clean work is not falsely flagged. Each case is a
concrete, executable example of a catch.

## The daily workflow

```text
1. drop a spec/ticket/notes into rails/dispatches/inbox/
2. /dispatch   → Claude turns it into a dispatch + a manifest of proof
                 obligations, then stops for your review
3. approve in chat → the loop records APPROVED and proceeds
4. /go         → walk away; it builds, runs the verifier, and cannot end the
                 session without a fresh PASS or an explicit BLOCKED note
5. read the handoff → approve; the loop commits (and pushes if you ask),
                 then reports the hash
6. /status     → read-only dashboard, any time
```

The full workflow, including how the optional reviewer, observers, and Claude
Code's `/goal` and `/loop` layer on top, is in
[`docs/OPERATING.md`](docs/OPERATING.md). The operating rules the agent itself
follows are in [`CLAUDE.md`](CLAUDE.md).

## What is enforced, what is advisory

- **Enforced (blocks the loop):** the boundary guards stop a fixed set of
  shell and file operations — push/merge/force/rebase/amend/hard-reset, commits
  (configurable), dependency adds, migrations, and any write to the trust
  layer. The Stop gate refuses to end a session mid-task without a fresh PASS.
- **Verified (the verifier's PASS means something):** full suite to completion,
  count vs. baseline, live-path grep, demonstrated-red. The verdict is stamped
  with a working-tree hash, so a stale green cannot be reused.
- **Posture (`rails/config.json`):** the default is `standard`, so the Stop
  gate blocks out of the box. `quiet` downgrades it to report-only — an explicit
  opt-down for low-stakes repos, not the default, because a gate that only
  reports is advisory. The optional code reviewer never feeds the gate; its
  findings inform you, nothing else.

## Proven in CI

`.github/workflows/prove.yml` re-runs the adversarial eval on every push and
pull request and fails the build if any case fails. CI proves but never stamps
the registry. Marking the trust layer "proven" stays a local, human-released
act (`RAILS_NO_STAMP=1` in the workflow).

## Limitations (read this)

The threat model it serves is a well-meaning agent that cuts corners under
pressure, with a human at the approval gates. It does not serve a determined or
adversarial agent. Specifically:

- **The bash guard is a pattern matcher, not a sandbox.** It blocks the obvious
  forms and the known config-injection vectors (`git -c core.hooksPath=`,
  `-c alias.…`, `GIT_CONFIG_*`), but it cannot stop an agent that writes files
  through a language interpreter (`python3 -c 'open(…,"w")'`). That class is
  architectural — for a hostile agent, use the optional [`isolate/`](isolate/)
  companion, which runs the loop in a container with the trust layer mounted
  read-only and the network off (a kernel-enforced boundary, not a pattern).
  This is a discipline tool, not a sandbox.
- **The verifier's "done" rests on a human approving a sound manifest.** The
  per-task `manifest.json` (what to break, what to grep) is frozen at approval
  and its obligations must point at the code the dispatch actually changed, so
  an agent can no longer rewrite or decoy its own proof after sign-off — but the
  human still has to approve a manifest that asks for the right thing.
- **The one open residual, disclosed:** the interpreter-write bypass above is
  architectural — open by design in-process, closed by the `isolate/` boundary.
  (The verifier's own soundness holes — manifest, diff-grounding, and
  untracked-content freshness — are all closed.)

These and the rest — including what's been closed and what hasn't — are tracked
in the adversarial self-audit, [`AUDIT.md`](AUDIT.md).

## Layout

```
install.sh                     installer (copy into a target repo; --update to refresh)
CLAUDE.md                      operating rules the agent follows (merged into your repo)
.claude/
  settings.json                hook registration
  hooks/                       guard_bash.py  guard_files.py  gate_stop.py
  commands/                    /dispatch /go /verify /handoff /status …
rails/
  config.json                  per-repo adapter: test_cmd, count_regex, branch, posture
  verifier/                    verify.sh + helpers, baseline.json, load_bearing.txt
  adversarial/                 run_eval.sh + cases/  (one known-bad case per violation class)
  observers/                   event-initiated intake: definitions + runner
  dispatches/  evidence/  handoff/   per-task state (git-ignored where per-machine)
docs/OPERATING.md              the full daily workflow
isolate/                       OPTIONAL container boundary (trust layer read-only, no network)
AUDIT.md                       adversarial self-audit: what holds, what doesn't
```
