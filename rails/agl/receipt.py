"""Deterministic, provider-independent release receipts.

The receipt is a content-addressed statement over evidence that already exists.
It does not decide whether work passes. It binds an engine, candidate tree,
test run, check set, verdict, environment, and the exact outputs that support
the verdict. Verification requires only Python's standard library.
"""

from __future__ import annotations

import base64
import binascii
import copy
import hashlib
import json
import os
import re
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping

from . import PRODUCT_NAME, RECEIPT_VERSION
from .worktree import (
    WorktreeHashError,
    safe_workspace_path,
    symlink_target_bytes,
    tree_hash as shared_tree_hash,
    update_hash_frame,
)


SCHEMA_REF = "rails/agl/receipt.schema.json"
SNAPSHOT_SCHEMA_REF = "rails/agl/candidate_snapshot.schema.json"
SNAPSHOT_VERSION = "agl.candidate-snapshot.v1"
MAX_SNAPSHOT_ENTRIES = 256
MAX_SNAPSHOT_DECODED_BYTES = 1024 * 1024
MAX_SNAPSHOT_JSON_BYTES = 2 * 1024 * 1024
MAX_SNAPSHOT_PATH_BYTES = 4096
HEX64 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^(?:[0-9a-f]{40,64}|NO-GIT)$")
CHECK_ID = re.compile(r"^[a-z][a-z0-9_]*$")
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
POLICIES = {"test_only", "observe_only", "enforced"}
VERDICTS = {"RELEASED", "BLOCKED"}


