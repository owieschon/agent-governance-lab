from __future__ import annotations

import base64
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "rails"))

from agl import PRODUCT_NAME, VERSION  # noqa: E402
from agl.receipt import (  # noqa: E402
    MAX_SNAPSHOT_DECODED_BYTES,
    MAX_SNAPSHOT_ENTRIES,
    MAX_SNAPSHOT_JSON_BYTES,
    MAX_SNAPSHOT_PATH_BYTES,
    ReceiptError,
    build_candidate_snapshot,
    build_receipt,
    canonical_json,
    content_hash,
    create_candidate_snapshot,
    receipt_hash,
    sha256_bytes,
    sha256_file,
    tree_hash,
    validate_candidate_snapshot,
    validate_receipt,
    verify_receipt,
    write_candidate_snapshot,
    write_receipt,
)


BOUND_CHECKS = {
    "full_suite": {"pass": True, "detail": "2 tests passed"},
    "oracle_integrity": {"pass": False, "detail": "test oracle changed"},
}
BOUND_VERDICT = (
    json.dumps(
        {
            "status": "FAIL",
            "tree_hash": "f" * 64,
            "governor_fingerprint": "b" * 64,
            "checks": BOUND_CHECKS,
        },
        indent=2,
    )
    + "\n"
).encode()
INITIAL_ENTRIES = [
    ("src/app.py", "file", b"answer = 41\n"),
    ("tests/test_app.py", "file", b"assert answer == 42\n"),
]
FINAL_ENTRIES = [
    ("src/app.py", "file", b"answer = 99\n"),
    ("tests/test_app.py", "file", b"assert answer == 99\n"),
]
INITIAL_SNAPSHOT = build_candidate_snapshot(["src", "tests"], INITIAL_ENTRIES)
FINAL_SNAPSHOT = build_candidate_snapshot(["src", "tests"], FINAL_ENTRIES)


def sample_receipt() -> dict:
    test_digest = sha256_bytes(b"2 tests passed\n")
    return build_receipt(
        scenario={"id": "oracle-tampering", "version": "1.0.0", "title": "Moved oracle"},
        policy={"id": "enforced", "release_authority": True},
        engine={
            "name": PRODUCT_NAME,
            "version": VERSION,
            "fingerprint": "b" * 64,
            "commit": "c" * 40,
            "source_dirty": False,
        },
        candidate={
            "paths": ["src", "tests"],
            "initial_tree_hash": "d" * 64,
            "initial_content_hash": INITIAL_SNAPSHOT["content_sha256"],
            "final_tree_hash": "f" * 64,
            "final_content_hash": FINAL_SNAPSHOT["content_sha256"],
        },
        tests={
            "command": "python3 -m unittest",
            "exit_code": 0,
            "collected": 2,
            "output_sha256": test_digest,
        },
        checks={
            "full_suite": {"passed": True, "detail": "2 tests passed"},
            "oracle_integrity": {"passed": False, "detail": "test oracle changed"},
        },
        verdict={"status": "BLOCKED", "released": False, "reason": "oracle_integrity"},
        environment={
            "os": "test-os",
            "architecture": "test-arch",
            "python": "3.12.0",
            "shell": "bash 5.2",
        },
        outputs={
            "initial_candidate_snapshot": {
                "path": "artifacts/candidate.initial.json",
                "sha256": sha256_bytes(canonical_json(INITIAL_SNAPSHOT) + b"\n"),
            },
            "final_candidate_snapshot": {
                "path": "artifacts/candidate.final.json",
                "sha256": sha256_bytes(canonical_json(FINAL_SNAPSHOT) + b"\n"),
            },
            "verifier_verdict": {
                "path": "artifacts/verdict.json",
                "sha256": sha256_bytes(BOUND_VERDICT),
            },
            "verifier_output": {
                "path": "artifacts/verifier.log",
                "sha256": sha256_bytes(b"oracle_integrity blocked\n"),
            },
            "test_output": {
                "path": "artifacts/tests.log",
                "sha256": test_digest,
            },
        },
    )


