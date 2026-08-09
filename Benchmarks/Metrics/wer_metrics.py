#!/usr/bin/env python3
"""Compatibility CLI for frozen normalized/display WER and CER metrics."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from Metrics.edit_distance import edit_counts
    from Metrics.normalization import normalize_text, normalized_characters
    from Metrics.scoring import punctuation_metrics, score_pair
else:
    from .edit_distance import edit_counts
    from .normalization import normalize_text, normalized_characters
    from .scoring import punctuation_metrics, score_pair


def rate(reference: str, hypothesis: str, *, character: bool = False) -> dict[str, Any]:
    reference_units = normalized_characters(reference) if character else normalize_text(reference)
    hypothesis_units = normalized_characters(hypothesis) if character else normalize_text(hypothesis)
    counts = edit_counts(reference_units, hypothesis_units)
    units = len(reference_units)
    return {
        "reference_units": units,
        "substitutions": counts.substitutions,
        "deletions": counts.deletions,
        "insertions": counts.insertions,
        "errors": counts.errors,
        "rate": counts.errors / units if units else (0.0 if not hypothesis_units else None),
    }


def punctuation_f1(reference: str, hypothesis: str) -> dict[str, Any]:
    result = punctuation_metrics(reference, hypothesis)
    return {"comparable": normalize_text(reference) == normalize_text(hypothesis), "macro_f1": result["macroF1"]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference")
    parser.add_argument("hypothesis")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    pair = score_pair(args.reference, args.hypothesis)
    result = {
        "normalization": pair["normalized"],
        "display": pair["display"],
        "cer": pair["cer"],
        "punctuation": pair["punctuation"],
    }
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(
            f"WER={float(result['normalization']['rate'] or 0):.6f} "
            f"CER={float(result['cer']['rate'] or 0):.6f} "
            f"PUNC_F1={result['punctuation']['macroF1']:.6f}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
