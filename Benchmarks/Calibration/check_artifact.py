#!/usr/bin/env python3
"""Check that the tracked synthetic calibration artifact is reproducible."""

from __future__ import annotations

import json
from pathlib import Path
import sys

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from calibrate import build_artifact, load_rows
else:
    from .calibrate import build_artifact, load_rows


ROOT = Path(__file__).resolve().parent


def main() -> int:
    expected_path = ROOT / "expected_artifact.json"
    actual = build_artifact(load_rows(ROOT / "synthetic_labeled.jsonl"))
    expected = json.loads(expected_path.read_text(encoding="utf-8"))
    if actual != expected:
        raise SystemExit("calibration artifact is not deterministic")
    for group in actual["groups"]:
        if group["operatingPoint"]["status"] != "uncalibrated":
            raise SystemExit("fixture must not promote an unsupported threshold")
        if group["operatingPoint"]["errorThreshold"] is not None:
            raise SystemExit("fixture contains an unexplained threshold")
    print("confidence calibration artifact: deterministic")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
