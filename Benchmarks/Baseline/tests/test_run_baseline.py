#!/usr/bin/env python3
"""Focused tests for the content-safe baseline collector."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


BASELINE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASELINE_ROOT))

import run_baseline  # noqa: E402


class BaselineCollectorTests(unittest.TestCase):
    def test_summary_is_aggregate_only_and_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "latest.json"
            path.write_text(
                json.dumps(
                    {
                        "dataset": "LibriSpeech test-clean and test-other",
                        "examples_per_split": 50,
                        "profiles": {
                            "adaptive": {
                                "combined_wer": 0.0404,
                                "p50_seconds": 0.3,
                                "cases": [
                                    {
                                        "id": "synthetic-case",
                                        "reference_words": 3,
                                        "word_errors": 1,
                                    }
                                ],
                            },
                            "accuracy": {
                                "combined_wer": 0.0431,
                                "p50_seconds": 0.4,
                            },
                        },
                    }
                ),
                encoding="utf-8",
            )
            first = run_baseline.summarize_result(path)
            second = run_baseline.summarize_result(path)

        self.assertEqual(first, second)
        self.assertEqual([record["decode_profile"] for record in first], ["precision", "adaptive"])
        rendered = run_baseline.jsonl(first)
        self.assertNotIn("synthetic-case", rendered)
        self.assertNotIn("reference_words", rendered)
        self.assertNotIn("word_errors", rendered)

    def test_content_bearing_result_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "unsafe.json"
            path.write_text(
                json.dumps(
                    {
                        "profiles": {
                            "accuracy": {
                                "combined_wer": 0.1,
                                "text": "must not be collected",
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaises(run_baseline.BaselineError):
                run_baseline.summarize_result(path)

    def test_camel_case_content_bearing_result_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "unsafe.json"
            path.write_text(
                json.dumps(
                    {
                        "profiles": {
                            "accuracy": {
                                "combined_wer": 0.1,
                                "audioPath": "/private/audio.wav",
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaises(run_baseline.BaselineError):
                run_baseline.summarize_result(path)

    def test_predecode_result_records_decode_while_speaking_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "predecode.json"
            path.write_text(
                json.dumps(
                    {
                        "dataset": "LibriSpeech test-clean and test-other",
                        "examples_per_split": 50,
                        "strategy": "adaptive",
                        "full_wer": 0.04,
                        "predecode_wer": 0.05,
                        "full_p50_release_seconds": 0.3,
                        "predecode_p50_release_seconds": 0.1,
                    }
                ),
                encoding="utf-8",
            )
            records = run_baseline.summarize_result(path)

        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["processing_mode"], "decodeWhileSpeaking")
        self.assertEqual(records[0]["decode_profile"], "adaptive")
        self.assertEqual(records[0]["metrics"]["predecode_wer"], 0.05)

    def test_mode_inventory_does_not_invent_unmeasured_metrics(self) -> None:
        inventory = run_baseline._mode_inventory()
        self.assertEqual(
            [entry["id"] for entry in inventory],
            ["afterRecording", "modelReady", "decodeWhileSpeaking"],
        )
        self.assertEqual(inventory[0]["status"], "smoke_only")
        self.assertEqual(inventory[1]["status"], "smoke_only")
        self.assertIn("measured", str(inventory[2]["status"]))

    def test_corpus_metadata_hashes_only_tracked_selection_files(self) -> None:
        metadata = run_baseline._corpus_metadata(Path(__file__).resolve().parents[3])
        self.assertEqual(metadata["id"], "librispeech_test100_local")
        selection = metadata["selection"]
        self.assertEqual(selection["manifest"]["status"], "present")
        self.assertEqual(selection["case_ids"]["status"], "present")
        self.assertNotIn("audio_path", json.dumps(metadata))

    def test_model_pin_is_recorded_and_known(self) -> None:
        pins = dict(run_baseline.MODEL_PINS)
        self.assertEqual(
            pins["ggml-large-v3-turbo-q5_0.bin"],
            "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
        )

    def test_unknown_model_is_rejected_before_hashing(self) -> None:
        with self.assertRaises(run_baseline.BaselineError):
            run_baseline._model_metadata(Path("unrecorded-model.bin"))

    def test_revision_classifies_current_main_commit_without_release_claim(self) -> None:
        self.assertTrue(run_baseline.AUDITED_CURRENT_MAIN_COMMIT)
        self.assertNotEqual(
            run_baseline.AUDITED_CURRENT_MAIN_COMMIT,
            run_baseline.AUDITED_RELEASE_COMMIT,
        )


if __name__ == "__main__":
    unittest.main()
