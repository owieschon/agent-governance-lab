from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from rails.agl.comparison import (
    CONFIRMATORY,
    NO_CONFIRMATORY,
    _invalid_result,
    assess_protocol,
    canonical_json,
    generate_or_check,
    load_context,
    observed_bindings,
    run_experiment,
    sha256_bytes,
    sha256_file,
    validate_case_receipt,
    validate_engineering_decision,
    validate_historical_study,
    validate_result,
)


ROOT = Path(__file__).resolve().parents[1]


class ComparisonContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.preregistration = json.loads(
            (ROOT / "experiment/preregistration.json").read_text(encoding="utf-8")
        )
        self.corpus = json.loads(
            (ROOT / "experiment/corpus.json").read_text(encoding="utf-8")
        )
        self.result = json.loads(
            (ROOT / "explorer/data/experiment.json").read_text(encoding="utf-8")
        )
        self.receipts = [
            json.loads(
                (ROOT / "explorer/data/receipts" / f"{case['id']}.json").read_text(
                    encoding="utf-8"
                )
            )
            for case in self.corpus["cases"]
        ]

    def test_checked_result_is_content_addressed_and_denominated(self) -> None:
        validate_result(self.result)
        self.assertEqual(self.result["status"], CONFIRMATORY)
        self.assertEqual(self.result["confirmatory_contrast"], ["L1", "L3"])
        self.assertEqual(self.result["denominators"]["violation_cases"]["count"], 6)
        self.assertEqual(self.result["denominators"]["clean_controls"]["count"], 2)
        self.assertEqual(
            self.result["metrics"]["by_policy"]["L1"]["containment"],
            {"numerator": 0, "denominator": 6},
        )
        self.assertEqual(
            self.result["metrics"]["by_policy"]["L3"]["containment"],
            {"numerator": 6, "denominator": 6},
        )
        self.assertEqual(
            self.result["metrics"]["by_policy"]["L3"]["false_blocks"],
            {"numerator": 0, "denominator": 2},
        )
        serialized = json.dumps(self.result).lower()
        self.assertIn("no productivity", serialized)
        self.assertNotIn("productivity_gain", serialized)
        self.assertNotIn("time_saved", serialized)

    def test_all_case_receipts_bind_four_treatments_to_one_candidate(self) -> None:
        paths = sorted((ROOT / "explorer/data/receipts").glob("*.json"))
        self.assertEqual(len(paths), 8)
        for path in paths:
            with self.subTest(path=path.name):
                receipt = json.loads(path.read_text(encoding="utf-8"))
                validate_case_receipt(receipt)
                digests = receipt["treatment_candidate_sha256"]
                self.assertEqual(list(digests), ["L0", "L1", "SHAM", "L3"])
                self.assertEqual(len(set(digests.values())), 1)
                self.assertEqual(
                    receipt["treatments"]["SHAM"]["observation"]["evidence_sha256"],
                    receipt["treatments"]["L3"]["evidence_sha256"],
                )

    def test_current_protocol_bindings_match(self) -> None:
        observed, expected, reasons = assess_protocol(
            ROOT, self.preregistration, self.corpus
        )
        self.assertEqual(reasons, [])
        self.assertEqual(observed, expected)
        self.assertEqual(observed, observed_bindings(ROOT))

    def test_missing_independent_label_suppresses_all_metrics(self) -> None:
        corpus = copy.deepcopy(self.corpus)
        del corpus["cases"][2]["expected_label"]
        observed, expected, reasons = assess_protocol(ROOT, self.preregistration, corpus)
        self.assertTrue(any("independent expected label" in reason for reason in reasons))
        result = _invalid_result(
            self.preregistration,
            load_context(ROOT),
            observed,
            expected,
            reasons,
        )
        validate_result(result)
        self.assertEqual(result["status"], NO_CONFIRMATORY)
        self.assertIsNone(result["metrics"])
        self.assertFalse(result["headline_eligible"])

    def test_binding_drift_suppresses_all_metrics(self) -> None:
        drifted = observed_bindings(ROOT)
        drifted["corpus_sha256"] = "0" * 64
        with mock.patch(
            "rails.agl.comparison.observed_bindings", return_value=drifted
        ):
            observed, expected, reasons = assess_protocol(
                ROOT, self.preregistration, self.corpus
            )
        self.assertIn("binding drift: corpus_sha256", reasons)
        result = _invalid_result(
            self.preregistration,
            load_context(ROOT),
            observed,
            expected,
            reasons,
        )
        self.assertEqual(result["status"], NO_CONFIRMATORY)
        self.assertIsNone(result["metrics"])

    def test_regular_generation_emits_invalid_result_without_receipts(self) -> None:
        observed = observed_bindings(ROOT)
        invalid = _invalid_result(
            self.preregistration,
            load_context(ROOT),
            observed,
            observed,
            ["binding drift: corpus_sha256"],
        )
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "data"
            with mock.patch(
                "rails.agl.comparison.run_experiment", return_value=(invalid, [])
            ):
                with self.assertRaisesRegex(ValueError, NO_CONFIRMATORY):
                    generate_or_check(ROOT, output)
            emitted = json.loads(
                (output / "experiment.json").read_text(encoding="utf-8")
            )
            self.assertEqual(emitted["status"], NO_CONFIRMATORY)
            self.assertIsNone(emitted["metrics"])
            self.assertEqual(list((output / "receipts").glob("*.json")), [])

    def test_separate_context_cases_preserve_their_claim_boundaries(self) -> None:
        context = load_context(ROOT)
        historical = context["historical_study"]["record"]
        engineering = context["engineering_decision"]["record"]
        validate_historical_study(historical)
        validate_engineering_decision(engineering)
        self.assertEqual(historical["decision"]["status"], NO_CONFIRMATORY)
        self.assertIsNone(historical["decision"]["headline_metrics"])
        self.assertIn("Excluded", engineering["separation"])
        self.assertEqual(engineering["release"]["decision"], "stop")

    def test_engineering_decision_rejects_a_rewritten_stop(self) -> None:
        engineering = load_context(ROOT)["engineering_decision"]["record"]
        weakened = copy.deepcopy(engineering)
        weakened["release"]["decision"] = "release"
        with self.assertRaisesRegex(ValueError, "preserve the stop"):
            validate_engineering_decision(weakened)

    def test_corpus_and_mutable_lock_cannot_rebind_the_trusted_release(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            clone = Path(directory) / "repo"
            shutil.copytree(
                ROOT,
                clone,
                ignore=shutil.ignore_patterns(
                    ".git",
                    "node_modules",
                    "test-results",
                    ".ruff_cache",
                ),
            )
            corpus_path = clone / "experiment/corpus.json"
            corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
            oracle = next(case for case in corpus["cases"] if case["id"] == "oracle-tampering")
            oracle["expected_label"] = "clean"
            corpus_path.write_text(json.dumps(corpus, indent=2) + "\n", encoding="utf-8")
            bindings_path = clone / "experiment/bindings.json"
            bindings = json.loads(bindings_path.read_text(encoding="utf-8"))
            bindings["corpus_sha256"] = sha256_file(corpus_path)
            bindings_path.write_text(json.dumps(bindings, indent=2) + "\n", encoding="utf-8")
            manifest_path = clone / "experiment/trusted-release.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            rebound_paths = {
                "experiment/corpus.json": corpus_path,
                "experiment/bindings.json": bindings_path,
            }
            for item in manifest["files"]:
                if item["path"] in rebound_paths:
                    item["sha256"] = sha256_file(rebound_paths[item["path"]])
            manifest_path.write_text(
                json.dumps(manifest, indent=2) + "\n",
                encoding="utf-8",
            )

            preregistration = json.loads(
                (clone / "experiment/preregistration.json").read_text(encoding="utf-8")
            )
            observed, expected, reasons = assess_protocol(
                clone,
                preregistration,
                corpus,
            )
            result, receipts = run_experiment(clone)

        self.assertNotEqual(observed, expected)
        self.assertIn(
            "trusted release manifest differs from the code-anchored digest",
            reasons,
        )
        self.assertIn("binding drift: trusted_release_sha256", reasons)
        self.assertEqual(result["status"], NO_CONFIRMATORY)
        self.assertIsNone(result["metrics"])
        self.assertEqual(receipts, [])

    def test_schema_drift_is_part_of_the_immutable_trust_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            clone = Path(directory) / "repo"
            shutil.copytree(
                ROOT,
                clone,
                ignore=shutil.ignore_patterns(".git", "node_modules", "test-results", ".ruff_cache"),
            )
            schema_path = clone / "schemas/comparison-result.schema.json"
            schema = json.loads(schema_path.read_text(encoding="utf-8"))
            schema["title"] = "Rebound result schema"
            schema_path.write_text(json.dumps(schema, indent=2) + "\n", encoding="utf-8")
            preregistration = json.loads(
                (clone / "experiment/preregistration.json").read_text(encoding="utf-8")
            )
            corpus = json.loads(
                (clone / "experiment/corpus.json").read_text(encoding="utf-8")
            )
            _observed, _expected, reasons = assess_protocol(
                clone,
                preregistration,
                corpus,
            )

        self.assertIn(
            "trusted source drift: schemas/comparison-result.schema.json",
            reasons,
        )

    def test_rehashed_treatment_forgery_fails_semantic_reexecution(self) -> None:
        receipt = copy.deepcopy(
            next(item for item in self.receipts if item["case_id"] == "oracle-tampering")
        )
        receipt["treatments"]["L3"]["decision"] = "RELEASED"
        receipt["treatments"]["L3"]["reason"] = "ordinary_tests_green"
        body = dict(receipt)
        body.pop("receipt_sha256")
        receipt["receipt_sha256"] = sha256_bytes(canonical_json(body))

        with self.assertRaisesRegex(ValueError, "L3 decision, reason"):
            validate_case_receipt(receipt, root=ROOT)

    def test_rehashed_evidence_forgery_fails_fresh_mechanism_reexecution(self) -> None:
        receipt = copy.deepcopy(
            next(item for item in self.receipts if item["case_id"] == "clean-baseline")
        )
        evidence = receipt["treatments"]["L1"]["evidence"]
        evidence["collected"] = 999
        receipt["treatments"]["L1"]["evidence_sha256"] = sha256_bytes(
            canonical_json(evidence)
        )
        body = dict(receipt)
        body.pop("receipt_sha256")
        receipt["receipt_sha256"] = sha256_bytes(canonical_json(body))

        with self.assertRaisesRegex(ValueError, "fresh bound mechanism execution"):
            validate_case_receipt(receipt, root=ROOT)

    def test_rehashed_result_metrics_fail_receipt_recomputation(self) -> None:
        result = copy.deepcopy(self.result)
        result["metrics"]["by_policy"]["L3"]["containment"]["numerator"] = 0
        body = dict(result)
        body.pop("result_sha256")
        result["result_sha256"] = sha256_bytes(canonical_json(body))

        with self.assertRaisesRegex(ValueError, "metrics differ from bound case receipts"):
            validate_result(
                result,
                self.receipts,
                root=ROOT,
                reexecute_receipts=False,
            )

    def test_rehashed_denominator_and_case_outcome_forgeries_fail_recomputation(self) -> None:
        for label, mutate, message in (
            (
                "denominator",
                lambda result: result["denominators"]["violation_cases"].update(
                    {"count": 5}
                ),
                "denominators differ from bound case receipts",
            ),
            (
                "case outcome",
                lambda result: result["cases"][2]["treatments"]["L3"].update(
                    {"decision": "RELEASED"}
                ),
                "case outcomes differ from bound case receipts",
            ),
        ):
            with self.subTest(label=label):
                result = copy.deepcopy(self.result)
                mutate(result)
                body = dict(result)
                body.pop("result_sha256")
                result["result_sha256"] = sha256_bytes(canonical_json(body))
                with self.assertRaisesRegex(ValueError, message):
                    validate_result(
                        result,
                        self.receipts,
                        root=ROOT,
                        reexecute_receipts=False,
                    )


if __name__ == "__main__":
    unittest.main()
