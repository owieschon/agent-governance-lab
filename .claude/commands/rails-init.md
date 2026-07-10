---
description: Autodetect and validate this repo's test adapter, then seed rails/config.json (never stamps the governor)
---

Run `bash rails/verifier/init.sh` and present its output verbatim.

init detects the test ecosystem (pytest/unittest, jest/vitest; go/cargo as
unverified), runs it once to confirm the detection is real, and writes the
adapter into rails/config.json -- preserving any values already there. It never
seeds a config it could not parse a real run with; on failure it names the keys
to set by hand. Run `bash rails/verifier/init.sh --detect-only` first if the
user wants a dry run.

Two things to tell the user after it runs: (1) fill in `scope` (one line on what
the repo is for -- init leaves it blank because it is prose, not detectable),
and (2) init SEEDS but never STAMPS -- the governor is still unproven, so the
next step is `bash rails/verifier/verify.sh BOOTSTRAP --update-baseline` then
`bash rails/adversarial/run_eval.sh`. Do not run those for the user without
their go-ahead; proving the governor is their call.
