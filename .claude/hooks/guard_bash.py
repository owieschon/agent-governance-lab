#!/usr/bin/env python3
"""
PreToolUse guard for the Bash tool. Enforces the boundary rules:
the loop's autonomy ends before anything irreversible or judgment-laden.

Exit 0 = allow the command.
Exit 2 = block; stderr is fed back to the agent as the reason.

This file lives in the trust layer. It is intentionally NOT agent-editable
(guard_files.py enforces that). Humans edit it; the loop does not.
"""
import json
import os
import re
import subprocess
import sys


def _hard_block(msg: str):
    print(msg, file=sys.stderr)
    sys.exit(2)


try:
    data = json.load(sys.stdin)
except Exception:
    # Fail closed: unparseable input blocks rather than silently allowing.
    # A JSON parse failure that exits 0 would disable ALL bash guards.
    _hard_block("GUARD: could not parse tool input (fail closed). Retry the command; if this persists, report it in the handoff.")

cmd = (data.get("tool_input") or {}).get("command", "") or ""
if not cmd.strip():
    sys.exit(0)

proj = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

cfg = {}
try:
    with open(os.path.join(proj, "rails", "config.json")) as f:
        cfg = json.load(f)
except Exception:
    pass

main_branch = cfg.get("main_branch", "main")
allow_local_commits = bool(cfg.get("allow_local_commits", False))

# ---- observe mode (D63): record-don't-block, except the catastrophic floor ---
sys.path.insert(0, os.path.join(proj, "rails", "verifier"))
try:
    import observe as _observe
    OBSERVE = _observe.mode(proj) == "observe"
except Exception:
    _observe = None
    OBSERVE = False


def floor(msg: str):
    """Catastrophic floor: irreversible / outbound / apparatus. Blocks in EVERY
    mode -- observe included. You cannot observe-and-recover from a push, a
    history rewrite, leaked credentials, a migration, destroyed uncommitted
    work, an eject, or a write to the layer's own apparatus."""
    print(msg, file=sys.stderr)
    sys.exit(2)


def deny(msg: str):
    """A boundary. enforce: block (exit 2). observe: RECORD the crossing and
    ALLOW (exit 0) -- the behavior is the dataset, not a thing to halt."""
    if OBSERVE and _observe is not None:
        _observe.record(proj, "bash_boundary", msg, command=cmd[:500])
        sys.exit(0)
    print(msg, file=sys.stderr)
    sys.exit(2)

# Posture (Job 8, D25): guards are the GATING layer, so reading posture here is
# legitimate (verify.sh and the checks never read it -- that invariant stands).
# Posture splits this guard's denials into two classes:
#   FLOOR (posture-independent, unreachable from any setting): push, force-push,
#     merge, history rewrites, hard reset, work-destroying HEAD moves,
#     dependency adds (supply chain/spend), migrations (irreversible), every
#     trust-layer/self-protection path, baseline shrink.
#   CEREMONY (the dispatch-lifecycle discipline): the commit boundary and the
#     test-file write gate. In the default posture nothing outside the floor is
#     blocked, so quiet relaxes ONLY these two. Verification is unchanged:
#     verify.sh still runs, still records, still reports a tampered oracle.
posture = str(cfg.get("posture", "standard"))
ceremony_gating = posture != "quiet"

# ---- role posture enforcement (spec §1: posture = named permission profile) -
# When CLAUDE_AGENT_NAME is set, load the posture file. A reviewer-posture
# agent is blocked from any bash command that writes to the work tree (the
# WRITE_TOKENS heuristic catches shell writes). Read-only commands pass through.
import fnmatch as _fnmatch
_agent_name = os.environ.get("CLAUDE_AGENT_NAME", "")
_posture = {}
if _agent_name:
    _posture_path = os.path.join(proj, "rails", "verifier", "postures",
                                 _agent_name + ".json")
    if os.path.isfile(_posture_path):
        try:
            _posture = json.load(open(_posture_path))
        except Exception:
            pass

