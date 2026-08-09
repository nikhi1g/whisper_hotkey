#!/usr/bin/env python3
"""Score an ephemeral JSONL benchmark run into the v1 result schema."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from Metrics.jsonio import load_json_records, write_json
    from Metrics.normalization import NORMALIZATION_VERSION, normalization_sha256
    from Metrics.scoring import score_rows
else:
    from .jsonio import load_json_records, write_json
    from .normalization import NORMALIZATION_VERSION, normalization_sha256
    from .scoring import score_rows


def _object(value: str | None) -> dict[str, Any]:
    if not value:
        return {}
    loaded = json.loads(value)
    if not isinstance(loaded, dict):
        raise ValueError("metadata arguments must be JSON objects")
    return loaded


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Score benchmark JSONL without writing audio, references, or "
            "hypotheses to the result artifact."
        )
    )
    parser.add_argument("input", help="JSONL/JSON input path, or - for stdin")
    parser.add_argument("--run-id", default="benchmark-run")
    parser.add_argument("--commit", default="unknown")
    parser.add_argument("--hardware-json", help="hardware object encoded as JSON")
    parser.add_argument("--configuration-json", help="configuration object encoded as JSON")
    parser.add_argument("--output", help="output JSON path; defaults to stdout")
    args = parser.parse_args()
    rows = load_json_records(args.input)
    result = score_rows(
        rows,
        run_id=args.run_id,
        commit=args.commit,
        hardware=_object(args.hardware_json),
        configuration=_object(args.configuration_json),
    )
    result["normalization"] = {
        "version": NORMALIZATION_VERSION,
        "sha256": normalization_sha256(),
    }
    write_json(result, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
