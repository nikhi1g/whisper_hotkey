#!/usr/bin/env python3
"""Score content-free lexical-invariance metrics for formatter candidates.

Input is JSONL with one object per candidate and these fields:
``before`` and ``after`` are the lexical and formatted strings; ``id`` is an
optional utterance identifier.  The script prints only aggregate metrics and
never echoes either text field.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from collections.abc import Iterable


TOKEN = re.compile(r"[\w]+(?:['’_-][\w]+)*(?:\.[\w]+)*", re.UNICODE)


def lexical_tokens(value: str) -> list[str]:
    normalized = unicodedata.normalize("NFKC", value)
    return [token.lower().replace("’", "'") for token in TOKEN.findall(normalized)]


def score(rows: Iterable[dict[str, object]]) -> dict[str, int | float]:
    total = 0
    invariant = 0
    malformed = 0
    for row in rows:
        total += 1
        before = row.get("before")
        after = row.get("after")
        if not isinstance(before, str) or not isinstance(after, str):
            malformed += 1
            continue
        if lexical_tokens(before) == lexical_tokens(after):
            invariant += 1

    mutation_count = total - invariant - malformed
    return {
        "cases": total,
        "lexically_invariant": invariant,
        "lexical_mutations": mutation_count,
        "malformed_cases": malformed,
        "invariance_rate": (invariant / total) if total else 1.0,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "input",
        help="JSONL candidate file with before/after fields; '-' reads stdin",
    )
    args = parser.parse_args(argv)

    stream = sys.stdin if args.input == "-" else open(args.input, encoding="utf-8")
    try:
        rows = (json.loads(line) for line in stream if line.strip())
        metrics = score(rows)
    finally:
        if stream is not sys.stdin:
            stream.close()

    print(json.dumps(metrics, sort_keys=True))
    return 0 if metrics["lexical_mutations"] == 0 and metrics["malformed_cases"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
