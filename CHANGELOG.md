# Changelog

Security-hardening changes since the initial release. Each follows the kit's own
process: an adversarial eval case that reproduces the hole (red), the minimal
fix, the case passing (green), and a full governor re-proof. Every change is
auditable and the suite stays green.

- **B5 — case-insensitive-filesystem guard bypass (closed).** On stock macOS /
  default Windows, `RAILS/VERIFIER/baseline.json` resolves to the same file as
  the protected `rails/verifier/baseline.json`, but `guard_files.py` compared
  paths case-sensitively and missed the variant — a write straight onto a
  protected file (reproduced live in the audit). Fixed by detecting a
  case-insensitive filesystem once and folding case in the protected-path
  comparisons; on a case-sensitive filesystem the variant is a genuinely
  different file, so the change is a no-op there (Linux/CI behavior unchanged).
  Proven by new adversarial case `51_case_variant_path` (asserts blocked on
  case-insensitive FS, allowed on case-sensitive). Governor re-proved green.

- **V2 — scorer-integrity self-disable (closed).** `oracle_integrity` (the
  defense against an agent silently mutating the tests that grade it) could be
  turned off wholesale by setting one agent-writable boolean, `"declares_test_changes": true`,
  on the manifest — and the eval's own case 14 codified that as legitimate. Removed
  the blanket flag: a test/fixture change is now declared only by naming the
  specific files in `"test_changes": [paths]`, a per-file declaration the human
  sees at the approval gate. Rewrote case 14 to prove the blanket flag no longer
  clears the gate while a named declaration does; migrated cases 15 and 16 (which
  used the flag only to isolate their own check) to the named form. Governor
  re-proved green. Surfaced while fixing it: `snapshot.sh` (which records the
  approval-time hashes the check compares against) is not wired into the
  documented approval flow, so the check is inert outside the test fixture until
  that wiring is added — logged in `AUDIT.md` for the manifest-freeze work.

- **Scoreboard ported to SQL (language fit + first bash→Python port).** The
  program scoreboard's metrics — dispatches completed, first-pass verify rate,
  mean iterations-to-green, incident/accretion status — are relational
  aggregates over an append-only event ledger (`rails/evidence/` verdicts +
  `stats.jsonl`, `rails/incidents/`). They had been computed by a ~90-line
  Python heredoc inside `scoreboard.sh` doing hand-rolled dict counting. Moved
  to a standalone `rails/verifier/scoreboard.py` that loads the ledgers into an
  in-memory **stdlib `sqlite3`** database and computes the metrics with readable
  CTEs (`scoreboard.sh` is now a thin shim, matching `stats.sh`). Stdlib sqlite3
  keeps the kit zero-dependency. Output is byte-preserved (cases 27 and 42 pin
  the format); wired into `install.sh`, `eject.sh`, and the eval fixture; full
  eval re-proved green including the install round-trip (case 26). The queries
  were later externalized into `rails/verifier/scoreboard_metrics.sql`
  (loaded by name) so they are a first-class, readable artifact rather than
  Python string constants — which also means GitHub's language stats now count
  the SQL instead of hiding it inside a `.py` file.

- **V3 — advisory default posture (closed).** The kit shipped `posture: quiet`,
  under which the Stop gate only *reports* a missing/stale verdict and lets the
  session end — so the headline guarantee did not hold in the default config
  (the eval ran `standard`, proving a stricter setup than was shipped). Flipped
  the shipped `rails/config.json` default to `posture: standard`, so the gate
  blocks out of the box; `quiet` remains an explicit opt-down for low-stakes
  repos. No new case needed — case 18 already proves standard/strict block a
  stale verdict while quiet reports; the shipped default is now the gating
  behavior the eval proves. README updated to match.

- **Manifest freeze at approval (post-approval V1/V2/V4/V5 — closed).** The
  per-dispatch `manifest.json` defines the proof obligations (break plan,
  live-path greps, declared test changes) and is written by the agent, so a
  post-approval rewrite let the agent grade itself against an answer key it
  changed. `snapshot.sh` now hashes the manifest at approval (next to the
  test-file hashes it already records), it is wired into `dispatch.md`'s
  approval step, and `verify.sh`'s `manifest_complete` check fails on any
  post-approval drift; a real amendment re-approves, which re-snapshots. Proven
  by new case `52_manifest_frozen`. The *at-approval* decoy half (V1/V4) is
  still open and needs greps/break-plan tied to the diff.

- **Config-injection push bypasses hardened (B1–B3).** `git -c core.hooksPath=`
  (disables the pre-push hook), `git -c alias.<name>=` (alias-expands to push),
  and `GIT_CONFIG_*` env injection each reached the remote without naming `git
  config` or `git push` adjacently — past both the per-segment regex and the
  git-layer hook. `guard_bash.py` now rejects those forms and its
  push-indirection scan sees through env-var assignments and `-c` global flags;
  benign `-c` (e.g. `-c color.ui`) stays allowed. Proven by the extended case
  `37_git_config_alias`. This is **defense-in-depth, not a seal** — a regex over
  a shell string is not a sandbox; the class is architectural and the honest fix
  for a hostile agent is OS-level isolation. B4 (interpreter writes to the
  apparatus) is the same class and remains open.

