#!/usr/bin/env python3
"""Generate the required primary/confidence/verifier/fusion/formatting report."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from Metrics.edit_distance import edit_counts
    from Metrics.jsonio import load_json_records, write_json
    from Metrics.normalization import NORMALIZATION_VERSION, normalization_sha256, normalize_text
    from Metrics.paired_bootstrap import paired_bootstrap
else:
    from .edit_distance import edit_counts
    from .jsonio import load_json_records, write_json
    from .normalization import NORMALIZATION_VERSION, normalization_sha256, normalize_text
    from .paired_bootstrap import paired_bootstrap


REQUIRED_ABLATIONS = ("primary", "+confidence", "+verifier", "+fusion", "+formatting")
INPUT_ALIASES = {
    "primary": ("primary", "primary_only", "baseline"),
    "+confidence": ("+confidence", "confidence", "with_confidence"),
    "+verifier": ("+verifier", "verifier", "with_verifier"),
    "+fusion": ("+fusion", "fusion", "with_fusion"),
    "+formatting": ("+formatting", "formatting", "with_formatting", "candidate"),
}


def _field(row: Mapping[str, Any], aliases: Sequence[str]) -> str | None:
    for alias in aliases:
        value = row.get(alias)
        if value is not None:
            return str(value)
    return None


def _wer(reference: str, hypothesis: str) -> tuple[int, int]:
    reference_words = normalize_text(reference)
    return edit_counts(reference_words, normalize_text(hypothesis)).errors, len(reference_words)


def _profile_summary(rows: Sequence[Mapping[str, Any]], profile: str, key: str) -> dict[str, Any]:
    errors = words = 0
    for row in rows:
        row_errors, row_words = _wer(str(row["reference"]), str(row[key]))
        errors += row_errors
        words += row_words
    return {
        "profile": profile,
        "utterances": len(rows),
        "errors": errors,
        "referenceWords": words,
        "normalizedWER": errors / words if words else None,
    }


def build_report(rows: Sequence[Mapping[str, Any]], *, samples: int = 10_000, seed: int = 7) -> dict[str, Any]:
    if len(rows) < 2:
        raise ValueError("ablation reporting requires at least two utterances")
    resolved: dict[str, str] = {}
    missing: list[str] = []
    for profile in REQUIRED_ABLATIONS:
        key = next((candidate for candidate in INPUT_ALIASES[profile] if all(candidate in row for row in rows)), None)
        if key is None:
            missing.append(profile)
        else:
            resolved[profile] = key
    if missing:
        raise ValueError(f"missing required ablation profiles: {', '.join(missing)}")
    primary_key = resolved["primary"]
    profiles: dict[str, Any] = {}
    for profile in REQUIRED_ABLATIONS:
        key = resolved[profile]
        summary = _profile_summary(rows, profile, key)
        if profile == "primary":
            summary["deltaWERvsPrimary"] = 0.0
            summary["regressionCount"] = 0
            summary["improvementCount"] = 0
            summary["pairedBootstrap"] = None
        else:
            paired_rows = [
                {
                    "id": row["id"],
                    "subset": row.get("subset", "unspecified"),
                    "reference": row["reference"],
                    "baseline": row[primary_key],
                    "candidate": row[key],
                }
                for row in rows
            ]
            bootstrap = paired_bootstrap(paired_rows, samples=samples, seed=seed)
            summary["deltaWERvsPrimary"] = bootstrap["deltaCandidateMinusBaseline"]
            summary["regressionCount"] = bootstrap["regressionCount"]
            summary["improvementCount"] = bootstrap["improvementCount"]
            summary["pairedBootstrap"] = bootstrap
        profiles[profile] = summary
    return {
        "schemaVersion": 1,
        "normalization": {
            "version": NORMALIZATION_VERSION,
            "sha256": normalization_sha256(),
        },
        "requiredAblations": list(REQUIRED_ABLATIONS),
        "missingAblations": missing,
        "profiles": profiles,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="report frozen benchmark ablations")
    parser.add_argument("input", help="JSONL/JSON rows with all five hypothesis profiles")
    parser.add_argument("--samples", type=int, default=10_000)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--output")
    args = parser.parse_args()
    result = build_report(load_json_records(args.input), samples=args.samples, seed=args.seed)
    write_json(result, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
