---
description: Run the verifier against the active dispatch and report the verdict
---

Run `bash rails/verifier/verify.sh $ARGUMENTS` (it auto-detects the dispatch
if exactly one is active). Report the verdict exactly as the script printed
it: status, then each check with its detail, then the evidence path.

Do not soften a FAIL, do not reinterpret a check, and do not modify
anything under `rails/verifier/`. If a check seems wrong, say so explicitly
as a recommendation to the human; the verdict stands until a human changes
the verifier.
