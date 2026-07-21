# Governor release log

<!-- sourcebound:purpose -->
Use this ledger when reviewing or changing the governor trust layer. It identifies every permissive or restrictive change and its proof fingerprint so you can focus review on moments when release authority changed.
<!-- sourcebound:end purpose -->

This is an append-only, human-maintained ledger of changes to the **governor** — the
trust layer the agent cannot edit (`rails/verifier/`, `.claude/hooks/`,
`.claude/settings.json`, `rails/adversarial/`). One line per change.

The guards treat this file as append-only: the agent may never edit or delete
an existing line. You add a line by hand whenever you change the trust layer,
after re-proving it (`bash rails/adversarial/run_eval.sh`).

Format:

    <date>  <LOOSENING|TIGHTENING>  <summary>  | why: <...>  | fp: <fingerprint12>

Read it at review time: every `LOOSENING` line is a moment the governor was
made more permissive, so those are the lines to read closely.

<!-- Add your first entry below after the initial run_eval.sh proof. -->
