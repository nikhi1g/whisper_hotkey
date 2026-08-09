#!/usr/bin/env python3
"""Focused tests for bounded, content-free W13 profiling tools."""

from __future__ import annotations

import json
import stat
import sys
import tempfile
import textwrap
import unittest
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import profile_performance as profile  # noqa: E402
import soak_cancel  # noqa: E402


def synthetic_wav(root: Path) -> Path:
    path = root / "synthetic.wav"
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16_000)
        output.writeframes(b"\0\0" * 1_600)
    path.chmod(0o600)
    return path


def fake_helper(root: Path) -> Path:
    path = root / "fake-helper"
    path.write_text(
        textwrap.dedent(
            """
            #!/usr/bin/env python3
            import json
            import sys
            import time

            print(json.dumps({"event": "ready"}), flush=True)
            for line in sys.stdin:
                command = json.loads(line)
                if command.get("command") == "transcribe":
                    time.sleep(0.05)
                    print(json.dumps({"event": "result", "text": "synthetic"}), flush=True)
            """
        ).lstrip(),
        encoding="utf-8",
    )
    path.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
    return path


class PerformanceToolTests(unittest.TestCase):
    def test_percentiles_are_nearest_rank_and_rtf_is_aggregate_only(self) -> None:
        self.assertEqual(profile.percentile([0.1, 0.2, 0.3, 0.4], 0.50), 0.2)
        self.assertEqual(profile.percentile([0.1, 0.2, 0.3, 0.4], 0.95), 0.4)
        metrics = profile.latency_metrics([0.2, 0.4], [1.0, 2.0])
        self.assertEqual(metrics["sample_count"], 2)
        self.assertAlmostEqual(metrics["aggregate_rtf"], 0.2)
        self.assertNotIn("text", json.dumps(metrics))

    def test_content_bearing_report_fields_fail_closed(self) -> None:
        with self.assertRaises(profile.PerformanceError):
            profile.assert_content_free({"transcript": "not retained"})
        with self.assertRaises(profile.PerformanceError):
            profile.assert_content_free({"audioPath": "/private/input.wav"})
        profile.assert_content_free({"audio_seconds": 0.2, "peak_rss_bytes": 123})

    def test_host_metadata_excludes_identity_fields(self) -> None:
        metadata = profile.host_metadata()
        rendered = json.dumps(metadata).casefold()
        self.assertNotIn("serial", rendered)
        self.assertNotIn("uuid", rendered)
        self.assertNotIn("username", rendered)
        self.assertNotIn("/users/", rendered)

    def test_preflight_blocks_missing_engines_without_inventing_metrics(self) -> None:
        result = profile.engine_preflight(
            whisper_helper=Path("missing-helper"),
            whisper_model=Path("missing-model"),
            parakeet_runner=Path("missing-parakeet"),
            wav_root=Path("missing-wavs"),
        )
        self.assertEqual(result["whisper_cpp"]["status"], "blocked")
        self.assertEqual(result["parakeet"]["status"], "blocked")
        comparison = profile.placement_comparison(result)
        self.assertEqual(comparison["status"], "unavailable")
        self.assertIsNone(comparison["sequential"])
        self.assertIsNone(comparison["heterogeneous_concurrent"])

    def test_lower_memory_matrix_does_not_fabricate_results(self) -> None:
        matrix = profile.lower_memory_matrix()
        self.assertEqual([row["memory_gb"] for row in matrix["tiers"]], [8, 16, 24])
        self.assertTrue(all(row["status"] == "unmeasured" for row in matrix["tiers"]))
        self.assertTrue(all(row["metrics"] is None for row in matrix["tiers"]))

    def test_profile_reaps_owned_helper_and_drops_helper_text(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            wav = synthetic_wav(root)
            helper = fake_helper(root)
            model = root / "model.bin"
            model.write_bytes(b"synthetic-model")
            model.chmod(0o600)
            cases = profile.load_audio_cases(root, maximum_cases=1)
            result = profile.run_profile(
                helper_path=helper,
                model_path=model,
                cases=cases,
                repeats=1,
                threads=1,
                strategy="beam",
                timeout_seconds=2.0,
            )
            profile.assert_content_free(result)
            self.assertEqual(result["status"], "measured")
            self.assertEqual(result["metrics"]["sample_count"], 1)
            self.assertTrue(result["metrics"]["helper_process"]["owned_process_reaped"])
            self.assertNotIn("synthetic", json.dumps(result))

    def test_cancel_soak_reaps_each_cancelled_helper(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            synthetic_wav(root)
            helper = fake_helper(root)
            model = root / "model.bin"
            model.write_bytes(b"synthetic-model")
            model.chmod(0o600)
            cases = profile.load_audio_cases(root, maximum_cases=1)
            result = soak_cancel.run_soak(
                helper_path=helper,
                model_path=model,
                cases=cases,
                iterations=2,
                cancel_every=1,
                cancel_after_seconds=0.01,
                threads=1,
                strategy="beam",
                timeout_seconds=2.0,
            )
            profile.assert_content_free(result)
            self.assertEqual(result["cancelled_iterations"], 2)
            self.assertEqual(result["leaked_owned_processes"], 0)


if __name__ == "__main__":
    unittest.main()
