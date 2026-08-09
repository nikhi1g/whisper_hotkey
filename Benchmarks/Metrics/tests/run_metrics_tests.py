#!/usr/bin/env python3
"""Run the focused dependency-free benchmark tests."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


TESTS = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS.parents[1]))


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.discover(str(TESTS), pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
