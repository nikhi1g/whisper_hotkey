#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from Metrics.ablation_report import REQUIRED_ABLATIONS, build_report


class AblationReportTests(unittest.TestCase):
    def test_required_profiles_are_paired_to_primary(self) -> None:
        rows = [
            {
                "id": "one",
                "reference": "one two",
                "primary": "one x",
                "confidence": "one two",
                "verifier": "one two",
                "fusion": "one two",
                "formatting": "One two.",
            },
            {
                "id": "two",
                "reference": "three four",
                "primary": "three four",
                "confidence": "three four",
                "verifier": "three five",
                "fusion": "three four",
                "formatting": "Three four.",
            },
        ]
        report = build_report(rows, samples=200, seed=3)
        self.assertEqual(tuple(report["requiredAblations"]), REQUIRED_ABLATIONS)
        self.assertEqual(report["missingAblations"], [])
        self.assertEqual(set(report["profiles"]), set(REQUIRED_ABLATIONS))
        self.assertLess(report["profiles"]["+confidence"]["normalizedWER"], report["profiles"]["primary"]["normalizedWER"])

    def test_missing_profile_fails_closed(self) -> None:
        rows = [{"id": "one", "reference": "one", "primary": "one"}, {"id": "two", "reference": "two", "primary": "two"}]
        with self.assertRaises(ValueError):
            build_report(rows, samples=200)


if __name__ == "__main__":
    unittest.main()
