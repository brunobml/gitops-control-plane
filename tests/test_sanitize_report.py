#!/usr/bin/env python3
"""
Unit tests for scripts/lib/sanitize_report.py
"""

import json
import os
import tempfile
import unittest
from pathlib import Path

# Add scripts/lib to path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts" / "lib"))

from sanitize_report import sanitize_xml, sanitize_text, build_redaction_pairs


class TestSanitizeReport(unittest.TestCase):

    def setUp(self):
        self.test_dir = tempfile.TemporaryDirectory()
        self.dir_path = Path(self.test_dir.name)
        self.known_secrets = {
            "SuperSecretPassword123!": "test-password.secret",
            "AKIATESTEXACTKEY123": "test-key.secret"
        }

    def tearDown(self):
        self.test_dir.cleanup()

    def test_exact_value_redaction(self):
        pairs = build_redaction_pairs(self.known_secrets)
        raw_text = "Login failed with SuperSecretPassword123! and user admin"
        clean = sanitize_text(raw_text, pairs, "/home/bleite", "OMEN30L")
        self.assertNotIn("SuperSecretPassword123!", clean)
        self.assertIn("[REDACTED:test-password.secret]", clean)

    def test_pattern_redaction(self):
        pairs = build_redaction_pairs(self.known_secrets)
        raw_text = "Header: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc123def456ghi789 and AKIA1111222233334444"
        clean = sanitize_text(raw_text, pairs, "/home/bleite", "OMEN30L")
        self.assertNotIn("eyJhbGci", clean)
        self.assertIn("Bearer [REDACTED:JWT]", clean)
        self.assertIn("[REDACTED:AWS_KEY_ID]", clean)

    def test_hostname_and_path_scrubbing(self):
        pairs = build_redaction_pairs(self.known_secrets)
        raw_text = "Error in /home/bleite/repos/gitops-control-plane/tests on OMEN30L"
        clean = sanitize_text(raw_text, pairs, "/home/bleite", "OMEN30L")
        self.assertNotIn("/home/bleite", clean)
        self.assertIn("~/repos/gitops-control-plane/tests", clean)
        self.assertNotIn("OMEN30L", clean)
        self.assertIn("lab-host", clean)

    def test_xml_failure_and_system_out(self):
        input_xml = self.dir_path / "raw.xml"
        output_xml = self.dir_path / "clean.xml"

        xml_content = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites time="1.0">
<testsuite name="smoke.bats" tests="2" failures="1" errors="0" skipped="0" hostname="OMEN30L">
    <testcase classname="smoke.bats" name="test failure" time="0.5">
        <failure message="Error SuperSecretPassword123!">Trace: /home/bleite/test.sh failed with SuperSecretPassword123!</failure>
    </testcase>
    <testcase classname="smoke.bats" name="test pass" time="0.5">
        <system-out>Passed test with key AKIATESTEXACTKEY123</system-out>
    </testcase>
</testsuite>
</testsuites>
"""
        input_xml.write_text(xml_content, encoding="utf-8")
        summary, sha256 = sanitize_xml(input_xml, output_xml, self.known_secrets)

        clean_text = output_xml.read_text(encoding="utf-8")
        self.assertNotIn("SuperSecretPassword123!", clean_text)
        self.assertNotIn("AKIATESTEXACTKEY123", clean_text)
        self.assertNotIn("/home/bleite", clean_text)
        self.assertNotIn("OMEN30L", clean_text)
        self.assertIn("[REDACTED:test-password.secret]", clean_text)
        self.assertIn("[REDACTED:test-key.secret]", clean_text)
        self.assertEqual(summary["total"], 2)
        self.assertEqual(summary["passed"], 1)
        self.assertEqual(summary["failed"], 1)

    def test_fail_closed_on_unredacted_secret(self):
        input_xml = self.dir_path / "raw_fail_closed.xml"
        output_xml = self.dir_path / "clean_fail_closed.xml"

        xml_content = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites time="1.0">
<testsuite name="smoke.bats" tests="1" failures="0" errors="0" skipped="0">
    <testcase classname="smoke.bats" name="test" time="0.5" />
</testsuite>
</testsuites>
"""
        input_xml.write_text(xml_content, encoding="utf-8")
        # Intentionally inject a known secret that appears in the XML structure itself (e.g. tag attribute)
        # to test that the fail-closed scanner catches any residual leak
        known_with_leak = dict(self.known_secrets)
        known_with_leak["smoke.bats"] = "leaked-testname"

        with self.assertRaises(ValueError) as ctx:
            sanitize_xml(input_xml, output_xml, known_with_leak)
        self.assertIn("SECURITY ALERT", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