class ReceiptError(ValueError):
    """The receipt is malformed, inconsistent, or no longer intact."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: str | Path) -> str:
    with Path(path).open("rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def canonical_json(value: Mapping[str, Any]) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def receipt_hash(receipt: Mapping[str, Any]) -> str:
    body = copy.deepcopy(dict(receipt))
    body.pop("receipt_sha256", None)
    return sha256_bytes(canonical_json(body))


def _safe_relative(path: str) -> PurePosixPath:
    if (
        not isinstance(path, str)
        or not path
        or "\\" in path
        or "\0" in path
        or re.match(r"^[A-Za-z]:", path)
    ):
        raise ReceiptError(f"candidate path must stay relative to the workspace: {path!r}")
    if len(path.encode("utf-8")) > MAX_SNAPSHOT_PATH_BYTES:
        raise ReceiptError(f"candidate path is unreasonably long: {path!r}")
    candidate = PurePosixPath(path)
    if (
        candidate.is_absolute()
        or ".." in candidate.parts
        or not candidate.parts
        or candidate.as_posix() != path
    ):
        raise ReceiptError(f"candidate path must be canonical and relative: {path!r}")
    return candidate


def _validate_candidate_paths(paths: Iterable[str]) -> list[str]:
    raw_paths = list(paths)
    if not raw_paths:
        raise ReceiptError("candidate paths must be a non-empty list")
    if len(raw_paths) > MAX_SNAPSHOT_ENTRIES:
        raise ReceiptError(f"candidate paths exceed {MAX_SNAPSHOT_ENTRIES} entries")
    for raw in raw_paths:
        _safe_relative(raw)
    if raw_paths != sorted(set(raw_paths)):
        raise ReceiptError("candidate paths must be unique and sorted")
    parsed = [_safe_relative(raw) for raw in raw_paths]
    for index, path in enumerate(parsed):
        for other in parsed[index + 1 :]:
            if path == other or path in other.parents or other in path.parents:
                raise ReceiptError("candidate paths must not overlap")
    return raw_paths


def _contained_path(workspace: Path, relative: PurePosixPath) -> Path:
    try:
        return safe_workspace_path(
            workspace,
            relative.parts,
            allow_final_symlink=True,
        )
    except (OSError, WorktreeHashError) as exc:
        raise ReceiptError(str(exc)) from exc


def _candidate_entries(root: str | Path, paths: Iterable[str]) -> list[tuple[str, str, bytes]]:
    """Read named candidate paths as canonical file/symlink entries.

    Timestamps and platform-specific metadata are intentionally excluded. A
    symlink is hashed by its target string and is never followed.
    """

    try:
        workspace = Path(root).resolve(strict=True)
    except OSError as exc:
        raise ReceiptError(f"candidate workspace is unavailable: {exc}") from exc
    entries: list[tuple[str, str, bytes]] = []
    normalized_paths = sorted(set(paths))
    _validate_candidate_paths(normalized_paths)
    for raw in normalized_paths:
        relative = _safe_relative(raw)
        target = _contained_path(workspace, relative)
        if not target.exists() and not target.is_symlink():
            raise ReceiptError(f"candidate path does not exist: {raw}")
        if target.is_symlink():
            entries.append((relative.as_posix(), "symlink", symlink_target_bytes(target)))
            continue
        if target.is_file():
            entries.append((relative.as_posix(), "file", target.read_bytes()))
            continue
        for dirpath, dirnames, filenames in os.walk(target, followlinks=False):
            kept_dirs: list[str] = []
            for dirname in sorted(d for d in dirnames if d not in {".git", "__pycache__"}):
                absolute = Path(dirpath) / dirname
                rel = PurePosixPath(absolute.relative_to(workspace).as_posix())
                absolute = _contained_path(workspace, rel)
                if absolute.is_symlink():
                    entries.append(
                        (rel.as_posix(), "symlink", symlink_target_bytes(absolute))
                    )
                else:
                    kept_dirs.append(dirname)
            dirnames[:] = kept_dirs
            for filename in sorted(filenames):
                if filename.endswith(".pyc"):
                    continue
                discovered = Path(dirpath) / filename
                rel = PurePosixPath(discovered.relative_to(workspace).as_posix())
                absolute = _contained_path(workspace, rel)
                if absolute.is_symlink():
                    entries.append(
                        (rel.as_posix(), "symlink", symlink_target_bytes(absolute))
                    )
                else:
                    entries.append((rel.as_posix(), "file", absolute.read_bytes()))
    return sorted(entries)


def _content_hash_entries(entries: Iterable[tuple[str, str, bytes]]) -> str:
    digest = hashlib.sha256()
    update_hash_frame(digest, (b"AGL-CANDIDATE-CONTENT-v2",))
    for relative, kind, data in sorted(entries):
        update_hash_frame(
            digest,
            (relative.encode("utf-8"), kind.encode("ascii"), data),
        )
    return digest.hexdigest()


def content_hash(root: str | Path, paths: Iterable[str]) -> str:
    """Hash named candidate paths by relative name, kind, and exact bytes."""

    return _content_hash_entries(_candidate_entries(root, paths))


def _entry_is_covered(path: PurePosixPath, roots: list[PurePosixPath]) -> bool:
    return any(path == root or root in path.parents for root in roots)


def build_candidate_snapshot(
    candidate_paths: Iterable[str],
    entries: Iterable[tuple[str, str, bytes]],
) -> dict[str, Any]:
    """Build a canonical bounded candidate snapshot from exact entry bytes."""

    paths = _validate_candidate_paths(list(candidate_paths))
    materialized_entries = list(entries)
    normalized_entries: list[tuple[str, str, bytes]] = []
    for index, raw in enumerate(materialized_entries):
        if not isinstance(raw, (list, tuple)) or len(raw) != 3:
            raise ReceiptError(f"candidate snapshot entry {index} must be a path/kind/bytes triple")
        path, kind, data = raw
        if not isinstance(path, str) or not isinstance(kind, str):
            raise ReceiptError(f"candidate snapshot entry {index} path and kind must be strings")
        if not isinstance(data, (bytes, bytearray)):
            raise ReceiptError(f"candidate snapshot entry {index} data must be bytes")
        normalized_entries.append((path, kind, bytes(data)))
    encoded_entries = [
        {
            "path": path,
            "kind": kind,
            "data_base64": base64.b64encode(data).decode("ascii"),
        }
        for path, kind, data in normalized_entries
    ]
    snapshot: dict[str, Any] = {
        "$schema": SNAPSHOT_SCHEMA_REF,
        "schema_version": SNAPSHOT_VERSION,
        "candidate_paths": paths,
        "entries": sorted(encoded_entries, key=lambda entry: entry["path"]),
        "entry_count": len(encoded_entries),
        "decoded_bytes": sum(len(data) for _, _, data in normalized_entries),
        "content_sha256": _content_hash_entries(normalized_entries),
    }
    validate_candidate_snapshot(snapshot, expected_paths=paths)
    _canonical_snapshot_bytes(snapshot)
    return snapshot


def create_candidate_snapshot(root: str | Path, paths: Iterable[str]) -> dict[str, Any]:
    normalized_paths = sorted(set(paths))
    entries = _candidate_entries(root, normalized_paths)
    return build_candidate_snapshot(normalized_paths, entries)


def validate_candidate_snapshot(
    snapshot: Mapping[str, Any],
    *,
    expected_paths: Iterable[str] | None = None,
) -> str:
    top = _object(
        snapshot,
        "candidate snapshot",
        {
            "$schema",
            "schema_version",
            "candidate_paths",
            "entries",
            "entry_count",
            "decoded_bytes",
            "content_sha256",
        },
    )
    if top["$schema"] != SNAPSHOT_SCHEMA_REF or top["schema_version"] != SNAPSHOT_VERSION:
        raise ReceiptError("unsupported candidate snapshot schema")
    if not isinstance(top["candidate_paths"], list):
        raise ReceiptError("candidate snapshot paths must be a list")
    paths = _validate_candidate_paths(top["candidate_paths"])
    if expected_paths is not None:
        expected = _validate_candidate_paths(list(expected_paths))
        if paths != expected:
            raise ReceiptError("candidate snapshot paths do not match receipt candidate.paths")
    roots = [_safe_relative(path) for path in paths]

    raw_entries = top["entries"]
    if not isinstance(raw_entries, list):
        raise ReceiptError("candidate snapshot entries must be a list")
    if len(raw_entries) > MAX_SNAPSHOT_ENTRIES:
        raise ReceiptError(
            f"candidate snapshot exceeds {MAX_SNAPSHOT_ENTRIES} entries"
        )
    decoded_entries: list[tuple[str, str, bytes]] = []
    seen: set[str] = set()
    for index, raw in enumerate(raw_entries):
        entry = _object(
            raw,
            f"candidate snapshot entries[{index}]",
            {"path", "kind", "data_base64"},
        )
        path_text = _string(
            entry["path"],
            f"candidate snapshot entries[{index}].path",
        )
        path = _safe_relative(path_text)
        if path_text in seen:
            raise ReceiptError(f"candidate snapshot contains duplicate path: {path_text}")
        seen.add(path_text)
        if not _entry_is_covered(path, roots):
            raise ReceiptError(f"candidate snapshot path is outside candidate.paths: {path_text}")
        kind = _string(entry["kind"], f"candidate snapshot entries[{index}].kind")
        if kind not in {"file", "symlink"}:
            raise ReceiptError(f"unsupported candidate snapshot kind: {kind}")
        encoded = _string(
            entry["data_base64"],
            f"candidate snapshot entries[{index}].data_base64",
            nonempty=False,
        )
        try:
            data = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise ReceiptError("candidate snapshot contains invalid base64") from exc
        if base64.b64encode(data).decode("ascii") != encoded:
            raise ReceiptError("candidate snapshot base64 must use canonical encoding")
        decoded_entries.append((path_text, kind, data))

    if [path for path, _, _ in decoded_entries] != sorted(seen):
        raise ReceiptError("candidate snapshot entries must be sorted by path")
    uncovered = [
        root.as_posix()
        for root in roots
        if not any(_entry_is_covered(_safe_relative(path), [root]) for path in seen)
    ]
    if uncovered:
        raise ReceiptError(
            "candidate snapshot does not cover candidate paths: " + ", ".join(uncovered)
        )
    decoded_bytes = sum(len(data) for _, _, data in decoded_entries)
    if decoded_bytes > MAX_SNAPSHOT_DECODED_BYTES:
        raise ReceiptError(
            f"candidate snapshot exceeds {MAX_SNAPSHOT_DECODED_BYTES} decoded bytes"
        )
    if (
        not isinstance(top["entry_count"], int)
        or isinstance(top["entry_count"], bool)
        or top["entry_count"] != len(decoded_entries)
    ):
        raise ReceiptError("candidate snapshot entry_count does not match entries")
    if (
        not isinstance(top["decoded_bytes"], int)
        or isinstance(top["decoded_bytes"], bool)
        or top["decoded_bytes"] != decoded_bytes
    ):
        raise ReceiptError("candidate snapshot decoded_bytes does not match entries")
    computed = _content_hash_entries(decoded_entries)
    claimed = _hash(top["content_sha256"], "candidate snapshot content_sha256")
    if claimed != computed:
        raise ReceiptError(
            f"candidate snapshot content hash mismatch: expected {claimed}, computed {computed}"
        )
    return computed


def _canonical_snapshot_bytes(snapshot: Mapping[str, Any]) -> bytes:
    payload = canonical_json(snapshot) + b"\n"
    if len(payload) > MAX_SNAPSHOT_JSON_BYTES:
        raise ReceiptError(
            f"candidate snapshot exceeds {MAX_SNAPSHOT_JSON_BYTES} canonical JSON bytes"
        )
    return payload


def write_candidate_snapshot(snapshot: Mapping[str, Any], path: str | Path) -> Path:
    validate_candidate_snapshot(snapshot)
    payload = _canonical_snapshot_bytes(snapshot)
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    return destination


def read_candidate_snapshot(
    path: str | Path,
    *,
    expected_paths: Iterable[str] | None = None,
) -> tuple[dict[str, Any], str]:
    source = Path(path)
    try:
        if source.stat().st_size > MAX_SNAPSHOT_JSON_BYTES:
            raise ReceiptError(
                f"candidate snapshot exceeds {MAX_SNAPSHOT_JSON_BYTES} JSON bytes"
            )
        raw = source.read_bytes()
        snapshot = json.loads(raw.decode("utf-8"))
    except ReceiptError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ReceiptError(f"could not read candidate snapshot: {exc}") from exc
    if raw != canonical_json(snapshot) + b"\n":
        raise ReceiptError("candidate snapshot JSON is not canonically encoded")
    computed = validate_candidate_snapshot(snapshot, expected_paths=expected_paths)
    return snapshot, computed


def tree_hash(root: str | Path) -> str:
    """Use the same worktree codec as the live release verifier."""

    try:
        return shared_tree_hash(root)
    except (OSError, WorktreeHashError) as exc:
        raise ReceiptError(str(exc)) from exc


def build_receipt(
    *,
    scenario: Mapping[str, Any],
    policy: Mapping[str, Any],
    engine: Mapping[str, Any],
    candidate: Mapping[str, Any],
    tests: Mapping[str, Any],
    checks: Mapping[str, Any],
    verdict: Mapping[str, Any],
    environment: Mapping[str, Any],
    outputs: Mapping[str, Any],
) -> dict[str, Any]:
    receipt: dict[str, Any] = {
        "$schema": SCHEMA_REF,
        "schema_version": RECEIPT_VERSION,
        "scenario": dict(scenario),
        "policy": dict(policy),
        "engine": dict(engine),
        "candidate": dict(candidate),
        "tests": dict(tests),
        "checks": {key: dict(value) for key, value in sorted(checks.items())},
        "verdict": dict(verdict),
        "environment": dict(environment),
        "outputs": dict(outputs),
    }
    receipt["receipt_sha256"] = receipt_hash(receipt)
    validate_receipt(receipt)
    return receipt


def write_receipt(receipt: Mapping[str, Any], path: str | Path) -> Path:
    validate_receipt(receipt)
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return destination


def _object(
    value: Any,
    name: str,
    required: set[str],
    optional: set[str] | None = None,
) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ReceiptError(f"{name} must be an object")
    optional = optional or set()
    missing = required - set(value)
    extra = set(value) - required - optional
    if missing:
        raise ReceiptError(f"{name} missing fields: {', '.join(sorted(missing))}")
    if extra:
        raise ReceiptError(f"{name} has unknown fields: {', '.join(sorted(extra))}")
    return value


def _string(value: Any, name: str, *, nonempty: bool = True) -> str:
    if not isinstance(value, str) or (nonempty and not value.strip()):
        raise ReceiptError(f"{name} must be a non-empty string")
    return value


def _hash(value: Any, name: str) -> str:
    text = _string(value, name)
    if not HEX64.fullmatch(text):
        raise ReceiptError(f"{name} must be a lowercase SHA-256 digest")
    return text


def validate_receipt(receipt: Mapping[str, Any]) -> Mapping[str, Any]:
    top = _object(
        receipt,
        "receipt",
        {
            "$schema",
            "schema_version",
            "scenario",
            "policy",
            "engine",
            "candidate",
            "tests",
            "checks",
            "verdict",
            "environment",
            "outputs",
            "receipt_sha256",
        },
    )
    if top["$schema"] != SCHEMA_REF or top["schema_version"] != RECEIPT_VERSION:
        raise ReceiptError("unsupported receipt schema")

    scenario = _object(top["scenario"], "scenario", {"id", "version", "title"})
    for key in ("id", "version", "title"):
        _string(scenario[key], f"scenario.{key}")

    policy = _object(top["policy"], "policy", {"id", "release_authority"})
    if policy["id"] not in POLICIES:
        raise ReceiptError(f"policy.id must be one of {sorted(POLICIES)}")
    if not isinstance(policy["release_authority"], bool):
        raise ReceiptError("policy.release_authority must be boolean")

    engine = _object(
        top["engine"],
        "engine",
        {"name", "version", "fingerprint", "commit", "source_dirty"},
    )
    if engine["name"] != PRODUCT_NAME:
        raise ReceiptError("receipt engine identity is not Agent Governance Lab")
    if not SEMVER.fullmatch(_string(engine["version"], "engine.version")):
        raise ReceiptError("engine.version must be semantic version x.y.z")
    _hash(engine["fingerprint"], "engine.fingerprint")
    if not COMMIT.fullmatch(_string(engine["commit"], "engine.commit")):
        raise ReceiptError("engine.commit must be a Git commit or NO-GIT")
    if not isinstance(engine["source_dirty"], bool):
        raise ReceiptError("engine.source_dirty must be boolean")

    candidate = _object(
        top["candidate"],
        "candidate",
        {
            "paths",
            "initial_tree_hash",
            "initial_content_hash",
            "final_tree_hash",
            "final_content_hash",
        },
    )
    if not isinstance(candidate["paths"], list):
        raise ReceiptError("candidate.paths must be a list")
    _validate_candidate_paths(candidate["paths"])
    for key in (
        "initial_tree_hash",
        "initial_content_hash",
        "final_tree_hash",
        "final_content_hash",
    ):
        _hash(candidate[key], f"candidate.{key}")

    tests = _object(
        top["tests"],
        "tests",
        {"command", "exit_code", "collected", "output_sha256"},
    )
    _string(tests["command"], "tests.command")
    if not isinstance(tests["exit_code"], int) or isinstance(tests["exit_code"], bool):
        raise ReceiptError("tests.exit_code must be an integer")
    if (
        not isinstance(tests["collected"], int)
        or isinstance(tests["collected"], bool)
        or tests["collected"] < 0
    ):
        raise ReceiptError("tests.collected must be a non-negative integer")
    _hash(tests["output_sha256"], "tests.output_sha256")

    checks = top["checks"]
    if not isinstance(checks, dict) or not checks:
        raise ReceiptError("checks must be a non-empty object")
    failed: list[str] = []
    for check_id, raw in checks.items():
        if not CHECK_ID.fullmatch(check_id):
            raise ReceiptError(f"invalid check id: {check_id!r}")
        check = _object(raw, f"checks.{check_id}", {"passed", "detail"})
        if not isinstance(check["passed"], bool):
            raise ReceiptError(f"checks.{check_id}.passed must be boolean")
        _string(check["detail"], f"checks.{check_id}.detail", nonempty=False)
        if not check["passed"]:
            failed.append(check_id)

    verdict = _object(top["verdict"], "verdict", {"status", "released", "reason"})
    if verdict["status"] not in VERDICTS:
        raise ReceiptError(f"verdict.status must be one of {sorted(VERDICTS)}")
    if not isinstance(verdict["released"], bool):
        raise ReceiptError("verdict.released must be boolean")
    reason = _string(verdict["reason"], "verdict.reason")
    if verdict["status"] == "BLOCKED":
        if verdict["released"] or not failed or reason not in failed:
            raise ReceiptError("a blocked verdict must name a failed check and refuse release")
    elif not verdict["released"]:
        raise ReceiptError("a released verdict must set released=true")
    elif policy["id"] == "enforced" and failed:
        raise ReceiptError("the enforced policy cannot release failed checks")

    environment = _object(
        top["environment"],
        "environment",
        {"os", "architecture", "python", "shell"},
    )
    for key in ("os", "architecture", "python", "shell"):
        _string(environment[key], f"environment.{key}")

    outputs = _object(
        top["outputs"],
        "outputs",
        {
            "initial_candidate_snapshot",
            "final_candidate_snapshot",
            "verifier_verdict",
            "verifier_output",
            "test_output",
        },
    )
    for key, value in outputs.items():
        artifact = _object(value, f"outputs.{key}", {"path", "sha256"})
        _safe_relative(_string(artifact["path"], f"outputs.{key}.path"))
        _hash(artifact["sha256"], f"outputs.{key}.sha256")
    if outputs["test_output"]["sha256"] != tests["output_sha256"]:
        raise ReceiptError("tests.output_sha256 must match outputs.test_output.sha256")

    stored = _hash(top["receipt_sha256"], "receipt.receipt_sha256")
    actual = receipt_hash(top)
    if stored != actual:
        raise ReceiptError(f"receipt digest mismatch: expected {stored}, computed {actual}")
    return top


def read_receipt(path: str | Path) -> dict[str, Any]:
    try:
        receipt = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ReceiptError(f"could not read receipt: {exc}") from exc
    validate_receipt(receipt)
    return receipt


def verify_receipt(path: str | Path, workspace: str | Path | None = None) -> dict[str, Any]:
    receipt_path = Path(path).resolve()
    receipt = read_receipt(receipt_path)
    resolved_outputs: dict[str, Path] = {}
    for name, artifact in receipt["outputs"].items():
        relative = _safe_relative(artifact["path"])
        artifact_path = receipt_path.parent.joinpath(*relative.parts).resolve()
        try:
            artifact_path.relative_to(receipt_path.parent)
        except ValueError as exc:
            raise ReceiptError(f"output artifact escapes receipt directory: {name}") from exc
        if not artifact_path.is_file():
            raise ReceiptError(f"output artifact is missing: {artifact['path']}")
        if (
            name in {"initial_candidate_snapshot", "final_candidate_snapshot"}
            and artifact_path.stat().st_size > MAX_SNAPSHOT_JSON_BYTES
        ):
            raise ReceiptError(
                f"candidate snapshot exceeds {MAX_SNAPSHOT_JSON_BYTES} JSON bytes"
            )
        actual = sha256_file(artifact_path)
        if actual != artifact["sha256"]:
            raise ReceiptError(
                f"output artifact digest mismatch for {name}: "
                f"expected {artifact['sha256']}, computed {actual}"
            )
        resolved_outputs[name] = artifact_path

    candidate = receipt["candidate"]
    _, initial_content = read_candidate_snapshot(
        resolved_outputs["initial_candidate_snapshot"],
        expected_paths=candidate["paths"],
    )
    if initial_content != candidate["initial_content_hash"]:
        raise ReceiptError(
            "initial candidate snapshot does not match candidate.initial_content_hash"
        )
    _, final_content = read_candidate_snapshot(
        resolved_outputs["final_candidate_snapshot"],
        expected_paths=candidate["paths"],
    )
    if final_content != candidate["final_content_hash"]:
        raise ReceiptError(
            "final candidate snapshot does not match candidate.final_content_hash"
        )

    try:
        bound_verdict = json.loads(
            resolved_outputs["verifier_verdict"].read_text(encoding="utf-8")
        )
        bound_checks = {
            name: {"passed": bool(value["pass"]), "detail": str(value.get("detail", ""))}
            for name, value in bound_verdict["checks"].items()
        }
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        raise ReceiptError(f"bound verifier verdict is malformed: {exc}") from exc
    if bound_checks != receipt["checks"]:
        raise ReceiptError("receipt checks do not match the bound verifier verdict")
    if bound_verdict.get("tree_hash") != receipt["candidate"]["final_tree_hash"]:
        raise ReceiptError("candidate final tree hash does not match the bound verifier verdict")
    if bound_verdict.get("governor_fingerprint") != receipt["engine"]["fingerprint"]:
        raise ReceiptError("engine fingerprint does not match the bound verifier verdict")
    bound_status = bound_verdict.get("status")
    if bound_status not in {"PASS", "FAIL"}:
        raise ReceiptError("bound verifier verdict status must be PASS or FAIL")
    if receipt["policy"]["id"] == "enforced":
        expected = "RELEASED" if bound_status == "PASS" else "BLOCKED"
        if receipt["verdict"]["status"] != expected:
            raise ReceiptError("enforced release decision does not match the bound verifier verdict")
    if workspace is not None:
        actual_content = content_hash(workspace, candidate["paths"])
        if actual_content != candidate["final_content_hash"]:
            raise ReceiptError(
                "workspace content hash mismatch: "
                f"expected {candidate['final_content_hash']}, computed {actual_content}"
            )
        actual_tree = tree_hash(workspace)
        if actual_tree != candidate["final_tree_hash"]:
            raise ReceiptError(
                "workspace tree hash mismatch: "
                f"expected {candidate['final_tree_hash']}, computed {actual_tree}"
            )
    return receipt
