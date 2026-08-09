"""Focused deterministic tests for the content-safe verifier harness."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import run_experiments  # noqa: E402


def _case_digest(number: int) -> str:
    return "sha256:" + (f"{number:064x}")


def _edit(position: int, *, accepted: bool = True, locked: bool = False) -> dict[str, object]:
    return {
        "position": position,
        "accepted": accepted,
        "locked": locked,
        "anchorsPreserved": True,
        "numbersPreserved": True,
        "alignmentValid": True,
        "generationCurrent": True,
    }


def _measurements(items: list[dict[str, object]]) -> dict[str, object]:
    return {
        "schema": run_experiments.MEASUREMENT_SCHEMA,
        "schemaVersion": 1,
        "candidateId": "whisper-large-v3",
        "provenance": {
            "runtimeVersion": "1.9.1",
            "runtimeCommit": "f049fff95a089aa9969deb009cdd4892b3e74916",
            "modelSha256": "a" * 64,
            "corpusManifestSha256": "b" * 64,
        },
        "items": items,
    }


class VerifierExperimentTests(unittest.TestCase):
    def test_overlap_oracle_and_guarded_repair_metrics(self) -> None:
        payload = _measurements(
            [
                {
                    "caseIdHash": _case_digest(1),
                    "referenceWordCount": 10,
                    "primaryErrorPositions": [1, 3],
                    "verifierErrorPositions": [3, 8],
                    "edits": [_edit(1), _edit(3), _edit(4)],
                    "audioDurationMs": 1000,
                    "verifierSpanDurationsMs": [100, 120],
                    "latencyMs": 100,
                    "coldLoadMs": 500,
                    "warmLoadMs": 100,
                    "peakRssMiB": 900,
                },
                {
                    "caseIdHash": _case_digest(2),
                    "referenceWordCount": 5,
                    "primaryErrorPositions": [0],
                    "verifierErrorPositions": [],
                    "edits": [_edit(0)],
                    "audioDurationMs": 1000,
                    "verifierSpanDurationsMs": [80],
                    "latencyMs": 200,
                    "coldLoadMs": 700,
                    "warmLoadMs": 200,
                    "peakRssMiB": 1000,
                },
                {
                    "caseIdHash": _case_digest(3),
                    "referenceWordCount": 5,
                    "primaryErrorPositions": [],
                    "verifierErrorPositions": [],
                    "edits": [],
                    "audioDurationMs": 1000,
                    "verifierSpanDurationsMs": [],
                    "latencyMs": 400,
                    "coldLoadMs": 900,
                    "warmLoadMs": 400,
                    "peakRssMiB": 1100,
                },
            ]
        )
        normalized = run_experiments.validate_measurements(payload)
        metrics = run_experiments.aggregate_metrics(normalized)

        overlap = metrics["errorOverlap"]
        self.assertEqual(overlap["primaryErrors"], 3)
        self.assertEqual(overlap["verifierErrors"], 2)
        self.assertEqual(overlap["intersection"], 1)
        self.assertEqual(overlap["union"], 4)
        self.assertAlmostEqual(overlap["jaccard"], 0.25)
        oracle = metrics["oracleRepair"]
        self.assertEqual(oracle["corrected"], 2)
        self.assertAlmostEqual(oracle["rate"], 2 / 3)
        guarded = metrics["guardedRepair"]
        self.assertEqual(guarded["accepted"], 4)
        self.assertEqual(guarded["corrected"], 2)
        self.assertEqual(guarded["introduced"], 2)
        self.assertAlmostEqual(guarded["precision"], 0.5)
        self.assertAlmostEqual(guarded["recall"], 2 / 3)
        self.assertEqual(metrics["latency"]["completionP50Ms"], 200)
        self.assertEqual(metrics["latency"]["completionP95Ms"], 400)
        self.assertEqual(metrics["rss"]["peakRSSMiB"], 1100)
        self.assertAlmostEqual(metrics["spanBudget"]["coverageRatio"], 0.1)

    def test_locked_accept_is_counted_as_high_confidence_corruption(self) -> None:
        item = {
            "caseIdHash": _case_digest(4),
            "referenceWordCount": 2,
            "primaryErrorPositions": [],
            "verifierErrorPositions": [0],
            "edits": [_edit(0, locked=True)],
            "audioDurationMs": 1000,
            "verifierSpanDurationsMs": [],
            "latencyMs": 10,
        }
        metrics = run_experiments.aggregate_metrics(
            run_experiments.validate_measurements(_measurements([item]))
        )
        guarded = metrics["guardedRepair"]
        self.assertEqual(guarded["unsafeAccepts"], 1)
        self.assertEqual(guarded["highConfidenceCorruptions"], 1)
        self.assertAlmostEqual(guarded["highConfidenceCorruptionRate"], 0.5)

    def test_transcript_or_audio_fields_fail_closed(self) -> None:
        payload = _measurements([])
        payload["items"] = [
            {
                "caseIdHash": _case_digest(6),
                "referenceWordCount": 1,
                "primaryErrorPositions": [],
                "verifierErrorPositions": [],
                "edits": [],
                "audioDurationMs": 1000,
                "verifierSpanDurationsMs": [],
                "latencyMs": 1,
                "transcript": "forbidden",
            }
        ]
        with self.assertRaises(run_experiments.VerifierExperimentError):
            run_experiments.validate_measurements(payload)

    def test_span_ratio_and_case_identity_are_bounded(self) -> None:
        ratio_payload = _measurements(
            [
                {
                    "caseIdHash": _case_digest(5),
                    "referenceWordCount": 4,
                    "primaryErrorPositions": [],
                    "verifierErrorPositions": [],
                    "edits": [],
                    "audioDurationMs": 1000,
                    "verifierSpanDurationsMs": [251],
                    "latencyMs": 1,
                }
            ]
        )
        with self.assertRaises(run_experiments.VerifierExperimentError):
            run_experiments.validate_measurements(ratio_payload)

        identity_payload = _measurements(
            [
                {
                    "caseIdHash": "case-5",
                    "referenceWordCount": 4,
                    "primaryErrorPositions": [],
                    "verifierErrorPositions": [],
                    "edits": [],
                    "audioDurationMs": 1000,
                    "verifierSpanDurationsMs": [],
                    "latencyMs": 1,
                }
            ]
        )
        with self.assertRaises(run_experiments.VerifierExperimentError):
            run_experiments.validate_measurements(identity_payload)

    def test_default_preflight_reports_missing_local_prerequisites(self) -> None:
        record = run_experiments.preflight(Path(__file__).resolve().parents[3])
        self.assertEqual(record["status"], "blocked")
        self.assertIn("candidate:whisper-large-v3:artifact:missing", record["blockers"])
        manifest = next(
            check
            for check in record["checks"]
            if check["id"] == "corpus:librispeech_test100:manifest"
        )
        self.assertEqual(manifest["status"], "present_verified")

    def test_jsonl_is_aggregate_only(self) -> None:
        records = run_experiments.build_report(Path(__file__).resolve().parents[3])
        rendered = run_experiments.jsonl(records)
        self.assertNotIn("forbidden", rendered)
        self.assertNotIn("caseIdHash", rendered)
        self.assertIn('"recordType":"decision"', rendered)
        for line in rendered.splitlines():
            json.loads(line)


if __name__ == "__main__":
    unittest.main()
