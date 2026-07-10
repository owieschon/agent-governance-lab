#!/usr/bin/env python3
"""Strictly verify the separate engineering case; optionally check its public pin."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "rails"))

from agl.comparison import validate_engineering_decision  # noqa: E402


def normalized_contains(source: str, fragment: str) -> bool:
    return " ".join(fragment.split()) in " ".join(source.split())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fetch-source",
        action="store_true",
        help="also fetch the immutable public source and verify its SHA-256/evidence fragments",
    )
    args = parser.parse_args()
    path = ROOT / "experiment/engineering-decision.json"
    case = json.loads(path.read_text(encoding="utf-8"))
    validate_engineering_decision(case)

    if args.fetch_source:
        source = case["source"]
        url = (
            "https://raw.githubusercontent.com/"
            f"{source['repository']}/{source['commit']}/{source['path']}"
        )
        with urlopen(url, timeout=15) as response:  # noqa: S310 - immutable public commit
            body = response.read()
        digest = hashlib.sha256(body).hexdigest()
        if digest != source["sha256"]:
            raise SystemExit(
                f"source digest mismatch: expected {source['sha256']}, got {digest}"
            )
        text = body.decode("utf-8")
        fragments = (
            "ran all 127/127 gold",
            "all 63 clean-layer and 64 hard-layer items",
            "0.98 — out of band",
            "[1.0, 1.0]",
            "hard-layer `fp`",
            "Not committing a `transport_fidelity: pass` artifact",
        )
        missing = [fragment for fragment in fragments if not normalized_contains(text, fragment)]
        if missing:
            raise SystemExit(f"pinned source is missing required evidence: {missing}")

    mode = "schema, semantics, and public source pin" if args.fetch_source else "schema and decision semantics"
    print(f"PASS: engineering case preserves {mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
