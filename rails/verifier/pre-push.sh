#!/usr/bin/env bash
#
# pre-push: structural push gate. Fires at the git layer (not the shell layer),
# so no amount of shell indirection can bypass it. Push is allowed only when
# ALICE_PUSH_OK=1 is set — a human export in the terminal session.
#
# Installed by install.sh; removed by eject.sh. Lives in the trust layer.
#
if [ "${ALICE_PUSH_OK:-0}" != "1" ]; then
  echo "PUSH BLOCKED by 3xit2 pre-push hook." >&2
  echo "Push is a human floor act. To push: export ALICE_PUSH_OK=1" >&2
  exit 1
fi
exit 0
