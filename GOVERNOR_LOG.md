# Governor release log

Append-only, human-maintained ledger of changes to the **governor** — the
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
