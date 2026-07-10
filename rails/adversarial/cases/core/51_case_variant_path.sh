#!/usr/bin/env bash
# Boundary, case-variant form: on a case-INSENSITIVE filesystem (stock macOS,
# default Windows) a path like RAILS/VERIFIER/baseline.json resolves to the SAME
# file as the protected rails/verifier/baseline.json, so the guard must fold
# case or the variant is a write-bypass straight onto a protected file. On a
# case-SENSITIVE filesystem the variant is a genuinely different file and is
# correctly allowed -- so this case asserts per the filesystem it runs on
# (Linux CI is case-sensitive; macOS dev is case-insensitive).
source "$(dirname "$0")/../../lib.sh"

# Canonical protected paths are always blocked (the floor that must hold).
expect_blocked "canonical rails/verifier/baseline.json -> blocked" \
  "$(agent_edit "$SANDBOX/rails/verifier/baseline.json")"

if [ -d "$SANDBOX/RAILS" ]; then
  # Case-insensitive FS: the variant IS the protected file -> must block.
  expect_blocked "case-variant RAILS/VERIFIER/baseline.json -> blocked (case-insensitive FS)" \
    "$(agent_edit "$SANDBOX/RAILS/VERIFIER/baseline.json")"
  expect_blocked "case-variant .CLAUDE/HOOKS/guard_files.py -> blocked (case-insensitive FS)" \
    "$(agent_edit "$SANDBOX/.CLAUDE/HOOKS/guard_files.py")"
else
  # Case-sensitive FS: the variant is a DIFFERENT, unprotected path -> allowed.
  expect_allowed "case-variant RAILS/VERIFIER/baseline.json is a different file (case-sensitive FS) -> allowed" \
    "$(agent_edit "$SANDBOX/RAILS/VERIFIER/baseline.json")"
fi

# Clean work is never blocked: an ordinary source write is allowed.
expect_allowed "ordinary source write -> allowed" \
  "$(agent_edit "$SANDBOX/src/main.py")"

finish
