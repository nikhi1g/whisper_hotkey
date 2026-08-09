#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from Metrics.paired_bootstrap import paired_bootstrap


ROWS = [
    {"id": "one", "subset": "clean", "reference": "one two three", "baseline": "one x three", "candidate": "one two three"},
    {"id": "two", "subset": "clean", "reference": "four five", "baseline": "four five", "candidate": "four six"},
    {"id": "three", "subset": "other", "reference": "seven eight", "baseline": "seven", "candidate": "seven eight"},
]


class PairedBootstrapTests(unittest.TestCase):
    def test_bootstrap_is_paired_and_seeded(self) -> None:
        first = paired_bootstrap(ROWS, samples=200, seed=11)
        second = paired_bootstrap(ROWS, samples=200, seed=11)
        self.assertEqual(first, second)
        self.assertLess(first["candidateWER"], first["baselineWER"])
        self.assertEqual(first["improvementCount"], 2)
        self.assertEqual(first["regressionCount"], 1)
        self.assertEqual(first["ci95"][0] <= first["ci95"][1], True)

    def test_result_has_no_transcript_text(self) -> None:
        result = paired_bootstrap(ROWS, samples=200, seed=2)
        serialized = json.dumps(result)
        for row in ROWS:
            self.assertNotIn(row["reference"], serialized)
            self.assertNotIn(row["baseline"], serialized)
            self.assertNotIn(row["candidate"], serialized)

    def test_rejects_tiny_sample(self) -> None:
        with self.assertRaises(ValueError):
            paired_bootstrap(ROWS, samples=99)


if __name__ == "__main__":
    unittest.main()
