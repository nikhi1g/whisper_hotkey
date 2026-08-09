#!/usr/bin/env python3
"""Run privacy-safe benchmark scoring from the established scripts folder."""

from __future__ import annotations

import runpy
from pathlib import Path


if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).resolve().parents[1] / "Metrics" / "score_benchmark.py"), run_name="__main__")
