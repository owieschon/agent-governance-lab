#!/usr/bin/env bash
# Inbox create-only (D59, Bundle 4 phase A): rails/dispatches/inbox/ holds the
# proposals the human approves from. ANY agent may CREATE a new item; NO agent
# may edit, overwrite, rename, or delete an existing one -- tampering with a
# proposal rewrites what the human sees at the approval gate. The ONE
# permitted mutation is the documented /dispatch consumption flow: moving a
# consumed inbox file into the dispatch's sources/ dir. That flow is proven
# here END-TO-END as the negative assertion: the guard must not block it.
source "$(dirname "$0")/../../lib.sh"
cd "$SANDBOX"

mkdir -p rails/dispatches/inbox rails/dispatches/active/D-test/sources
echo "human spec: ship the thing" > rails/dispatches/inbox/feature-spec.md
git add rails/dispatches/inbox/feature-spec.md
git commit -qm "inbox: feature-spec"

# --- RED: tampering with an existing item (worker, no posture) ----------------
expect_blocked "Edit tool on existing inbox item"      "$(agent_edit "$SANDBOX/rails/dispatches/inbox/feature-spec.md")"
expect_blocked "shell overwrite (>) existing item"     "$(agent_bash 'echo evil > rails/dispatches/inbox/feature-spec.md')"
expect_blocked "shell append (>>) existing item"       "$(agent_bash 'echo evil >> rails/dispatches/inbox/feature-spec.md')"
expect_blocked "sed -i on existing item"               "$(agent_bash 'sed -i.bak s/spec/evil/ rails/dispatches/inbox/feature-spec.md')"
expect_blocked "rm an inbox item"                      "$(agent_bash 'rm rails/dispatches/inbox/feature-spec.md')"
expect_blocked "rm -rf the whole inbox"                "$(agent_bash 'rm -rf rails/dispatches/inbox')"
expect_blocked "cp over an existing item"              "$(agent_bash 'cp /tmp/evil.md rails/dispatches/inbox/feature-spec.md')"
expect_blocked "mv over an existing item (overwrite)"  "$(agent_bash 'mv evil.md rails/dispatches/inbox/feature-spec.md')"
expect_blocked "rename within the inbox"               "$(agent_bash 'mv rails/dispatches/inbox/feature-spec.md rails/dispatches/inbox/renamed.md')"
expect_blocked "move-out to a non-dispatch dest"       "$(agent_bash 'mv rails/dispatches/inbox/feature-spec.md /tmp/gone.md')"
expect_blocked "traversal escape via sources/../"      "$(agent_bash 'git mv rails/dispatches/inbox/feature-spec.md rails/dispatches/active/D-test/sources/../../../../tmp/esc.md')"
# the dest must be VALIDATED AS WRITTEN, not via a reconstructed in-project
# slice: an absolute dest that merely CONTAINS the magic substring lands
# outside the repo (caught by realpath-resolving the actual destination)
expect_blocked "move-out via absolute dest embedding the magic substring" \
  "$(agent_bash 'mv rails/dispatches/inbox/feature-spec.md /tmp/evil/rails/dispatches/active/D-test/sources/stolen.md')"

# --- GREEN: creating a NEW item stays open (any agent) -------------------------
expect_allowed "Edit tool creates a NEW inbox item"    "$(agent_edit "$SANDBOX/rails/dispatches/inbox/new-idea.md")"
expect_allowed "shell creates a NEW inbox item"        "$(agent_bash 'echo idea > rails/dispatches/inbox/new-idea.md')"

# --- GREEN (negative assertion): the documented /dispatch consumption flow ----
expect_allowed "guard allows: git mv inbox item -> dispatch sources/" \
  "$(agent_bash 'git mv rails/dispatches/inbox/feature-spec.md rails/dispatches/active/D-test/sources/feature-spec.md')"
expect_allowed "guard allows: plain mv into the sources/ dir form" \
  "$(agent_bash 'mv rails/dispatches/inbox/feature-spec.md rails/dispatches/active/D-test/sources/')"

# allowed is not enough; demonstrate the documented flow actually EXECUTES
git mv rails/dispatches/inbox/feature-spec.md rails/dispatches/active/D-test/sources/feature-spec.md
_assert "consumed item landed in sources/" 1 \
  "$([ -f rails/dispatches/active/D-test/sources/feature-spec.md ] && echo 1 || echo 0)"
_assert "inbox no longer holds the consumed item" 0 \
  "$([ -f rails/dispatches/inbox/feature-spec.md ] && echo 1 || echo 0)"

finish