PROTECTED_PATHS = [
    "rails/verifier",
    ".claude/hooks",
    ".claude/settings.json",
    ".claude/settings.local.json",
    "rails/evidence",      # only verify.sh writes verdicts
    "rails/adversarial",   # the eval is part of the governor
    "rails/config.json",   # verifier inputs; softening = weakening
    "GOVERNOR_LOG.md",     # append-only ledger (historical record)
]

DEFAULT_MIGRATION_PATTERNS = [
    "prisma migrate",
    "alembic upgrade",
    "alembic downgrade",
    "supabase db push",
    "supabase db reset",
    "drizzle-kit push",
    "drizzle-kit migrate",
    "rails db:migrate",
    "manage.py migrate",
    "flyway migrate",
    "atlas migrate apply",
]


def run_git(args):
    try:
        return subprocess.run(
            ["git"] + args, capture_output=True, text=True, cwd=proj, timeout=10
        )
    except Exception:
        return None


def has_unpushed_work() -> bool:
    """Uncommitted changes OR commits on any local branch not on any remote."""
    r = run_git(["status", "--porcelain"])
    if r is None or r.returncode != 0:
        return True  # can't tell -> assume the dangerous case
    if r.stdout.strip():
        return True
    r = run_git(["log", "--branches", "--not", "--remotes", "--oneline", "-1"])
    return bool(r and r.stdout.strip())


# ---- full-command scan: push via indirection (structural, before segments) ----
# Shell indirection can hide "git push" from per-segment regex. Scan the full
# unsplit command for push invoked via common prefix forms. This is defense-in-
# depth alongside the pre-push git hook (which catches ALL push attempts at the
# git layer regardless of how they're invoked).
_PUSH_INDIRECT = re.compile(
    r"(?:^|[;&|])\s*"                          # start or chain separator
    r"(?:\w+=\S+\s+|/\S*/|env\s+|command\s+|exec\s+)*"  # env-var assignments + prefixes
    r"git\s+(?:-c\s+\S+\s+|-C\s+\S+\s+|--\S+\s+)*"      # global flags (e.g. -c k=v) before the subcommand
    r"push",
    re.MULTILINE
)
if _PUSH_INDIRECT.search(cmd):
    floor("BOUNDARY: git push (detected via indirection). "
          "Pushes are human-only. Hand off to the human.")

# Also catch push hidden inside bash -c / sh -c
if re.search(r'''(?:bash|sh)\s+-c\s+["'].*git\s+push''', cmd):
    floor("BOUNDARY: git push inside bash -c / sh -c. "
          "Pushes are human-only. Hand off to the human.")

# ---- config injection that disables the push backstop (B1-B4, defense-in-depth) -
# `git -c core.hooksPath=...` disables git hooks (the pre-push backstop);
# `git -c alias.<name>=...` alias-expands to push or another boundary op; the
# GIT_CONFIG_* env vars inject the same config out of band. Each evades both the
# per-segment regex and (by disabling hooks) the git-layer pre-push hook. These
# are the known vectors only -- a regex over a shell string is NOT a sandbox;
# the class is architectural (AUDIT.md), so this hardens, it does not seal. For
# a hostile agent, isolate at the OS level.
if re.search(r"-c\s+core\.hookspath\s*=", cmd, re.IGNORECASE):
    floor("BOUNDARY: 'git -c core.hooksPath=' disables git hooks (the push "
          "backstop). Human-only; hand off.")
if re.search(r"-c\s+alias\.", cmd, re.IGNORECASE):
    floor("BOUNDARY: 'git -c alias.<name>=' can expand to push or another "
          "boundary op. Human-only; hand off.")
if re.search(r"\bGIT_CONFIG_(?:COUNT|KEY_\d+|VALUE_\d+|PARAMETERS)\b", cmd):
    floor("BOUNDARY: GIT_CONFIG_* environment config injection (can set "
          "core.hooksPath or aliases). Human-only; hand off.")

# Heuristic: evaluate each segment of a chained command independently.
segments = re.split(r"(?:&&|\|\||;|\|)", cmd)

WRITE_TOKENS = re.compile(
    r"(>>?|\btee\b|\bsed\s+-i|\brm\b|\bmv\b|\bcp\b|\bchmod\b|\btruncate\b"
    r"|\bln\b|\bdd\b|\bpatch\b|\binstall\b)"
)

