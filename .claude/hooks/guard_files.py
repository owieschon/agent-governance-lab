#!/usr/bin/env python3
"""
PreToolUse guard for Edit/Write/MultiEdit/NotebookEdit. Enforces the cardinal
invariant (the cardinal rule): the loop never fixes its own verifier.

Protected from agent edits:
  - rails/verifier/**        (the checks, the baseline, the load-bearing list)
  - .claude/hooks/**         (these guards)
  - .claude/settings.json    (hook registration)
  - every file listed in rails/verifier/load_bearing.txt
    (the agent may ADD coverage in NEW files; it may not touch a
     load-bearing test, because weakening one is exactly the failure
     this framework exists to prevent)

Exit 0 = allow. Exit 2 = block with reason on stderr.
"""
import fnmatch
import json
import os
import sys


def _hard_block(msg: str):
    print(msg, file=sys.stderr)
    sys.exit(2)


try:
    data = json.load(sys.stdin)
except Exception:
    # Fail closed: unparseable input blocks rather than silently allowing.
    _hard_block("GUARD: could not parse tool input (fail closed). Retry the command; if this persists, report it in the handoff.")

ti = data.get("tool_input") or {}
path = ti.get("file_path") or ti.get("notebook_path") or ti.get("path") or ""
if not path:
    sys.exit(0)

proj = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
# Resolve symlinks: abspath does NOT follow symlinks, so ln -s protected /tmp/x
# lets a write to /tmp/x silently hit the protected file. realpath resolves the
# full chain, closing the entire symlink-attack class.
ap = os.path.realpath(path if os.path.isabs(path) else os.path.join(proj, path))
try:
    rel = os.path.relpath(ap, proj)
except ValueError:
    rel = ap


# Case-insensitive filesystems (stock macOS, default Windows) resolve
# RAILS/VERIFIER/baseline.json to the SAME file as rails/verifier/baseline.json,
# but the case-sensitive string compares below would miss the variant -- a guard
# bypass (the write lands on the real protected file). Detect the filesystem
# once and fold case in the protected-path comparisons when it is
# case-insensitive. On a case-sensitive filesystem a differently-cased path is a
# genuinely different file, so _n is the identity and behavior is unchanged.
def _fs_case_insensitive(base):
    try:
        lower = os.path.join(base, "rails")
        upper = os.path.join(base, "RAILS")
        return (os.path.isdir(lower) and os.path.isdir(upper)
                and os.path.samefile(lower, upper))
    except Exception:
        return False


CI_FS = _fs_case_insensitive(proj)


def _n(s):
    return s.lower() if CI_FS else s


# ---- observe mode (D63): record-don't-block, except the apparatus floor ------
sys.path.insert(0, os.path.join(proj, "rails", "verifier"))
try:
    import observe as _observe
    OBSERVE = _observe.mode(proj) == "observe"
except Exception:
    _observe = None
    OBSERVE = False


def floor(msg: str):
    """Apparatus floor: writes that would blind/disable the trust layer itself.
    Blocks in EVERY mode -- you cannot observe the agent if it can edit the
    camera (hooks, settings, verifier, eval)."""
    print(msg, file=sys.stderr)
    sys.exit(2)


def deny(msg: str):
    """A protected-content boundary. enforce: block. observe: RECORD + ALLOW --
    the agent editing its own oracle / forging a verdict IS the behavior we want
    to see, not suppress (it is recoverable; the apparatus is not)."""
    if OBSERVE and _observe is not None:
        _observe.record(proj, "file_write", msg, path=rel)
        sys.exit(0)
    print(msg, file=sys.stderr)
    sys.exit(2)


# The apparatus is floor even in observe mode -- editing it breaks observation.
if _observe is not None and _observe.is_apparatus(rel):
    floor(
        f"BLOCKED: {rel} is trust-layer apparatus (hooks/settings/verifier/eval) "
        "-- not agent-editable in ANY mode. Editing it would disable the layer "
        "itself. State the change; the human makes it."
    )

# ---- role posture enforcement (spec §1: posture = named permission profile) -
# When CLAUDE_AGENT_NAME is set, load the posture file and enforce its write
# restrictions. A role with no posture file falls through to default (worker)
# behavior. The reviewer posture is the first instantiation: read-only on the
# work tree, write only to the findings path in run artifacts.
#
# Architecture: posture has TWO effects:
#   1. RESTRICT: non-worker postures block writes outside their writable set.
#   2. GRANT: posture-granted writable paths carve out the trust-layer block
#      for that specific pattern (the reviewer MUST write to rails/evidence/,
#      which is otherwise protected). The carve-out is scoped: it only applies
#      to the exact patterns in the posture file, not the whole prefix.
_agent_name = os.environ.get("CLAUDE_AGENT_NAME", "")
_posture = {}
_posture_granted = False  # True if the write is to a posture-granted path
if _agent_name:
    _posture_path = os.path.join(proj, "rails", "verifier", "postures",
                                 _agent_name + ".json")
    if os.path.isfile(_posture_path):
        try:
            _posture = json.load(open(_posture_path))
        except Exception:
            pass
        _writable = _posture.get("writable", ["*"])
        # Check if the target path matches any writable pattern
        _write_allowed = False
        for _pat in _writable:
            if _pat == "*":
                _write_allowed = True
                break
            if fnmatch.fnmatch(rel, _pat):
                _write_allowed = True
                _posture_granted = True  # explicitly granted by posture
                break
        if not _write_allowed:
            deny(
                f"POSTURE ({_agent_name}): write to '{rel}' is outside the "
                f"{_agent_name} posture's writable paths. The {_agent_name} role "
                "is read-only on the work tree; findings go to the evidence "
                "directory only. This is guard-enforced, not prompted."
            )

