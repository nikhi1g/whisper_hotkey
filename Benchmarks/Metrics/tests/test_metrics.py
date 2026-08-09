#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from Metrics.normalization import NORMALIZATION_VERSION, normalize_text
from Metrics.scoring import punctuation_metrics, score_pair, score_rows


class FrozenMetricTests(unittest.TestCase):
    def test_normalizer_is_case_and_punctuation_independent(self) -> None:
        self.assertEqual(normalize_text("Café's, TEST—one!"), ["café's", "test", "one"])
        self.assertEqual(NORMALIZATION_VERSION, "whisper-hotkey-wer-normalization-v1")

    def test_pair_reports_normalized_and_display_quality_separately(self) -> None:
        result = score_pair("Hello, world.", "hello world")
        self.assertEqual(result["normalized"]["errors"], 0)
        self.assertGreater(result["display"]["errors"], 0)
        self.assertEqual(result["punctuation"]["byMark"]["."]["falseNegative"], 1)

    def test_punctuation_macro_and_micro_are_numeric(self) -> None:
        result = punctuation_metrics("One, two. Three!", "One, two. Three?")
        self.assertIn(",", result["byMark"])
        self.assertEqual(result["byMark"][","]["f1"], 1.0)
        self.assertGreaterEqual(result["macroF1"], 0.0)
        self.assertLessEqual(result["microF1"], 1.0)

    def test_result_artifact_does_not_contain_transcript_text(self) -> None:
        result = score_rows(
            [
                {
                    "id": "synthetic-1",
                    "reference": "THE private reference",
                    "hypothesis": "the private hypothesis",
                    "latencyMs": 12,
                    "audioDurationMs": 1_000,
                }
            ],
            run_id="synthetic",
            commit="deadbeef",
        )
        serialized = json.dumps(result)
        self.assertNotIn("private reference", serialized)
        self.assertNotIn("private hypothesis", serialized)
        self.assertEqual(result["summary"]["utteranceCount"], 1)
        self.assertEqual(result["normalization"]["version"], NORMALIZATION_VERSION)


if __name__ == "__main__":
    unittest.main()
