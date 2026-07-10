#!/usr/bin/env bash
# Compatibility entrypoint. The canonical interface is `agl demo`; this path
# remains because installed repositories and the existing slash command call it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/bin/agl" demo "$@"
