#!/usr/bin/env python3
"""Print the shared Agent Governance Lab worktree freshness hash."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "rails"))

from agl.worktree import WorktreeHashError, tree_hash  # noqa: E402


try:
    sys.stdout.write(tree_hash(Path.cwd()))
except (OSError, WorktreeHashError) as exc:
    print(f"tree hash failed: {exc}", file=sys.stderr)
    raise SystemExit(1) from exc
