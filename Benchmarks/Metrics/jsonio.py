#!/usr/bin/env python3
"""Small JSON/JSONL reader used by benchmark command-line tools."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def load_json_records(path: str | Path) -> list[dict[str, Any]]:
    """Load JSONL or a JSON array/object containing ``rows``/``items``."""

    if str(path) == "-":
        text = sys.stdin.read()
    else:
        text = Path(path).read_text(encoding="utf-8")
    if not text.strip():
        raise ValueError("benchmark input is empty")
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        records = [json.loads(line) for line in text.splitlines() if line.strip()]
    else:
        if isinstance(value, list):
            records = value
        elif isinstance(value, dict):
            if "rows" in value or "items" in value:
                records = value.get("rows", value.get("items", []))
            else:
                records = [value]
        else:
            records = []
    if not isinstance(records, list) or not records:
        raise ValueError("benchmark input must contain one or more records")
    if not all(isinstance(record, dict) for record in records):
        raise ValueError("every benchmark record must be a JSON object")
    return records


def write_json(value: Any, path: str | Path | None) -> None:
    payload = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if path is None or str(path) == "-":
        print(payload, end="")
    else:
        destination = Path(path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(payload, encoding="utf-8")
