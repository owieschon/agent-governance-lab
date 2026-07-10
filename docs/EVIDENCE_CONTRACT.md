# Evidence contract

`agl.receipt.v1` is the portable boundary between the governance engine and
anything that presents its result. A CLI, CI job, or future UI may render a
receipt; none of them may decide what the receipt says.

## What one receipt binds

- scenario identity and version;
- release policy and whether it has release authority;
- Agent Governance Lab version, source commit, dirty-state disclosure, and
  exact engine fingerprint;
- initial and final candidate tree hashes plus content hashes over the named
  candidate paths;
- bounded initial and final candidate snapshots that preserve safe relative
  paths, file/symlink kind, and exact bytes in canonical base64;
- test command, exit status, collected count, and output digest;
- every governor check and its detail;
- release decision and firing reason;
- non-identifying execution environment fields;
- the original verifier verdict, verifier output, and test output artifacts.

The receipt has its own SHA-256 content address. JSON keys are canonicalized
before hashing, so formatting changes do not change the meaning of the record.
Candidate content hashes use an explicit domain plus 64-bit length-prefixed
path, kind, and data frames; embedded delimiters in arbitrary file bytes cannot
change entry boundaries or collide with a different entry sequence.

## Verification layers

```bash
./bin/agl verify-receipt /path/to/receipt.json
```

The standard-library verifier:

1. validates the versioned contract and rejects unknown fields;
2. enforces semantic invariants—for example, an enforced policy cannot release
   failed checks;
3. recomputes the receipt content address;
4. recomputes every bound artifact digest;
5. validates both candidate snapshots, reconstructs their content hashes, and
   requires their path coverage and hashes to match `candidate.paths` and the
   receipt's initial/final claims;
6. parses the original verifier verdict and requires its checks, final tree,
   engine fingerprint, and enforced decision to match the receipt.

When the candidate workspace still exists, add `--workspace /path/to/repo`.
The verifier already reconstructs both content hashes from the durable
snapshots. With `--workspace`, it additionally recomputes the live final
candidate content and Git tree hashes from disk.

## Snapshot bounds

Candidate snapshots use `agl.candidate-snapshot.v1`. Paths are canonical POSIX
relative paths: absolute paths, parent traversal, backslashes, duplicates,
overlapping candidate roots, and entries outside the named roots are rejected.
Entries are limited to `file` and `symlink`; the latter stores the exact target
bytes and is never followed. JSON keys and entries are sorted, JSON is emitted
in the contract's canonical compact encoding, and base64 must use its canonical
padded form; the verifier rejects alternate encodings rather than normalizing
them silently.

Every parent component is checked lexically and by resolved containment before
any ordinary file is opened. A symlink may be the final captured entry, in
which case only its link-text bytes are stored. A symlinked parent is rejected,
including one that would lead to an otherwise readable path outside the
workspace. The live freshness verifier and receipt verifier use the same
worktree-hash implementation and apply the same rule to untracked symlinks.

One snapshot may contain at most 256 entries, 1 MiB of decoded content, and
2 MiB of JSON. Every named candidate root must contribute at least one entry.
These limits make the format appropriate for the small synthetic demo and
prevent a receipt verifier from becoming an unbounded archive reader. Larger
real repositories need a separately designed chunked/Merkle snapshot protocol,
not a silent increase to this contract.

## Trust boundary

The receipt is content-addressed, not identity-signed. It proves that a named
receipt and its evidence bundle still contain the bytes whose digest was
published in Git or CI. A party that controls the receipt, every artifact, and
the published digest can replace all three consistently. Authenticating an
external issuer requires a signature or trusted transparency log and is a
separate protocol; this version does not imply one.

That boundary is deliberate. The first useful contract is deterministic,
offline, inspectable, and independent of any model provider. Signing can be
added without changing what the underlying verdict must bind.