- **B6 / B7 — adjudicated, documented (no behavior change).** B6 (`gate_stop`
  fails open on malformed stdin) is kept fail-open *by design* — a Stop hook
  that fails closed risks bricking the session, the agent cannot supply this
  hook's stdin (Claude Code does), and unverified work is still caught by the
  verifier/evidence regardless. Added a code comment explaining the deliberate
  asymmetry with the fail-closed PreToolUse guards. B7 (forged verdict) is
  already gated: `verdict.json` is agent-read-only under `rails/evidence/` (case
  09), so a forge is only reachable by first defeating that via B5 (fixed) or B4
  (architectural). Both recorded accurately in `AUDIT.md` rather than papered
  over with a brick-risking "fix."

- **Obligations grounded on the diff (at-approval V1/V4 — closed).** The manifest
  is agent-authored, so even with the freeze, an agent could propose a decoy at
  approval — a `break_plan` or `live_path` grep pointing at code the dispatch
  never touches — and the human might approve it; the green→red→green ceremony
  would then prove nothing about the real change. Added `basis.sh`, which records
  the base commit at approval (HEAD before the build) into an agent-read-only
  `.base_ref` (guards block agent writes; only `basis.sh` writes it). When a base
  ref is present, `verify.sh` requires the break plan to target files in the
  dispatch's diff and each live-path grep to match a line in a changed file;
  `rails/` paths are excluded so trust-layer churn never counts. The check is
  isolated by the base-ref marker — dispatches/installs without one keep the
  prior match-anywhere behavior, so no legitimate work false-blocks. Proven by
  new case `53_obligations_grounded`. With the freeze, the verifier no longer
  trusts an unconstrained agent-authored answer key — the central soundness gap
  the self-audit named.

- **Language-fit ports (bash heredoc → standalone Python).** `status.sh`,
  `receipt.sh`, `why.sh`, `snapshot.sh`, `flaky_triage.sh`, and
  `run_observer.sh` each wrapped a substantial `python3 - <<'PY'` block; each is
  now a thin shim invoking a standalone sibling `.py` (matching `scoreboard.py`
  and the existing `stats.py`), passing the previously-interpolated shell vars
  as argv. No logic changed; output is byte-preserved (the eval pins the
  formats); wired into `install.sh`, `eject.sh`, and the eval fixture; the new
  `.py` are auto-protected by the `rails/verifier/**` and `rails/observers/**`
  guard prefixes. `init.sh` was deliberately left as bash — its adapter
  detection is bash-native and porting only its one clean heredoc would fragment
  it further. Full eval re-proved green.

- **CI now exercises `verify.sh` on a real dispatch.** `prove.yml` builds the
  fixture dispatch and runs `verify.sh` against it, asserting a real PASS — so
  the verifier's own green path is CI-covered, not only the checks (the eval
  drives verify.sh through violation cases; this adds the clean-PASS path).

- **OS-isolation companion (optional) — `isolate/`.** The in-process guards
  can't stop the interpreter-write class (B4) — that's architectural. Added an
  optional container path that turns the honest "not a sandbox" caveat into a
  boundary: `run.sh` runs the loop with the trust layer mounted **read-only**
  (so an interpreter write fails at the kernel, `EROFS`) and **`--network=none`**
  (no push/fetch), and `selftest.sh` proves both. Kept out of the
  zero-dependency core (needs Docker/Podman). **Labeled not-executed-in-this-CI**
  — the CI host has no container engine — so it ships with its self-test rather
  than a false green; run `isolate/selftest.sh` on a Docker host to verify the
  boundary before relying on it. A documented, self-testable path, not a
  verified-here guarantee.

- **V6 — untracked-content staleness (closed).** `treehash.py` hashed untracked
  file *names*, not content, so a PASS stamped with an untracked file present
  could stand after the file's content was swapped for arbitrary code. Now it
  hashes untracked *content*. The fix also resolved a latent false-positive: the
  freshness hash had been polluted by the kit's own churning state under
  `rails/` (evidence, incident/adjudication ledgers, the registry stamp,
  snapshots), so a benign untracked file made a fresh verdict read as stale.
  `treehash.py` now excludes all of `rails/` (agent-read-only, governed by the
  fingerprint + manifest freeze, not freshness). Proven by new case 54; tracked
  non-`rails/` drift is still caught (regression-checked). **Every reproduced
  verifier hole (V1–V6, H1) is now closed.**

Still open (flagged in `AUDIT.md`): `init.sh` (bash-native adapter detection,
left by design). The architectural guard class (B4 + the B1–B3 residual) is the
adversarial-model concern, addressed by the `isolate/` companion above; the
in-process guards remain the cooperative-model check.
