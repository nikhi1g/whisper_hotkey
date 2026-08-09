from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from calibrate import CalibrationError, build_artifact, load_rows, metric_summary


ROOT = Path(__file__).resolve().parent


class CalibrationTests(unittest.TestCase):
    def test_only_calibration_partition_fits_and_test_is_evaluation_only(self) -> None:
        artifact = build_artifact(load_rows(ROOT / "synthetic_labeled.jsonl"))
        self.assertEqual(len(artifact["groups"]), 2)
        for group in artifact["groups"]:
            self.assertGreater(group["calibrationExampleCount"], 0)
            self.assertGreater(group["heldOutExampleCount"], 0)
            self.assertEqual(group["operatingPoint"]["status"], "uncalibrated")

    def test_content_fields_are_rejected_before_summary(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl") as handle:
            handle.write(
                json.dumps(
                    {
                        "id": "bad",
                        "partition": "calibration",
                        "engine": "whisperTurbo",
                        "model": "turbo-q5",
                        "profile": "precision",
                        "raw_error_probability": 0.5,
                        "is_error": False,
                        "transcript": "must not be accepted",
                    }
                )
            )
            handle.flush()
            with self.assertRaises(CalibrationError):
                load_rows(Path(handle.name))

    def test_repeated_artifact_generation_is_byte_stable(self) -> None:
        rows = load_rows(ROOT / "synthetic_labeled.jsonl")
        first = json.dumps(build_artifact(rows), sort_keys=True, indent=2)
        second = json.dumps(build_artifact(rows), sort_keys=True, indent=2)
        self.assertEqual(first, second)

    def test_nce_uses_standard_asr_one_minus_ratio_convention(self) -> None:
        rows = [
            {"is_error": False},
            {"is_error": True},
        ]
        perfect = metric_summary(rows, [0.0, 1.0])
        baseline = metric_summary(rows, [0.5, 0.5])
        worse = metric_summary(rows, [1.0, 0.0])
        self.assertAlmostEqual(perfect["nce"], 1.0, places=12)
        self.assertAlmostEqual(baseline["nce"], 0.0, places=12)
        self.assertLess(worse["nce"], 0.0)


if __name__ == "__main__":
    unittest.main()
