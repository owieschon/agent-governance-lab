#!/usr/bin/env python3
"""Run the full-repository lint gate with the reviewed Ruff release."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
RUFF_VERSION = "0.15.18"


def main() -> int:
    version = subprocess.run(
        [sys.executable, "-m", "ruff", "--version"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    expected = f"ruff {RUFF_VERSION}"
    if version.returncode != 0 or version.stdout.strip() != expected:
        actual = version.stdout.strip() or version.stderr.strip() or "not installed"
        print(
            f"FAIL: expected {expected}; found {actual}. "
            f"Install with: {sys.executable} -m pip install ruff=={RUFF_VERSION}",
            file=sys.stderr,
        )
        return 2
    return subprocess.run(
        [sys.executable, "-m", "ruff", "check", "."],
        cwd=ROOT,
        check=False,
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
