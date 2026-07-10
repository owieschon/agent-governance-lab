from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "rails"))

from agl.receipt import tree_hash as receipt_tree_hash  # noqa: E402


class WorktreeHashTests(unittest.TestCase):
    def make_repo(self, root: Path) -> None:
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "AGL Test"], cwd=root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "agl-test@users.noreply.github.com"],
            cwd=root,
            check=True,
        )
        (root / "tracked.txt").write_text("tracked\n", encoding="utf-8")
        subprocess.run(["git", "add", "tracked.txt"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=root, check=True)

    def live_tree_hash(self, root: Path) -> str:
        completed = subprocess.run(
            [sys.executable, str(ROOT / "rails" / "verifier" / "treehash.py")],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return completed.stdout.strip()

    def assert_shared_hash(self, root: Path) -> str:
        receipt_hash = receipt_tree_hash(root)
        self.assertEqual(receipt_hash, self.live_tree_hash(root))
        return receipt_hash

    def test_regular_untracked_file_uses_identical_live_and_receipt_hashing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_repo(root)
            untracked = root / "untracked.bin"
            untracked.write_bytes(b"first\x00payload")
            first = self.assert_shared_hash(root)
            nested = root / "nested"
            nested.mkdir()
            self.assertEqual(first, receipt_tree_hash(nested))
            self.assertEqual(first, self.live_tree_hash(nested))
            untracked.write_bytes(b"second\x00payload")
            second = self.assert_shared_hash(root)
            self.assertNotEqual(first, second)

    def test_untracked_symlink_hashes_link_text_and_never_external_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / "repo"
            root.mkdir()
            self.make_repo(root)
            target_a = base / "outside-a.bin"
            target_b = base / "outside-b.bin"
            target_a.write_bytes(b"external-secret-a")
            target_b.write_bytes(b"external-secret-b")
            link = root / "untracked-link"
            link.symlink_to(target_a)

            first = self.assert_shared_hash(root)
            target_a.write_bytes(b"changed-external-bytes")
            self.assertEqual(first, self.assert_shared_hash(root))

            link.unlink()
            link.symlink_to(target_b)
            second = self.assert_shared_hash(root)
            self.assertNotEqual(first, second)


if __name__ == "__main__":
    unittest.main()
