#!/usr/bin/env python3
"""Paired utterance-level bootstrap confidence intervals for WER.

Input records contain ``id``, ``reference``, ``baseline`` and ``candidate``
text.  Text is read only for the duration of scoring; the emitted artifact is
numeric and contains no transcript text.
"""

from __future__ import annotations

import argparse
import math
import random
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Mapping, Sequence

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from Metrics.edit_distance import edit_counts
    from Metrics.jsonio import load_json_records, write_json
    from Metrics.normalization import NORMALIZATION_VERSION, normalization_sha256, normalize_text
else:
    from .edit_distance import edit_counts
    from .jsonio import load_json_records, write_json
    from .normalization import NORMALIZATION_VERSION, normalization_sha256, normalize_text


def _wer_counts(reference: str, hypothesis: str) -> tuple[int, int]:
    reference_words = normalize_text(reference)
    hypothesis_words = normalize_text(hypothesis)
    return edit_counts(reference_words, hypothesis_words).errors, len(reference_words)


def _aggregate(rows: Sequence[Mapping[str, Any]], indices: Sequence[int], key: str) -> float | None:
    errors = words = 0
    for index in indices:
        row = rows[index]
        row_errors, row_words = _wer_counts(str(row["reference"]), str(row.get(key, "")))
        errors += row_errors
        words += row_words
    return errors / words if words else None


def _quantile(values: Sequence[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        raise ValueError("cannot calculate a quantile from an empty sample")
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def paired_bootstrap(
    rows: Sequence[Mapping[str, Any]],
    *,
    baseline_key: str = "baseline",
    candidate_key: str = "candidate",
    samples: int = 10_000,
    seed: int = 7,
    confidence: float = 0.95,
) -> dict[str, Any]:
    """Return an utterance-paired percentile CI for candidate minus baseline."""

    if len(rows) < 2:
        raise ValueError("paired bootstrap requires at least two utterances")
    if samples < 100:
        raise ValueError("paired bootstrap requires at least 100 samples")
    if not 0 < confidence < 1:
        raise ValueError("confidence must be between zero and one")
    required = {"id", "reference", baseline_key, candidate_key}
    for row in rows:
        absent = [key for key in required if key not in row]
        if absent:
            raise ValueError(f"row is missing required fields: {sorted(absent)}")
    all_indices = list(range(len(rows)))
    baseline_wer = _aggregate(rows, all_indices, baseline_key)
    candidate_wer = _aggregate(rows, all_indices, candidate_key)
    if baseline_wer is None or candidate_wer is None:
        raise ValueError("paired bootstrap requires at least one reference word")
    delta = candidate_wer - baseline_wer
    rng = random.Random(seed)
    deltas: list[float] = []
    for _ in range(samples):
        indices = [rng.randrange(len(rows)) for _ in rows]
        sampled_baseline = _aggregate(rows, indices, baseline_key)
        sampled_candidate = _aggregate(rows, indices, candidate_key)
        if sampled_baseline is not None and sampled_candidate is not None:
            deltas.append(sampled_candidate - sampled_baseline)
    alpha = (1.0 - confidence) / 2.0
    lower = _quantile(deltas, alpha)
    upper = _quantile(deltas, 1.0 - alpha)
    improvements = regressions = ties = 0
    by_subset: dict[str, dict[str, int]] = defaultdict(lambda: {"utterances": 0, "improvements": 0, "regressions": 0, "ties": 0})
    for row in rows:
        baseline_errors, _ = _wer_counts(str(row["reference"]), str(row[baseline_key]))
        candidate_errors, _ = _wer_counts(str(row["reference"]), str(row[candidate_key]))
        if candidate_errors < baseline_errors:
            improvements += 1
        elif candidate_errors > baseline_errors:
            regressions += 1
        else:
            ties += 1
        subset = str(row.get("subset", "unspecified"))
        bucket = by_subset[subset]
        bucket["utterances"] += 1
        if candidate_errors < baseline_errors:
            bucket["improvements"] += 1
        elif candidate_errors > baseline_errors:
            bucket["regressions"] += 1
        else:
            bucket["ties"] += 1
    relative = (baseline_wer - candidate_wer) / baseline_wer if baseline_wer else None
    return {
        "schemaVersion": 1,
        "normalization": {
            "version": NORMALIZATION_VERSION,
            "sha256": normalization_sha256(),
        },
        "n": len(rows),
        "baselineWER": baseline_wer,
        "candidateWER": candidate_wer,
        "deltaCandidateMinusBaseline": delta,
        # Compatibility name retained for simple consumers of the packet's
        # paired_bootstrap.py reference implementation.
        "delta_candidate_minus_baseline": delta,
        "absoluteImprovement": baseline_wer - candidate_wer,
        "relativeImprovement": relative,
        "confidenceLevel": confidence,
        "ci": {
            "lower": lower,
            "upper": upper,
        },
        "ci95": [lower, upper] if abs(confidence - 0.95) < 1e-12 else None,
        "bootstrapSamples": len(deltas),
        "seed": seed,
        "improvementCount": improvements,
        "regressionCount": regressions,
        "tieCount": ties,
        "bySubset": dict(sorted(by_subset.items())),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="paired utterance-level WER bootstrap")
    parser.add_argument("input", help="JSONL/JSON rows with reference/baseline/candidate")
    parser.add_argument("--samples", type=int, default=10_000)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--confidence", type=float, default=0.95)
    parser.add_argument("--baseline-key", default="baseline")
    parser.add_argument("--candidate-key", default="candidate")
    parser.add_argument("--output")
    args = parser.parse_args()
    rows = load_json_records(args.input)
    result = paired_bootstrap(
        rows,
        baseline_key=args.baseline_key,
        candidate_key=args.candidate_key,
        samples=args.samples,
        seed=args.seed,
        confidence=args.confidence,
    )
    write_json(result, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