PROTECTED_PREFIXES = [
    "rails/verifier",      # the checks, baseline, load-bearing list
    ".claude/hooks",       # these guards
    "rails/evidence",      # verdicts: only verify.sh writes here; a forged
                           # PASS is the self-grading loop in miniature
    "rails/adversarial",   # the eval that proves the checks fire; if the
                           # agent could edit it, weaken-a-check dies first
    "rails/observers",     # observer definitions + runner are governor-
                           # adjacent: they shape what the operator sees in
                           # the inbox (D59). Path-prefix rule, in force
                           # before the files exist; state/ carved out below.
]
# The one agent-writable surface under rails/observers/: each observer's own
# dedup/memory state (D59). Definitions and the runner stay protected.
OBSERVER_STATE = os.path.join("rails", "observers", "state")
PROTECTED_FILES = [
    ".claude/settings.json",
    ".claude/settings.local.json",
    "rails/config.json",   # test_cmd/count_regex ARE the verifier's inputs;
                           # softening them is weakening a check
    "GOVERNOR_LOG.md",     # append-only ledger (historical record)
]

for p in PROTECTED_PREFIXES:
    if _n(rel) == _n(p) or _n(rel).startswith(_n(p) + os.sep):
        # Posture-granted carve-out: if a posture explicitly grants write
        # access to this path, skip the trust-layer block. The reviewer's
        # findings artifact lives under rails/evidence/ (normally protected),
        # but the posture file scopes the carve-out to exactly its patterns.
        if _posture_granted:
            break  # skip trust-layer block; the posture authorized this write
        if p == os.path.join("rails", "observers") and (
            _n(rel) == _n(OBSERVER_STATE)
            or _n(rel).startswith(_n(OBSERVER_STATE) + os.sep)
        ):
            continue  # observer state dir stays agent-writable (D59)
        deny(
            f"BLOCKED: {p}/ is trust-layer (not agent-editable). "
            "State the change; the human makes it via the strict posture."
        )

for p in PROTECTED_FILES:
    if _n(rel) == _n(p):
        deny(
            "BLOCKED: hook/settings config is not agent-editable. "
            "State the change; the human makes it."
        )

lb_path = os.path.join(proj, "rails", "verifier", "load_bearing.txt")
load_bearing = []
try:
    with open(lb_path) as f:
        load_bearing = [
            ln.strip() for ln in f if ln.strip() and not ln.strip().startswith("#")
        ]
except Exception:
    pass

for p in load_bearing:
    pap = os.path.realpath(os.path.join(proj, p))
    if ap == pap or (CI_FS and ap.lower() == pap.lower()):
        deny(
            f"BLOCKED: {p} is a load-bearing test (not agent-editable). "
            "Add coverage in new files; describe changes to existing tests in the handoff."
        )

# Incident ledger: records are append-only and tamper-evident. A NEW record
# may be written, but an EXISTING one is never edited or overwritten by the
# loop (the human links it to its eval case; the loop does not rewrite its own
# accountability trail).
INCIDENTS = os.path.join("rails", "incidents")
if (_n(rel) == _n(INCIDENTS) or _n(rel).startswith(_n(INCIDENTS) + os.sep)) and os.path.exists(ap):
    deny(
        "BLOCKED: incident records are append-only. "
        "Write new records only; do not edit or overwrite existing ones."
    )

# Dispatch inbox: CREATE-ONLY for agents (D59). A NEW proposal may be written;
# an EXISTING item is never edited or overwritten by ANY agent, observers
# included -- this fires even when a posture grants the inbox pattern, because
# tampering with a proposal rewrites what the human sees at the approval gate.
# Consumption happens via the documented /dispatch move into the dispatch's
# sources/ dir (a Bash-layer move-out, not a write-tool edit; guard_bash.py
# allows exactly that destination).
INBOX = os.path.join("rails", "dispatches", "inbox")
if (_n(rel) == _n(INBOX) or _n(rel).startswith(_n(INBOX) + os.sep)) and os.path.exists(ap):
    deny(
        "BLOCKED: inbox items are create-only. Write NEW inbox files; "
        "never edit, overwrite, or delete an existing item. "
        "/dispatch (human-approved) consumes items by moving them into "
        "the dispatch's sources/."
    )

# Oracle snapshot: test-file hashes recorded at dispatch approval. It grades
# scorer integrity; the loop never edits it (only snapshot.sh writes it).
if _n(os.path.basename(rel)) == ".oracle_snapshot.json":
    deny(
        "BLOCKED: oracle snapshot is tamper-protected. "
        "Only snapshot.sh writes it."
    )

# Base ref: the commit recorded at approval (HEAD before the build) that the
# verifier diffs against to tie obligations to the dispatch's real change. The
# loop never edits it (only basis.sh writes it); widening it would let a decoy
# look "changed."
if _n(os.path.basename(rel)) == ".base_ref":
    deny(
        "BLOCKED: the dispatch base ref is tamper-protected. "
        "Only basis.sh writes it (at approval)."
    )

sys.exit(0)
