---
description: Show a real 3xit2 catch in a throwaway sandbox -- zero config, nothing touches your repo
---

Run `bash rails/verifier/demo.sh` and present its output verbatim.

This is the first-touch demo: it builds a disposable sandbox, stages a real
violation (an agent editing the test that grades it), runs the actual verifier,
and shows the real BLOCKED verdict -- then a clean PASS on whole work. It needs
no config and removes its sandbox on exit; nothing touches the user's repo.

Do not embellish or summarize the verdicts; they are real verifier output.
After the demo, if the user wants it on their own repo, the next step is
`rails init` (the demo's closing lines say so).
