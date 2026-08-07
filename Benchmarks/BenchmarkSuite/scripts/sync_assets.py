#!/usr/bin/env python3
"""Sync local benchmark metadata into the tracked BenchmarkSuite folder."""

from __future__ import annotations

import json
import argparse
from datetime import datetime, timezone
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[2]
LEGACY_DATA = ROOT / "Data"
LEGACY_RESULTS = ROOT / "Results"
SUITE_ROOT = ROOT / "BenchmarkSuite"
SUITE_DATA = SUITE_ROOT / "datasets" / "merged" / "librispeech-100"


def read_latest_results(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def merge_cases() -> None:
    SUITE_DATA.mkdir(parents=True, exist_ok=True)

    latest = read_latest_results(LEGACY_RESULTS / "latest.json")
    if not latest:
        print(f"skipping: missing {LEGACY_RESULTS / 'latest.json'}")
        return

    profile = latest.get("profiles", {}).get("accuracy")
    if not profile or "cases" not in profile:
        raise RuntimeError("latest.json missing expected accuracy cases")

    cases = profile["cases"]
    manifest = {
        "dataset": latest.get("dataset", "LibriSpeech"),
        "examples_per_split": latest.get("examples_per_split"),
        "threads": latest.get("threads"),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": {
            "librispeech_results": str((LEGACY_RESULTS / "latest.json").resolve()),
            "predecode_results": str(
                (LEGACY_RESULTS / "predecode-latest.json").resolve()
            ),
        },
        "split_counts": {
            "total": len(cases),
            "test-clean": len([c for c in cases if c.get("split") == "test-clean"]),
            "test-other": len([c for c in cases if c.get("split") == "test-other"]),
        },
        "cases": [
            {
                "id": c.get("id"),
                "split": c.get("split"),
                "reference_words": c.get("reference_words"),
                "seconds": c.get("seconds"),
                "word_errors": c.get("word_errors"),
                "audio_path": str(
                    (
                        ROOT
                        / "Data"
                        / "WAV"
                        / c.get("split", "test-clean")
                        / f"{c['id']}.wav"
                    ).resolve().relative_to(ROOT.parent.resolve())
                ),
            }
            for c in cases
        ],
    }

    (SUITE_DATA / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    (SUITE_DATA / "case_ids.txt").write_text(
        "\n".join(c["id"] for c in manifest["cases"]) + "\n",
        encoding="utf-8",
    )

    (SUITE_DATA / "wav_paths.txt").write_text(
        "\n".join(c["audio_path"] for c in manifest["cases"]) + "\n",
        encoding="utf-8",
    )

    # Keep a copy of the raw result for direct diff/review.
    shutil.copy2(LEGACY_RESULTS / "latest.json", SUITE_DATA / "whisper-latest.json")
    predecode = LEGACY_RESULTS / "predecode-latest.json"
    if predecode.exists():
        shutil.copy2(predecode, SUITE_DATA / "whisper-predecode.json")

    print(f"synced: {SUITE_DATA / 'manifest.json'}")


def sync_metadata() -> None:
    meta_root = SUITE_DATA / "metadata"
    meta_root.mkdir(exist_ok=True, parents=True)
    for name in ("LICENSE.TXT", "BOOKS.TXT", "CHAPTERS.TXT", "SPEAKERS.TXT"):
        src = LEGACY_DATA / "LibriSpeech" / name
        dst = meta_root / name
        if src.exists():
            shutil.copy2(src, dst)
            print(f"copied: {dst}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--skip-metadata",
        action="store_true",
        help="do not copy LibriSpeech metadata text files",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    merge_cases()
    if args.skip_metadata:
        return
    sync_metadata()


if __name__ == "__main__":
    main()
