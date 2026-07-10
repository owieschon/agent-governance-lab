# Eval design notes: simplifications and known residuals

This file documents where the adversarial eval deliberately simplifies, and
what it therefore does NOT prove. Every departure is stated with its grounds.
These are all choices made to keep the eval deterministic and local; none
touches the core: every governor check fires against a known-bad input and
clean work is never false-positived.

1. **Sandbox fixture instead of live-repo violations.** Cases run against
   a disposable toy repo into which the host's ACTUAL trust-layer files
   are copied at run time. Grounds: known-bad inputs must not corrupt
   real work; the mechanism under test is byte-identical.

2. **Hook cases drive the guard scripts via the documented stdin
   contract, not a live Claude Code session.** Grounds: determinism and
   zero token cost. Residual assumption (Claude Code delivers hook events
   per contract) is owned by the environment-change trigger: the registry
   records the CC version, and verify.sh fails the governor check on a
   recorded environment change, forcing a re-proof.

3. **"Inflation" is implemented as its mechanically assertable forms:**
   stale-green presented as current (case 08), forged/tampered verdicts
   (case 09), and fabricated test names (case 06). Prose-level scope
   inflation in a handoff has no mechanical oracle and remains at the
   human gate, consistent with the dispatch->approve->go->handoff pipeline.

4. **Claim-not-landed proven against a local bare remote.** Grounds:
   identical git semantics, no network dependency, deterministic.

5. **Two classes added beyond the starting set** (the definition of done --
   green + count + live-path + demonstrated-red -- is explicitly a floor):
   `undisclosed-judgment` (case 10, the senior-engineer disclosure gate) and
   `unproven-governor-change` (case 11, the governor-change trigger,
   mechanized as a fingerprint gate).

Framework changes made alongside this eval (human-released via review of
this delivery, and themselves proven by the eval before taking force,
because verify.sh now refuses an unstamped governor):
- rails/evidence/, rails/config.json, rails/adversarial/ added to the
  protected set (closes forge-a-verdict and soften-the-test-command,
  both found while designing case 01).
- decisions check (disclosure of judgment, not grading of it).
- governor_proven check (the governor-change trigger: editing a check or
  hook closes the gate until the eval re-proves it).

Routing notes (what is deliberately NOT a governor class):
- TRAJECTORY / cross-turn inconsistency is not a governor class. An agent that
  contradicts itself across turns is a quality signal, not a check-it-fires
  violation; it routes to the calibration layer, not the eval.
- ADVERSARIAL-MODEL PROPENSITY (a model that actively tries to defeat the
  governor) and MULTI-AGENT COLLUSION are named EXCLUSIONS for the threat-model
  doc, not eval cases. The cooperative-but-corner-cutting threat model is what
  the eval mechanizes; a hostile model needs OS-level isolation, not a bash
  guard, and the threat-model doc states that honestly.
- ORACLE-INTEGRITY READ-SIDE RESIDUAL (class A): pure READING of test files
  cannot be blocked -- the agent must read tests to write code. Only mutation
  and instrumentation are mechanized; the threat-model doc states the read-side
  residual plainly.
- ORACLE-INDEPENDENCE (class B) and EXERCISED-ASSERTIONS (class C) are HEURISTIC
  and runner-shaped (AST self-reference detection; per-test pass/skip/xfail
  parsing needing pytest -rA / unittest -v). Their precision is tuned by the
  false-block adjudication; scoped to load-bearing tests to bound noise.
- CLEAN_ROOM (class D) proves the worktree-reexec + count-match core; the fresh
  venv/node-from-lockfile install is the CI-posture layer (doubles suite time,
  ON in CI, off in the inner loop), not exercised by the toy fixture.

Posture, precision, and principle residuals:
- L6 NEXT-STEP LINT scope v1 is call-site-shaped: it lints the literal args of
  deny()/block()/bad()/refuse() in hooks + verifier python (including the
  embedded <<'PY' blocks of verifier shell). Free-form echo/printf flag text in
  shell is not extracted; the action-clause test is a heuristic verb/path
  matcher. Both are tuned by the same false-block adjudication as classes B/C.
  Its first run on the shipped kit caught 12 dead-end messages (since fixed)
  -- demonstrated before it gated anything.
- QUIET-POSTURE CEREMONY RELAX: in quiet, the plain-commit boundary and
  the test-file write gate do not block (in the default posture nothing outside
  the floor is blocked). The floor and the trust-layer self-protection are
  posture-independent (cases 18/19 prove it), and CHECKING is unchanged: a
  mutated oracle still FAILs oracle_integrity where a snapshot exists; quiet
  only changes whether anything blocks. The price: a quiet user's tests can be
  silently edited between verdict lines.
- PRECISION SIGNALS are mirrors with thresholds (window 20, min 3 outcomes,
  strict majority): below threshold nothing flags, which under-reports thin
  real patterns by design (L10: a 1/1 window means nothing). Zero-fire checks
  surface as "unproven in practice", never as precise.

Onboarding/DX residuals (init + demo):
- DEMO NESTED-RUN: case 23 proves the demo's catch is REAL by reproducing its
  staged violation against the eval sandbox's own D-test dispatch (real verify
  FAIL on oracle_integrity, real PASS on restore) and asserting the demo script
  hardcodes no verdict text and invokes the real verifier. It does NOT run
  demo.sh's full nested sandbox-in-sandbox inside the eval (the eval sandbox
  carries no adversarial harness; fixture-in-fixture is avoided). The full
  nested run is exercised by hand and is a README capture target.