for seg in segments:
    s = seg.strip()
    if not s:
        continue

    # ---- role posture: reviewer write-block (before all other checks) ------
    # A reviewer-posture agent is blocked from any bash command that writes
    # to paths outside its writable set. The reviewer's writable set is the
    # findings artifact only; everything else is read-only.
    # A non-wildcard posture (e.g. the reviewer) gets DEFAULT-DENY on shell
    # writes: any write token denies unconditionally. We do NOT match the
    # writable glob against the raw command text -- substring matching is
    # bypassable (a decoy path in a comment, a string arg, or an unrelated
    # read-source flips it; HIGH finding, automated review 2026-06-11:
    # `tee /etc/x < rails/evidence/decoy` contains the writable substring and
    # escaped). The role writes its permitted paths with the Edit/Write tool,
    # which guard_files.py checks with proper fnmatch path-resolution; shell
    # redirection is never the write channel for a restricted posture.
    if _posture.get("writable") and _posture["writable"] != ["*"] and WRITE_TOKENS.search(s):
        deny(
            f"POSTURE ({_agent_name}): shell writes are not permitted for the "
            f"{_agent_name} posture (read-only on the work tree). Write your "
            "permitted output (e.g. the findings file) with the Edit/Write "
            "tool -- its path is checked against the posture, not the raw "
            "command text. This is guard-enforced, not prompted."
        )

    # ---- trust-layer paths reached through the shell --------------------
    for p in PROTECTED_PATHS:
        if p in s and WRITE_TOKENS.search(s):
            # Apparatus (verifier/hooks/settings/eval) is floor even in observe
            # -- editing it disables the layer. Governed content (evidence,
            # config) records-and-allows in observe.
            (floor if (_observe and _observe.is_apparatus(p)) else deny)(
                f"BLOCKED: '{p}' is trust-layer (not agent-editable). "
                "State the change; the human makes it."
            )
    if "--update-baseline" in s and "--allow-shrink" in s:
        floor(
            "BLOCKED: --allow-shrink is human-only (lowering the baseline hides "
            "deleted tests). Report the needed shrink in the handoff."
        )
    # eject removes the trust layer itself -- the ultimate self-protection
    # breach. FLOOR-class (posture-independent): the loop can never run it, in
    # any posture. Ejecting is a deliberate human teardown.
    if re.search(r"\beject\.sh\b", s):
        floor(
            "BLOCKED: eject.sh is human-only (removes the trust layer). "
            "Describe why in the handoff and stop."
        )
    if "rails/incidents" in s and WRITE_TOKENS.search(s):
        deny(
            "BLOCKED: incident records are append-only. "
            "Write new records only; do not delete or rewrite existing ones."
        )

    # ---- rails/observers: definitions + runner are governor-adjacent (D59) --
    # They shape what the operator sees in the inbox, so agents never edit
    # them. Path-prefix rule: in force BEFORE the files exist. The one
    # agent-writable carve-out is the observer state dir; conservative
    # matching: EVERY observers-path mention must be under state/ (a decoy
    # state path can only false-block, never unlock).
    if "rails/observers" in s and WRITE_TOKENS.search(s):
        # Resolve each candidate path before matching (D47): a literal-prefix
        # test on the command text is bypassable by traversal --
        # 'rails/observers/state/../run_observer.sh' string-prefixes the state
        # dir but resolves OUTSIDE it. Realpath-resolve and require the real
        # target to be under the resolved state dir.
        _state_root = os.path.realpath(
            os.path.join(proj, "rails", "observers", "state"))
        _obs = re.findall(r"rails/observers[^\s;|&'\"]*", s)

        def _under_state(m):
            rp = os.path.realpath(os.path.join(proj, m))
            return rp == _state_root or rp.startswith(_state_root + os.sep)

        if not all(_under_state(m) for m in _obs):
            deny(
                "BLOCKED: rails/observers/ (definitions + runner) is "
                "governor-adjacent and not agent-editable; only "
                "rails/observers/state/ is agent-writable. State the change; "
                "the human makes it."
            )

    # ---- dispatch inbox: CREATE-ONLY for agents (D59) ------------------------
    # New inbox items may be created; an EXISTING item is never edited,
    # overwritten, renamed, or deleted by any agent (tampering with a proposal
    # rewrites what the human sees at the approval gate). The ONE permitted
    # mutation is the documented /dispatch consumption flow: mv / git mv of an
    # inbox file OUT into the dispatch's sources/ dir. The destination is
    # realpath-resolved so sources/../ traversal cannot smuggle a move
    # elsewhere.
    INBOX = "rails/dispatches/inbox"
    if INBOX in s:
        _mv = re.match(r"^(?:git\s+)?mv\s+(.*)$", s)
        if _mv:
            _argv = [a for a in _mv.group(1).split() if not a.startswith("-")]
            _dest = _argv[-1] if len(_argv) >= 2 else ""
            # Resolve the ACTUAL destination as written (D47), not a
            # reconstructed in-project slice: a dest like
            # '/tmp/x/rails/dispatches/active/<id>/sources/' string-contains
            # the magic prefix but the mv actually lands in /tmp/x. join()
            # ignores proj when _dest is absolute, so realpath sees the true
            # target; traversal ('active/../../tmp') resolves out of bounds.
            _aroot = os.path.realpath(
                os.path.join(proj, "rails", "dispatches", "active"))
            _dap = os.path.realpath(os.path.join(proj, _dest))
            _parts = os.path.relpath(_dap, _aroot).split(os.sep)
            _ok = (len(_parts) >= 2 and ".." not in _parts
                   and _parts[1] == "sources")
            if not _ok:
                deny(
                    "BLOCKED: inbox items are create-only. The only permitted "
                    "move is /dispatch consumption into "
                    "rails/dispatches/active/<id>/sources/. Never rename, "
                    "overwrite, or relocate inbox items elsewhere."
                )
        elif re.search(r"\brm\b", s):
            deny(
                "BLOCKED: inbox items are create-only; never delete them. "
                "To consume an item, move it into "
                "rails/dispatches/active/<id>/sources/ via /dispatch; "
                "for removal, ask the human."
            )
        elif WRITE_TOKENS.search(s):
            for _tok in re.findall(r"rails/dispatches/inbox/[^\s;|&'\"]+", s):
                if os.path.exists(os.path.realpath(os.path.join(proj, _tok))):
                    deny(
                        "BLOCKED: '" + _tok + "' is an existing inbox item "
                        "(create-only). Write NEW inbox files; never edit or "
                        "overwrite existing ones."
                    )
    test_glob = cfg.get("test_glob", "")
    if ceremony_gating and test_glob and (test_glob in s or "conftest" in s) \
            and WRITE_TOKENS.search(s):
        deny(
            f"BLOCKED: shell writes to test files ('{test_glob}'/conftest) are "
            "blocked. Add new tests via the editor; declare existing test changes "
            "in the manifest."
        )
    if ".oracle_snapshot.json" in s and WRITE_TOKENS.search(s):
        deny(
            "BLOCKED: oracle snapshot is tamper-protected. Only snapshot.sh writes it."
        )
    if ".base_ref" in s and WRITE_TOKENS.search(s):
        deny(
            "BLOCKED: the dispatch base ref is tamper-protected. Only basis.sh writes it."
        )

    g = re.match(r"^git\s+(.*)$", s)
    if not g:
        # ---- non-git boundaries -----------------------------------------
        # Dependency add/change: named-package installs blocked,
        # lockfile-faithful installs allowed.
        m = re.match(r"^(npm|pnpm|yarn|bun)\s+(add|install|i)\b(.*)$", s)
        if m:
            rest = m.group(3).strip()
            names_pkg = any(not a.startswith("-") for a in rest.split())
            if m.group(2) == "add" or names_pkg:
                deny(
                    "BLOCKED: adding dependencies is human-only. Propose the "
                    "dependency in the handoff. (npm ci / npm install from lockfile is allowed.)"
                )
        if re.match(r"^pip3?\s+install\s+", s) and not re.search(
            r"(-r\s|--requirement|\s-e\s|--editable)", s
        ):
            deny(
                "BLOCKED: adding Python dependencies is human-only. "
                "(-r and -e are allowed.) Propose new packages in the handoff."
            )
        if re.match(r"^(poetry|cargo|uv)\s+add\s+", s):
            deny("BLOCKED: adding dependencies is human-only. "
             "Propose the dependency in the handoff.")

        for pat in cfg.get("migration_patterns", DEFAULT_MIGRATION_PATTERNS):
            if pat in s:
                floor(
                    "BLOCKED: migrations are human-only. "
                    "Write the migration file; the human runs it."
                )
        continue

    gargs = g.group(1).strip()

    # ---- always-blocked git operations ----------------------------------
    if re.match(r"^push\b", gargs) and re.search(r"(\s--force(-with-lease)?\b|\s-f\b|\s\+\S)", gargs):
        floor("BLOCKED: force-push is human-only. "
              "Stop and hand the situation to the human.")
    if re.match(r"^push\b", gargs):
        floor(
            "BLOCKED: push is human-only. "
            "Hand off; the human reviews, commits, and pushes."
        )
    if re.match(r"^merge\b", gargs):
        deny("BLOCKED: merge is human-only. Stop at the handoff.")
    if re.match(r"^(rebase|filter-branch|filter-repo|update-ref)\b", gargs) or re.match(
        r"^reflog\s+expire\b", gargs
    ):
        floor("BLOCKED: history rewrites are human-only. "
              "Describe what you need in the handoff.")
    if re.match(r"^reset\b.*--hard", gargs):
        floor("BLOCKED: hard reset is human-only. "
              "State what needs resetting in the handoff.")
    if re.match(r"^commit\b.*--amend", gargs):
        deny("BLOCKED: --amend is human-only. "
             "Make a new commit, or report the fix in the handoff.")
    if re.match(r"^branch\b.*\s-D\b", gargs):
        deny("BLOCKED: force-deleting branches is human-only. "
             "Name the branch and reason in the handoff; the human deletes it.")
    # ---- git config mutations that bypass other guards ----------------------
    # Aliases can disguise push (alias.save=push -> git save), hooksPath can
    # redirect to attacker-controlled hooks, remote URLs can redirect push
    # targets, credential helpers can exfiltrate tokens.
    if re.match(r"^config\b", gargs):
        cfg_arg = gargs[len("config"):].strip()
        if re.match(r"(?i)alias\.", cfg_arg):
            floor("BOUNDARY: git config alias.* is blocked — aliases can disguise "
                  "push/merge as innocent commands. State the alias you need; "
                  "the human sets it.")
        if re.match(r"(?i)core\.hookspath\b", cfg_arg):
            floor("BLOCKED: git config core.hooksPath is blocked. "
                  "State why you need it in the handoff; the human sets it.")
        if re.match(r"(?i)remote\.\S+\.url\b", cfg_arg):
            floor("BLOCKED: git config remote.*.url is blocked. "
                  "State the remote change in the handoff; the human sets it.")
        if re.match(r"(?i)credential\.", cfg_arg):
            floor("BLOCKED: git config credential.* is blocked. "
                  "State the credential config in the handoff; the human sets it.")
    if re.match(r"^commit\b", gargs) and not allow_local_commits and ceremony_gating:
        # Ceremony-class, not floor: in quiet the user commits as they always
        # did (L5); pushes stay blocked in every setting.
        deny(
            "BLOCKED: commit is human-gated. Produce the handoff; the human "
            "commits. (Set allow_local_commits=true in config to permit WIP commits.)"
        )

    # ---- HEAD-moving ops, gated on unpushed work (the standing git note) -
    head_moving = bool(
        (re.match(r"^checkout\b", gargs) and not re.match(r"^checkout\s+-b\b", gargs))
        or (
            re.match(r"^switch\b", gargs)
            and not re.match(r"^switch\s+(-c|--create)\b", gargs)
        )
        or re.match(r"^stash\b", gargs)
        or re.match(r"^reset\b", gargs)
        or re.match(r"^clean\b.*\s-[a-zA-Z]*f", gargs)
    )
    if head_moving and has_unpushed_work():
        floor(
            "BLOCKED: unpushed/uncommitted work present — HEAD-moving ops "
            "(checkout/switch/reset/stash/clean) blocked. Build on top of HEAD."
        )

sys.exit(0)
