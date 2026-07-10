from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "bin" / "agl"


class CliTests(unittest.TestCase):
    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(CLI), *args],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
            timeout=120,
        )

    def test_identity_is_canonical_and_machine_readable(self) -> None:
        result = self.run_cli("identity", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        identity = json.loads(result.stdout)
        self.assertEqual(identity["name"], "Agent Governance Lab")
        self.assertEqual(identity["cli"], "agl")
        self.assertEqual(identity["receipt_schema"], "agl.receipt.v1")

    def test_real_demo_proves_green_then_blocked_and_emits_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "demo.json"
            result = self.run_cli("demo", "--receipt", str(receipt))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("ordinary test suite: PASS", result.stdout)
            self.assertIn("VERDICT: BLOCKED", result.stdout)
            self.assertIn("VERDICT: PASS", result.stdout)
            self.assertTrue(receipt.is_file())

            verified = self.run_cli("verify-receipt", str(receipt))
            self.assertEqual(verified.returncode, 0, verified.stderr)
            self.assertIn("PASS: receipt is internally consistent", verified.stdout)

            payload = json.loads(receipt.read_text(encoding="utf-8"))
            self.assertEqual(payload["scenario"]["id"], "oracle-tampering")
            self.assertEqual(payload["policy"]["id"], "enforced")
            self.assertEqual(payload["verdict"]["reason"], "oracle_integrity")
            self.assertTrue(payload["checks"]["full_suite"]["passed"])
            self.assertFalse(payload["checks"]["oracle_integrity"]["passed"])


if __name__ == "__main__":
    unittest.main()
