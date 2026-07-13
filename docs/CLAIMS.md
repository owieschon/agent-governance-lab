# Claims and trust

<!-- clean-docs:purpose -->
Use this reference when deciding what an Agent Governance Lab result proves. It separates fail-closed comparison behavior, excluded cases, bound evidence, and threats outside the cooperative-hook boundary so reviewers can keep claims inside the executable evidence.
<!-- clean-docs:end purpose -->

## Refusal behavior

`rails/agl/trust_anchor.py` pins the digest of
`experiment/trusted-release.json`; the manifest in turn binds the mutable lock,
preregistration, corpus, context records, executable engines, Python/browser
verifiers, and every analysis schema. `experiment/bindings.json` is a derived,
manifest-bound readout—not its own source of truth. Before any headline
analysis, the generator requires:

1. exact binding matches;
2. the preregistered case order;
3. an independent `clean` or `violation` label for every case;
4. successful execution of every mechanism; and
5. identical candidate-envelope SHA-256 values across L0, L1, SHAM, and L3.

If any condition fails, the only valid output is:

```json
{
  "status": "NO_CONFIRMATORY_RESULT",
  "headline_eligible": false,
  "metrics": null
}
```

Regression tests change a corpus label and rewrite the mutable binding beside
it, drift a schema, forge and rehash a treatment receipt, and forge and rehash
headline metrics. Each path refuses the release; the browser keeps the headline
panel hidden for the rehashed-result reproduction.

## Two cases kept outside the benchmark

### Historical study invalidity

A prior paired L0/L1/SHAM/L3 study preserved 72 signed run records but did not
earn a treatment result. Its frozen apparatus had not exercised the full
record → grade → analysis seam; runner and grader tree hashes were incompatible,
so the integrity fence refused the real records. Grading stopped and headline
metrics remained `null`.

The explorer preserves that decision as `NO_CONFIRMATORY_RESULT`. It does not
reuse the old implementation, private materials, or synthetic effect sizes, and
does not rewrite repaired plumbing into a historical success.

### Transport-fidelity engineering decision

A separate real engineering case completed 127/127 judge items with zero
crashes, but the fidelity gate still failed: clean `safety_boundary` kappa was
`0.98`, outside the committed `[1.0, 1.0]` band, and one adversarial false-open
appeared against a reference of zero. The release decision remained **stop**.

This case has a strict local schema and semantic verifier plus a commit-pinned
public source digest:

```bash
./bin/agl verify-engineering-case
python3 scripts/verify_engineering_source.py
# Optional network recheck of the immutable public source:
python3 scripts/verify_engineering_source.py --fetch-source
```

It establishes transport completion and a preserved release refusal. It is not
part of the synthetic comparison, any denominator, or a model-efficacy claim.

## Integrity vertical slice

1. [`experiment/preregistration.json`](../experiment/preregistration.json) —
   treatments, estimands, denominators, invalidity rules.
2. [`experiment/trusted-release.json`](../experiment/trusted-release.json) —
   code-anchored manifest for every mutable comparison source and schema.
3. [`rails/agl/comparison.py`](../rails/agl/comparison.py) — deterministic executor,
   semantic receipt/result verification, and fail-closed analysis.
4. [`explorer/index.html`](../explorer/index.html) — static, framework-free reviewer
   surface over the generated, content-addressed result;
   `trusted-release.js` anchors the build and `verification.js` recomputes the
   receipt-backed analysis in the browser.

JSON Schemas live in [`schemas/`](../schemas/). The original provider-independent
release receipt remains documented in
[`docs/EVIDENCE_CONTRACT.md`](../docs/EVIDENCE_CONTRACT.md).

## Trust boundary

**Bound by this artifact:** public fixture bytes, attempted action, expected
labels, treatment rules, engine and verifier bytes, schemas, mechanism outputs,
equal candidate digests, source pins, integer denominators, semantic receipt
decisions, and the build-embedded browser release digest.

**Not bound:** a hostile process that can bypass cooperative hooks, the quality
of a human-approved manifest, the representativeness of eight synthetic cases,
model behavior in the wild, or business outcomes. The in-process Bash guard is
a discipline boundary, not a security sandbox; [`isolate/`](../isolate/) is the
optional OS-level companion for a stronger boundary.

To install the governance mechanism into another repository, run
`./install.sh /path/to/repo`, configure `rails/config.json`, seed the test-count
baseline, and execute the full adversarial proof. The daily operator path and
update/eject behavior remain in [`docs/OPERATING.md`](../docs/OPERATING.md).
