-- Program-scoreboard metrics, computed over the trust layer's append-only event
-- ledger (loaded into an in-memory SQLite DB by scoreboard.py: one row per
-- verdict, per gate-rejection run, and per incident). Kept here as plain SQL,
-- not buried in Python strings, so the metric definitions are readable on their
-- own and reviewable line by line.
--
-- Sections are delimited by "-- name: <key>"; scoreboard.py loads each by name.

-- name: metrics
-- A dispatch is "done" once it has a PASS verdict. fail_runs = the highest
-- verify iteration recorded for it (0 if it passed on the first run), so
-- iterations-to-green is fail_runs + 1, and the first-pass rate is the share of
-- completed dispatches that needed zero failing runs. All three fall out of one
-- grouping over the ledger.
WITH passed AS (
    SELECT dispatch FROM verdicts WHERE status = 'PASS'
),
verify_runs AS (
    SELECT dispatch, MAX(iteration) AS fail_runs
    FROM runs
    WHERE source = 'verify'
    GROUP BY dispatch
),
completed AS (
    SELECT p.dispatch,
           COALESCE(vr.fail_runs, 0) AS fail_runs
    FROM passed p
    LEFT JOIN verify_runs vr ON vr.dispatch = p.dispatch
)
SELECT
    COUNT(*)                                       AS n_done,
    SUM(CASE WHEN fail_runs = 0 THEN 1 ELSE 0 END) AS first_pass,
    AVG(fail_runs + 1)                             AS mean_iters
FROM completed;

-- name: incidents
-- Incident count and how many are still unlinked to an eval case. An unlinked
-- incident blocks the governor from re-stamping, so this is the accretion-health
-- number the scoreboard surfaces.
SELECT
    COUNT(*)                                                       AS n_incidents,
    SUM(CASE WHEN COALESCE(TRIM(linked_case), '') = '' THEN 1
             ELSE 0 END)                                           AS n_unlinked
FROM incidents;

-- name: unlinked
-- The specific unlinked incidents, for the per-incident lines in the report.
SELECT id, trigger, dispatch
FROM incidents
WHERE COALESCE(TRIM(linked_case), '') = ''
ORDER BY id;
