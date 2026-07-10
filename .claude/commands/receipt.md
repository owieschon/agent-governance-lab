---
description: Render the shareable receipt for a verified dispatch (claim, summary, catches, decisions, provenance)
---

Run `bash rails/verifier/receipt.sh $ARGUMENTS` and present the rendered
file's contents verbatim, then name its path.

A receipt is rendering over existing verified data -- it asserts nothing the
verifier did not already establish, and it renders only a PASS. Its
provenance line (commit, governor fingerprint, evidence content hash, run
pointer) is how a reader who did not generate it can trust it: they follow
it to its run. Do not embellish, summarize, or decorate the output; the
register is dry by design.