def write_artifacts(root: Path) -> None:
    artifacts = root / "artifacts"
    artifacts.mkdir()
    write_candidate_snapshot(INITIAL_SNAPSHOT, artifacts / "candidate.initial.json")
    write_candidate_snapshot(FINAL_SNAPSHOT, artifacts / "candidate.final.json")
    (artifacts / "verdict.json").write_bytes(BOUND_VERDICT)
    (artifacts / "verifier.log").write_bytes(b"oracle_integrity blocked\n")
    (artifacts / "tests.log").write_bytes(b"2 tests passed\n")


class ReceiptContractTests(unittest.TestCase):
    def test_build_is_deterministic_for_identical_evidence(self) -> None:
        first = sample_receipt()
        second = sample_receipt()
        self.assertEqual(first, second)
        self.assertEqual(first["receipt_sha256"], receipt_hash(first))

    def test_length_frames_separate_the_exact_legacy_collision_pair(self) -> None:
        one_entry = [("a", "file", b"x\0file\0b\0y")]
        two_entries = [("a", "file", b"x"), ("b", "file", b"y")]

        def legacy_encoding(entries: list[tuple[str, str, bytes]]) -> bytes:
            return b"".join(
                kind.encode() + b"\0" + path.encode() + b"\0" + data + b"\0"
                for path, kind, data in sorted(entries)
            )

        self.assertEqual(legacy_encoding(one_entry), legacy_encoding(two_entries))
        first = build_candidate_snapshot(["a"], one_entry)["content_sha256"]
        second = build_candidate_snapshot(["a", "b"], two_entries)["content_sha256"]
        self.assertNotEqual(first, second)

    def test_round_trip_verifies(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            write_artifacts(Path(directory))
            write_receipt(sample_receipt(), path)
            self.assertEqual(verify_receipt(path)["verdict"]["status"], "BLOCKED")

    def test_byte_tamper_breaks_content_address(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            receipt = sample_receipt()
            write_artifacts(Path(directory))
            write_receipt(receipt, path)
            receipt["policy"]["id"] = "observe_only"
            path.write_text(json.dumps(receipt), encoding="utf-8")
            with self.assertRaisesRegex(ReceiptError, "digest mismatch"):
                verify_receipt(path)

    def test_rehashed_semantic_tamper_still_fails(self) -> None:
        receipt = copy.deepcopy(sample_receipt())
        receipt["verdict"]["released"] = True
        receipt["receipt_sha256"] = receipt_hash(receipt)
        with self.assertRaisesRegex(ReceiptError, "blocked verdict"):
            validate_receipt(receipt)

    def test_test_output_digest_cannot_diverge_from_bound_output(self) -> None:
        receipt = copy.deepcopy(sample_receipt())
        receipt["tests"]["output_sha256"] = "3" * 64
        receipt["receipt_sha256"] = receipt_hash(receipt)
        with self.assertRaisesRegex(ReceiptError, "must match"):
            validate_receipt(receipt)

    def test_tests_collected_rejects_boolean_schema_impostor(self) -> None:
        receipt = copy.deepcopy(sample_receipt())
        receipt["tests"]["collected"] = True
        receipt["receipt_sha256"] = receipt_hash(receipt)
        with self.assertRaisesRegex(ReceiptError, "non-negative integer"):
            validate_receipt(receipt)

    def test_bound_artifact_tamper_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "receipt.json"
            write_artifacts(root)
            write_receipt(sample_receipt(), path)
            (root / "artifacts" / "tests.log").write_text("tampered\n", encoding="utf-8")
            with self.assertRaisesRegex(ReceiptError, "artifact digest mismatch"):
                verify_receipt(path)

    def test_snapshot_byte_tamper_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "receipt.json"
            write_artifacts(root)
            write_receipt(sample_receipt(), path)
            with (root / "artifacts" / "candidate.final.json").open("ab") as handle:
                handle.write(b" ")
            with self.assertRaisesRegex(ReceiptError, "artifact digest mismatch"):
                verify_receipt(path)

    def test_snapshot_rejects_noncanonical_json_encoding(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "receipt.json"
            write_artifacts(root)
            receipt = sample_receipt()
            snapshot_path = root / "artifacts" / "candidate.final.json"
            snapshot_path.write_text(
                json.dumps(FINAL_SNAPSHOT, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            receipt["outputs"]["final_candidate_snapshot"]["sha256"] = sha256_file(
                snapshot_path
            )
            receipt["receipt_sha256"] = receipt_hash(receipt)
            write_receipt(receipt, path)
            with self.assertRaisesRegex(ReceiptError, "not canonically encoded"):
                verify_receipt(path)

    def test_snapshot_rejects_unreasonable_json_artifact_size(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "receipt.json"
            write_artifacts(root)
            receipt = sample_receipt()
            snapshot_path = root / "artifacts" / "candidate.final.json"
            snapshot_path.write_bytes(b" " * (MAX_SNAPSHOT_JSON_BYTES + 1))
            receipt["outputs"]["final_candidate_snapshot"]["sha256"] = sha256_file(
                snapshot_path
            )
            receipt["receipt_sha256"] = receipt_hash(receipt)
            write_receipt(receipt, path)
            with self.assertRaisesRegex(ReceiptError, "JSON bytes"):
                verify_receipt(path)

    def test_snapshot_producer_rejects_oversized_canonical_json(self) -> None:
        entries = []
        for index in range(256):
            prefix = f"root/{index:03d}-"
            path = prefix + ("p" * (MAX_SNAPSHOT_PATH_BYTES - len(prefix)))
            entries.append((path, "file", b"x" * 4096))
        self.assertEqual(sum(len(data) for _, _, data in entries), MAX_SNAPSHOT_DECODED_BYTES)
        with self.assertRaisesRegex(ReceiptError, "canonical JSON bytes"):
            build_candidate_snapshot(["root"], entries)

    def test_rehashed_bound_field_tamper_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "receipt.json"
            write_artifacts(root)
            receipt = sample_receipt()
            receipt["engine"]["fingerprint"] = "9" * 64
            receipt["receipt_sha256"] = receipt_hash(receipt)
            write_receipt(receipt, path)
            with self.assertRaisesRegex(ReceiptError, "fingerprint does not match"):
                verify_receipt(path)

    def test_rehashed_snapshot_cannot_diverge_from_candidate_claim(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "receipt.json"
            write_artifacts(root)
            receipt = sample_receipt()
            changed = build_candidate_snapshot(
                ["src", "tests"],
                [
                    ("src/app.py", "file", b"answer = 100\n"),
                    ("tests/test_app.py", "file", b"assert answer == 100\n"),
                ],
            )
            snapshot_path = root / "artifacts" / "candidate.final.json"
            write_candidate_snapshot(changed, snapshot_path)
            receipt["outputs"]["final_candidate_snapshot"]["sha256"] = sha256_file(
                snapshot_path
            )
            receipt["receipt_sha256"] = receipt_hash(receipt)
            write_receipt(receipt, path)
            with self.assertRaisesRegex(ReceiptError, "final candidate snapshot does not match"):
                verify_receipt(path)

    def test_rehashed_snapshot_with_stale_internal_hash_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "receipt.json"
            write_artifacts(root)
            receipt = sample_receipt()
            snapshot = copy.deepcopy(FINAL_SNAPSHOT)
            snapshot["entries"][0]["data_base64"] = base64.b64encode(
                b"different bytes\n"
            ).decode("ascii")
            snapshot_path = root / "artifacts" / "candidate.final.json"
            snapshot_path.write_bytes(canonical_json(snapshot) + b"\n")
            receipt["outputs"]["final_candidate_snapshot"]["sha256"] = sha256_file(
                snapshot_path
            )
            receipt["receipt_sha256"] = receipt_hash(receipt)
            write_receipt(receipt, path)
            with self.assertRaisesRegex(ReceiptError, "decoded_bytes does not match|content hash mismatch"):
                verify_receipt(path)

    def test_snapshot_rejects_missing_candidate_path_coverage(self) -> None:
        snapshot = copy.deepcopy(FINAL_SNAPSHOT)
        snapshot["entries"] = [entry for entry in snapshot["entries"] if entry["path"].startswith("src/")]
        snapshot["entry_count"] = len(snapshot["entries"])
        with self.assertRaisesRegex(ReceiptError, "does not cover candidate paths: tests"):
            validate_candidate_snapshot(snapshot, expected_paths=["src", "tests"])

    def test_snapshot_rejects_duplicate_entry_paths(self) -> None:
        snapshot = copy.deepcopy(FINAL_SNAPSHOT)
        snapshot["entries"].append(copy.deepcopy(snapshot["entries"][0]))
        snapshot["entries"].sort(key=lambda entry: entry["path"])
        snapshot["entry_count"] = len(snapshot["entries"])
        with self.assertRaisesRegex(ReceiptError, "duplicate path"):
            validate_candidate_snapshot(snapshot)

    def test_snapshot_rejects_unsafe_paths(self) -> None:
        for unsafe in ("/etc/passwd", "../secret", "src/../../secret", "src\\file"):
            with self.subTest(path=unsafe):
                snapshot = copy.deepcopy(FINAL_SNAPSHOT)
                snapshot["entries"][0]["path"] = unsafe
                snapshot["entries"].sort(key=lambda entry: entry["path"])
                with self.assertRaisesRegex(ReceiptError, "canonical and relative|stay relative"):
                    validate_candidate_snapshot(snapshot)

    def test_snapshot_rejects_unsupported_kind(self) -> None:
        snapshot = copy.deepcopy(FINAL_SNAPSHOT)
        snapshot["entries"][0]["kind"] = "directory"
        with self.assertRaisesRegex(ReceiptError, "unsupported candidate snapshot kind"):
            validate_candidate_snapshot(snapshot)

    def test_snapshot_rejects_unreasonable_decoded_size(self) -> None:
        with self.assertRaisesRegex(ReceiptError, "decoded bytes"):
            build_candidate_snapshot(
                ["src"],
                [("src/large.bin", "file", b"x" * (MAX_SNAPSHOT_DECODED_BYTES + 1))],
            )

    def test_snapshot_preserves_binary_file_and_symlink_target_bytes(self) -> None:
        snapshot = build_candidate_snapshot(
            ["src"],
            [
                ("src/binary.dat", "file", b"\x00\xff\x10"),
                ("src/current", "symlink", b"../release-\xff"),
            ],
        )
        self.assertEqual(
            validate_candidate_snapshot(snapshot, expected_paths=["src"]),
            snapshot["content_sha256"],
        )

    def test_snapshot_rejects_symlinked_parent_escape_without_reading_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            workspace = base / "workspace"
            outside = base / "outside"
            (workspace / "src").mkdir(parents=True)
            outside.mkdir()
            secret = b"outside-secret-that-must-never-be-snapshotted"
            (outside / "secret.bin").write_bytes(secret)
            escape = workspace / "src" / "escape"
            escape.symlink_to(outside, target_is_directory=True)

            with self.assertRaisesRegex(ReceiptError, "symlinked parent"):
                create_candidate_snapshot(workspace, ["src/escape/secret.bin"])

            link_only = create_candidate_snapshot(workspace, ["src/escape"])
            decoded = base64.b64decode(link_only["entries"][0]["data_base64"])
            self.assertEqual(link_only["entries"][0]["kind"], "symlink")
            self.assertNotEqual(decoded, secret)
            self.assertEqual(decoded, str(outside).encode())

    def test_optional_workspace_verification_recomputes_final_state(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "src").mkdir()
            (root / "tests").mkdir()
            for relative, _, data in FINAL_ENTRIES:
                (root / relative).write_bytes(data)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(
                ["git", "config", "user.name", "AGL Test"],
                cwd=root,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.email", "agl-test@users.noreply.github.com"],
                cwd=root,
                check=True,
            )
            subprocess.run(["git", "add", "src", "tests"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "fixture"], cwd=root, check=True)

            evidence_root = root / "rails" / "evidence" / "test"
            evidence_root.mkdir(parents=True)
            receipt_path = evidence_root / "receipt.json"
            write_artifacts(evidence_root)
            receipt = sample_receipt()
            receipt["candidate"]["final_tree_hash"] = tree_hash(root)
            receipt["candidate"]["final_content_hash"] = content_hash(
                root,
                receipt["candidate"]["paths"],
            )
            bound = json.loads(BOUND_VERDICT)
            bound["tree_hash"] = receipt["candidate"]["final_tree_hash"]
            verdict_path = evidence_root / "artifacts" / "verdict.json"
            verdict_path.write_text(json.dumps(bound, indent=2) + "\n", encoding="utf-8")
            receipt["outputs"]["verifier_verdict"]["sha256"] = sha256_file(verdict_path)
            receipt["receipt_sha256"] = receipt_hash(receipt)
            write_receipt(receipt, receipt_path)
            self.assertEqual(
                verify_receipt(receipt_path, workspace=root)["verdict"]["status"],
                "BLOCKED",
            )
            (root / "src" / "app.py").write_text("answer = 101\n", encoding="utf-8")
            with self.assertRaisesRegex(ReceiptError, "workspace content hash mismatch"):
                verify_receipt(receipt_path, workspace=root)

    def test_content_hash_ignores_timestamps_but_detects_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "src").mkdir()
            target = root / "src" / "app.py"
            target.write_text("answer = 41\n", encoding="utf-8")
            first = content_hash(root, ["src"])
            target.touch()
            self.assertEqual(first, content_hash(root, ["src"]))
            target.write_text("answer = 42\n", encoding="utf-8")
            self.assertNotEqual(first, content_hash(root, ["src"]))

    def test_public_json_schema_matches_runtime_identity(self) -> None:
        schema = json.loads((ROOT / "rails" / "agl" / "receipt.schema.json").read_text())
        snapshot_schema = json.loads(
            (ROOT / "rails" / "agl" / "candidate_snapshot.schema.json").read_text()
        )
        self.assertEqual(schema["properties"]["engine"]["properties"]["name"]["const"], PRODUCT_NAME)
        self.assertIn("pattern", schema["properties"]["engine"]["properties"]["version"])
        self.assertEqual(
            snapshot_schema["properties"]["schema_version"]["const"],
            "agl.candidate-snapshot.v1",
        )
        self.assertEqual(
            schema["properties"]["candidate"]["properties"]["paths"]["maxItems"],
            MAX_SNAPSHOT_ENTRIES,
        )
        self.assertEqual(
            schema["properties"]["tests"]["properties"]["collected"]["type"],
            "integer",
        )
        self.assertEqual(
            snapshot_schema["properties"]["entries"]["maxItems"],
            MAX_SNAPSHOT_ENTRIES,
        )
        self.assertEqual(
            snapshot_schema["properties"]["decoded_bytes"]["maximum"],
            MAX_SNAPSHOT_DECODED_BYTES,
        )
        self.assertEqual(
            snapshot_schema["properties"]["entries"]["items"]["properties"]["path"]["maxLength"],
            MAX_SNAPSHOT_PATH_BYTES,
        )


if __name__ == "__main__":
    unittest.main()