- INIT VALIDATION RUNS THE SUITE ONCE: `rails init` executes the detected test
  command to confirm count_regex parses a real run (hard rule: never seed
  a config it could not parse a run with). Portable cap (background+poll+kill,
  240s) since stock bash 3.2 has no `timeout`. A pathological suite that ignores
  SIGKILL or a runner with side effects is out of scope; init is a human-invoked
  setup step, not an autonomous one.
- INIT v1 ADAPTER FAMILIES: pytest/unittest + jest/vitest are fleet-verified
  (verified=yes); go/cargo are detected (verified=no, "confirm before trusting")
  and validation-gated identically. Other ecosystems fall to the ASK path with
  the keys named — no silent wrong guess.

Eject, freshness, and /rails-skill residuals:
- EJECT ROUND-TRIP (case 26) uses the REAL install.sh against a throwaway repo
  (the KIT_HOST seam in run_eval). It exercises install<->eject symmetry and the
  registry-expiry seam. The "changed governor demands fresh eval" assertion
  checks the fingerprint diverges from the preserved stamp; it does not run a
  full verify (which needs a dispatch) -- the fingerprint gate is what enforces
  expiry and is asserted directly.
- EJECT settings surgery removes settings.json only when it reduces to purely-
  rails ({}). A user with other settings keeps the file, and a re-install then
  offers settings.rails.json for a manual merge -- so that round-trip is NOT
  byte-clean by design (the user's settings are theirs to merge), unlike the
  pure-rails fresh-install case which round-trips exactly.
- /rails SKILL is not eval-covered (it is instructions for Claude, not a check);
  it is conformance-table-only and ships outside the fingerprint set.

RETIRED 2026-06-12: the governor release ceremony
(propose/classify/release, the PENDING_RELEASE marker, cases 13/28/29/40) was
removed by operator decision. Its residuals (additive-bypass,
guard_surface scope, classifier calibration) retire with it. The remaining
guard on governor changes: the trust layer is agent-read-only (guards), and a
changed fingerprint set certifies nothing until run_eval.sh re-proves it
(verify.sh fingerprint gate). Governor diff review is now wholly human
judgment, with no mechanical classification or asymmetric release act --
named, not hidden.

Flaky-lane residuals (the quarantine lane):
- THE GATED test_cmd MUST NOT COLLECT THE LANE DIR. The lane only removes
  flakiness from the gate if the user's gated test_cmd excludes flaky_glob (e.g.
  a separate top-level dir that `unittest discover -s tests` ignores, or
  `pytest --ignore=flaky_tests`). The kit composes with the user's setup; it
  cannot generically prove their test_cmd excludes the lane. If the
  gated suite still collects the lane, the flaky test is still in the gate and
  the lane is advisory. Documented as a setup requirement; rails init / a future
  doctor check could verify the non-overlap.
- LANE-RUN PARSING is runner-shaped: the non-gating lane result reports the run
  exit code + the count_regex number (whatever it means per runner). The
  SMUGGLING catch (a lane file not in the manifest) is runner-agnostic and is the
  load-bearing assertion; the M/K/N naming is best-effort reporting.
- "WHAT IS A TEST FILE" in the lane is a heuristic (any regular file minus
  __pycache__/.pyc/__init__/hidden). A relocated test with an artifact-shaped
  name is an edge the heuristic could miss; conservative widening (more file
  types count) only adds smuggling-false-positives, the safe direction.

Role kernel + reviewer residuals (posture mechanism + first instantiation):
- POSTURE ENFORCEMENT IS HEURISTIC for bash writes. Guard_bash reads WRITE_TOKENS
  (a regex over shell commands) to detect writes. A write disguised in a way the
  regex misses (e.g., compiled binary, Python subprocess) is not caught by the
  bash guard. Guard_files catches editor writes directly (not heuristic); the
  bash heuristic is the complement for shell-mediated writes. The same heuristic
  applies to worker boundary enforcement and has been tuned over 30+ cases.
- POSTURE CARVE-OUT scopes to exact patterns. The reviewer's findings path
  (rails/evidence/*/review_findings.md) carves out the trust-layer protection for
  that specific fnmatch pattern only. A posture granting broader write access to
  rails/evidence/* would open the evidence directory more widely; the posture
  file is governor-held (fingerprint-set) to prevent this.
- REVIEWER DETECTION PROFILE is demand-driven N. Cases 31-34 prove the mechanism
  (posture fires, gate ignores, cap renders, grounding rule present); they do NOT
  measure the reviewer's detection accuracy. The detection profile (seeded defects
  + honest neighbors + FPR) grows with use; the prior is disclosed in the spec
  (SHADE-Arena AUC ~0.87, smallest model 13%-wrong at confidence 1.0). The
  reviewer is expected to miss things; the profile says which classes and how often.
- NON-BLOCKING is asserted by the timeout mechanism (background+poll+kill,
  portable for bash 3.2). A reviewer that hangs → "review: unavailable" and the
  handoff proceeds. The cross-process timeout test (reviewer blocks beyond
  timeout) is no longer future work: case 44 hangs a stub model past the
  timeout and asserts the handoff returns within deadline with the one honest
  line AND that the hung process tree is actually dead. The sharp edge it pins:
  review.sh's own kill reaps the subshell it backgrounded, but a hung model
  process can be an orphaned grandchild -- handoff_review.sh launches review.sh
  in its own process group (set -m) and group-kills at render time, which is
  what reaps the grandchild cross-process.
- R2 (gate-ignores-review) is naturally GREEN from the start (like case 18):
  it tests a structural negative (the gate does NOT read reviewer output) that
  was already the design. It becomes the guard that ensures nobody accidentally
  wires findings into the gate. Severity/score consumption by the gate is also
  asserted absent.
