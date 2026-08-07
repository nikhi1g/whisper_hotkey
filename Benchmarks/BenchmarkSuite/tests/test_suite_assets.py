#!/usr/bin/env python3
"""Integrity checks for tracked BenchmarkSuite artifacts."""

from __future__ import annotations

import json
from pathlib import Path

import unittest


ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "BenchmarkSuite" / "datasets" / "catalog.json"
MANIFEST_PATH = (
    ROOT / "BenchmarkSuite" / "datasets" / "merged" / "librispeech-100" / "manifest.json"
)


class BenchmarkSuiteAssetTests(unittest.TestCase):
    def test_catalog_has_entries(self) -> None:
        with CATALOG_PATH.open("r", encoding="utf-8") as handle:
            catalog = json.load(handle)
        assert catalog["entries"], "dataset catalog is empty"
        assert isinstance(catalog["entries"], list)

        for entry in catalog["entries"]:
            for key in ("id", "name", "source_url", "category", "license"):
                assert key in entry and entry[key], f"catalog entry missing {key}"

    def test_merged_manifest_exists(self) -> None:
        assert MANIFEST_PATH.exists(), f"missing merged manifest {MANIFEST_PATH}"
        with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
            manifest = json.load(handle)
        assert manifest["split_counts"]["total"] > 0
        assert manifest["split_counts"]["test-clean"] > 0
        assert manifest["split_counts"]["test-other"] > 0
        assert len(manifest["cases"]) == manifest["split_counts"]["total"]


if __name__ == "__main__":
    unittest.main()
