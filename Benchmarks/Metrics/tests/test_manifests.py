#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFESTS = ROOT / "Manifests"


class ManifestTests(unittest.TestCase):
    def _load(self, name: str) -> dict:
        return json.loads((MANIFESTS / name).read_text(encoding="utf-8"))

    def test_smoke_manifest_keeps_the_existing_100_cases(self) -> None:
        manifest = self._load("smoke-100.json")
        case_list = ROOT / "BenchmarkSuite" / "datasets" / "merged" / "librispeech-100" / "case_ids.txt"
        self.assertEqual(manifest["caseCount"], 100)
        self.assertEqual(len(case_list.read_text(encoding="utf-8").splitlines()), 100)
        digest = hashlib.sha256(case_list.read_bytes()).hexdigest()
        self.assertEqual(digest, manifest["caseList"]["sha256"])

    def test_public_manifest_covers_required_tracks_without_redistribution(self) -> None:
        manifest = self._load("full-public.json")
        ids = {entry["id"] for entry in manifest["entries"]}
        for required in {"librispeech-test-clean", "librispeech-test-other", "earnings22", "contextual-earnings22", "tedlium3", "ami-single-distant-microphone", "musan-controlled-mixtures"}:
            self.assertIn(required, ids)
        self.assertEqual(manifest["privacy"]["redistribution"], "metadata-only")

    def test_application_fixture_is_synthetic_and_speaker_session_disjoint(self) -> None:
        manifest = self._load("application-corpus.json")
        fixture = ROOT / "Fixtures" / "application-corpus.synthetic.jsonl"
        self.assertEqual(manifest["privacy"]["redistribution"], "synthetic")
        self.assertFalse(manifest["privacy"]["containsTranscriptText"])
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(), manifest["privacy"]["fixtureSha256"])
        rows = [json.loads(line) for line in fixture.read_text(encoding="utf-8").splitlines() if line.strip()]
        self.assertEqual(len(rows), manifest["caseCount"])
        seen: dict[str, tuple[str, str]] = {}
        for row in rows:
            partition = row["partition"]
            identity = (row["speakerId"], row["sessionId"])
            if partition in seen:
                continue
            seen[partition] = identity
        by_partition = {}
        for row in rows:
            by_partition.setdefault(row["partition"], set()).add((row["speakerId"], row["sessionId"]))
        partitions = list(by_partition.values())
        for index, identities in enumerate(partitions):
            for other in partitions[index + 1 :]:
                self.assertTrue(identities.isdisjoint(other))
        for row in rows:
            self.assertNotIn("audio", row)
            self.assertNotIn("reference", row)
            self.assertNotIn("transcript", row)


if __name__ == "__main__":
    unittest.main()
