#!/usr/bin/env bash
#
# run.sh [command...] -- run a command (default: an interactive shell) against
# the repo inside a container where the trust layer is READ-ONLY and there is
# no network. This is the OS-level boundary for the threat model the in-process
# guards explicitly do NOT cover: an agent that writes files through a language
# interpreter (AUDIT.md "B4") or otherwise reaches past the regex guards.
#
# What the boundary enforces, at the filesystem/kernel level (not by pattern):
#   - rails/verifier, rails/adversarial, .claude/hooks, .claude/settings.json,
#     and rails/observers are mounted READ-ONLY: an interpreter write to them
#     fails with EROFS, no matter how it is invoked.
#   - --network=none: the loop cannot push, fetch, or reach any third party.
#   - the agent works in a writable copy; you review and apply on the host.
#
# This is OPTIONAL and not part of the zero-dependency core; it needs Docker or
# Podman. Verify the boundary with selftest.sh before relying on it.
#
set -euo pipefail

ENGINE="${RAILS_CONTAINER_ENGINE:-}"
if [ -z "$ENGINE" ]; then
  if command -v docker >/dev/null 2>&1; then ENGINE=docker
  elif command -v podman >/dev/null 2>&1; then ENGINE=podman
  else
    echo "run.sh: no container engine found (need docker or podman). This is the" >&2
    echo "        OS-isolation companion; install one, or run the loop on the host" >&2
    echo "        under the in-process guards (cooperative threat model only)." >&2
    exit 1
  fi
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${RAILS_ISOLATE_IMAGE:-rails-isolate}"

# Build the image if it is missing (cheap; cached after first run).
if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "run.sh: building $IMAGE ..." >&2
  "$ENGINE" build -t "$IMAGE" "$REPO/isolate"
fi

# Read-only overlays for the trust layer, layered over a read-write repo mount.
RO=(
  -v "$REPO/rails/verifier:/work/rails/verifier:ro"
  -v "$REPO/rails/adversarial:/work/rails/adversarial:ro"
  -v "$REPO/rails/observers:/work/rails/observers:ro"
  -v "$REPO/.claude/hooks:/work/.claude/hooks:ro"
  -v "$REPO/.claude/settings.json:/work/.claude/settings.json:ro"
  # config.json holds the verifier's inputs (test_cmd, count_regex, posture):
  # read-only so the loop can't rewrite the test command to fake the suite.
  -v "$REPO/rails/config.json:/work/rails/config.json:ro"
)

exec "$ENGINE" run --rm -it \
  --network=none \
  -v "$REPO:/work" \
  "${RO[@]}" \
  -w /work \
  "$IMAGE" \
  "${@:-bash}"
