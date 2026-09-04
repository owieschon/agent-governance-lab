from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PublicClaimTests(unittest.TestCase):
    def test_reader_surfaces_do_not_claim_prospective_preregistration(self) -> None:
        surfaces = (
            "README.md",
            "docs/CLAIMS.md",
            "explorer/index.html",
            "experiment/preregistration.json",
            "experiment/corpus.json",
            "experiment/historical-study.json",
            "rails/agl/cli.py",
            "rails/agl/comparison.py",
            ".github/workflows/prove.yml",
            "schemas/preregistration.schema.json",
        )
        for relative in surfaces:
            with self.subTest(path=relative):
                text = (ROOT / relative).read_text(encoding="utf-8").lower()
                self.assertNotIn("preregistered", text)

    def test_claims_page_records_the_public_history_boundary(self) -> None:
        claims = (ROOT / "docs/CLAIMS.md").read_text(encoding="utf-8")
        normalized = " ".join(claims.split())
        self.assertIn("1fcb32d15cff84a7be32ec9b5f8f31e4e104787b", claims)
        self.assertIn("does not establish that the protocol predates execution", normalized)
        self.assertIn("they do not assert prospective chronology", normalized)

    def test_reader_surfaces_call_l1_to_l3_the_primary_comparison(self) -> None:
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        explorer = (ROOT / "explorer/index.html").read_text(encoding="utf-8")
        self.assertIn("The primary contrast is L1 → L3", readme)
        self.assertIn("Primary comparison · L1 versus L3", explorer)
        self.assertNotIn("The confirmatory contrast", readme)
        self.assertNotIn("Confirmatory slice", explorer)

    def test_audit_does_not_reopen_closed_v6(self) -> None:
        audit = (ROOT / "AUDIT.md").read_text(encoding="utf-8")
        self.assertIn("V6 is closed", audit)
        self.assertIn("case 54 proves", audit)
        self.assertNotIn("verifier soundness gap still open is V6", audit)


if __name__ == "__main__":
    unittest.main()
