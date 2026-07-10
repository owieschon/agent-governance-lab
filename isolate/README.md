# OS-isolation companion (optional)

The in-process guards (`.claude/hooks/`) are a pattern matcher, not a sandbox.
They stop a cooperative agent that cuts corners — the kit's stated threat model
— but they cannot stop an agent that writes files through a language
interpreter (`python3 -c 'open(…,"w")'`, see [`../AUDIT.md`](../AUDIT.md) "B4")
or otherwise reaches past a regex. That class is architectural: a guard reading
a shell string can never enumerate every way to write a byte.

This directory is the honest answer for the **adversarial** threat model the
guards do not cover: run the loop inside a container where the boundary is
enforced by the kernel, not by patterns.

## What the boundary enforces

`run.sh` starts a container (Docker or Podman) with:

- the **trust layer mounted read-only** — `rails/verifier/`, `rails/adversarial/`,
  `rails/observers/`, `.claude/hooks/`, `.claude/settings.json`, and
  `rails/config.json` (which holds the verifier's inputs: `test_cmd`,
  `count_regex`, posture — so the loop can't rewrite the test command to fake
  the suite). A write to any of them fails with `EROFS` regardless of how it is
  invoked, including the interpreter-write bypass the host-side guards miss.
- **`--network=none`** — the loop cannot push, fetch, or contact a third party.
- the agent works in a **writable copy** of the rest of the repo; you review and
  apply changes on the host.

## Use

```bash
bash isolate/run.sh                 # a shell inside the boundary
bash isolate/run.sh <your loop cmd> # run the agent loop inside it
```

Add your agent's runtime (e.g. Node + the Claude Code CLI) to the `Dockerfile`
if you run the loop inside the container; the image is deliberately minimal
(git/bash/python3) because the boundary — not the image — is the point.

## Verify it before you trust it

```bash
bash isolate/selftest.sh
```

It asserts the two properties the in-process guards cannot: an interpreter
write to the trust layer is blocked, and a push is blocked.

> **Status: not executed in this repo's CI.** The kit's CI host has no container
> engine, so this companion ships with the self-test rather than a green
> checkmark. Run `selftest.sh` on a Docker/Podman host to confirm the boundary
> holds in your environment before relying on it. This is a documented,
> testable path — not a verified-here guarantee.

## What it does NOT do

It does not make the kit a general security product. It bounds *this* loop's
blast radius. Container escapes, a writable mount you add, or credentials you
pass into the container are all out of scope — and a determined attacker with
those is past this boundary.
