#!/usr/bin/env python3
"""Run BenchmarkSuite asset checks with unittest."""

from __future__ import annotations

import unittest
import importlib.util
from pathlib import Path


def _load_tests() -> unittest.TestSuite:
    tests_path = Path(__file__).resolve()
    spec = importlib.util.spec_from_file_location(
        "test_suite_assets",
        str(tests_path.parent / "test_suite_assets.py"),
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load tests")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return unittest.defaultTestLoader.loadTestsFromModule(module)


def main() -> None:
    suite = _load_tests()
    result = unittest.TextTestRunner().run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    main()
