from __future__ import annotations

import json
import unittest
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AuditParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.elements: list[tuple[str, dict[str, str]]] = []
        self.ids: set[str] = set()
        self.h1_count = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "" for key, value in attrs}
        self.elements.append((tag, values))
        if values.get("id"):
            self.ids.add(values["id"])
        if tag == "h1":
            self.h1_count += 1


class ExplorerStaticAccessibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.html = (ROOT / "explorer/index.html").read_text(encoding="utf-8")
        cls.css = (ROOT / "explorer/styles.css").read_text(encoding="utf-8")
        cls.app_javascript = (ROOT / "explorer/app.js").read_text(encoding="utf-8")
        cls.verification_javascript = (
            ROOT / "explorer/verification.js"
        ).read_text(encoding="utf-8")
        cls.trusted_release_javascript = (
            ROOT / "explorer/trusted-release.js"
        ).read_text(encoding="utf-8")
        cls.javascript = cls.app_javascript + cls.verification_javascript
        cls.parser = AuditParser()
        cls.parser.feed(cls.html)

    def test_document_has_language_landmarks_and_one_primary_heading(self) -> None:
        html = next(attrs for tag, attrs in self.parser.elements if tag == "html")
        self.assertEqual(html.get("lang"), "en")
        self.assertIn("main", self.parser.ids)
        self.assertEqual(self.parser.h1_count, 1)
        self.assertTrue(any(tag == "nav" and attrs.get("aria-label") for tag, attrs in self.parser.elements))

    def test_controls_and_dialog_have_accessible_names(self) -> None:
        for tag, attrs in self.parser.elements:
            if tag == "button":
                self.assertEqual(attrs.get("type"), "button")
            if tag == "dialog":
                self.assertIn(attrs.get("aria-labelledby"), self.parser.ids)
        skip = next(attrs for tag, attrs in self.parser.elements if tag == "a" and "skip-link" in attrs.get("class", ""))
        self.assertEqual(skip.get("href"), "#main")

    def test_assets_are_local_and_content_security_is_simple(self) -> None:
        for tag, attrs in self.parser.elements:
            if tag == "script" and attrs.get("src"):
                self.assertFalse(attrs["src"].startswith(("http://", "https://")))
            if tag == "link" and attrs.get("rel") == "stylesheet":
                self.assertFalse(attrs["href"].startswith(("http://", "https://")))
            self.assertNotIn("style", attrs)

    def test_focus_reduced_motion_and_client_digest_verification_exist(self) -> None:
        self.assertIn(":focus-visible", self.css)
        self.assertIn("prefers-reduced-motion: reduce", self.css)
        self.assertIn("crypto.subtle.digest", self.javascript)
        self.assertIn("receipt_sha256", self.javascript)
        self.assertIn("result_sha256", self.javascript)

    def test_browser_trust_root_is_separate_from_mutable_result_json(self) -> None:
        scripts = [
            attrs["src"]
            for tag, attrs in self.parser.elements
            if tag == "script" and attrs.get("src")
        ]
        self.assertEqual(
            scripts,
            ["trusted-release.js", "verification.js", "app.js"],
        )
        result = json.loads(
            (ROOT / "explorer/data/experiment.json").read_text(encoding="utf-8")
        )
        self.assertIn(result["result_sha256"], self.trusted_release_javascript)
        self.assertIn(
            result["bindings"]["expected"]["trusted_release_sha256"],
            self.trusted_release_javascript,
        )
        self.assertNotIn("0" * 64, self.trusted_release_javascript)

    def test_generated_data_has_no_remote_or_private_payload(self) -> None:
        result = json.loads((ROOT / "explorer/data/experiment.json").read_text(encoding="utf-8"))
        serialized = json.dumps(result)
        self.assertNotIn("transcript", serialized.lower())
        self.assertNotIn("session_id", serialized.lower())
        self.assertEqual(result["scope"], "public synthetic mechanism demonstration")


if __name__ == "__main__":
    unittest.main()
