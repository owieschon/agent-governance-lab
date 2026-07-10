#!/usr/bin/env python3
"""Render or verify the reviewed comparison source manifest and derived lock."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from rails.agl.comparison import (  # noqa: E402
    LOCK_VERSION,
    PROTOCOL_ID,
    TRUSTED_MANIFEST_VERSION,
    TRUSTED_SOURCE_FILES,
    engine_sha256,
    schemas_sha256,
    sha256_file,
)
from rails.agl.trust_anchor import TRUSTED_RELEASE_MANIFEST_SHA256  # noqa: E402


BINDINGS_PATH = ROOT / "experiment/bindings.json"
MANIFEST_PATH = ROOT / "experiment/trusted-release.json"


def _json_text(value: dict) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def expected_bindings() -> dict:
    return {
        "schema_version": LOCK_VERSION,
        "locked_at": "2026-07-10",
        "preregistration_sha256": sha256_file(
            ROOT / "experiment/preregistration.json"
        ),
        "corpus_sha256": sha256_file(ROOT / "experiment/corpus.json"),
        "engine_sha256": engine_sha256(ROOT),
    }


def expected_manifest() -> dict:
    return {
        "$schema": "../schemas/trusted-release.schema.json",
        "schema_version": TRUSTED_MANIFEST_VERSION,
        "protocol_id": PROTOCOL_ID,
        "locked_at": "2026-07-10",
        "files": [
            {"path": relative, "sha256": sha256_file(ROOT / relative)}
            for relative in TRUSTED_SOURCE_FILES
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    bindings = expected_bindings()
    if args.check:
        actual_bindings = (
            BINDINGS_PATH.read_text(encoding="utf-8")
            if BINDINGS_PATH.exists()
            else ""
        )
        if actual_bindings != _json_text(bindings):
            print("stale: experiment/bindings.json")
            return 1
    else:
        BINDINGS_PATH.write_text(_json_text(bindings), encoding="utf-8")

    manifest = expected_manifest()
    expected_text = _json_text(manifest)
    if args.check:
        actual_manifest = (
            MANIFEST_PATH.read_text(encoding="utf-8")
            if MANIFEST_PATH.exists()
            else ""
        )
        if actual_manifest != expected_text:
            print("stale: experiment/trusted-release.json")
            return 1
    else:
        MANIFEST_PATH.write_text(expected_text, encoding="utf-8")

    manifest_sha256 = sha256_file(MANIFEST_PATH)
    if args.check and manifest_sha256 != TRUSTED_RELEASE_MANIFEST_SHA256:
        print(
            "untrusted: experiment/trusted-release.json differs from "
            "rails/agl/trust_anchor.py"
        )
        return 1

    print(f"trusted_release_sha256={manifest_sha256}")
    print(f"engine_sha256={bindings['engine_sha256']}")
    print(f"schemas_sha256={schemas_sha256(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
