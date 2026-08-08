#!/usr/bin/env python3
"""Measure whether combining Parakeet variants can beat the shipping default.

Answers three questions before any coordinator work is written:

1. What is the *oracle* ceiling -- the WER of an arbiter that always picks the
   better hypothesis? Nothing built on these candidates can beat it.
2. Does utterance-level consensus (pick the most central hypothesis) help?
3. Does word-level ROVER voting help?

Usage:

    python3 Benchmarks/Scripts/ensemble_ceiling.py \\
        --unified /tmp/unified.jsonl \\
        --balanced /tmp/v2.jsonl \\
        --fast /tmp/fast.jsonl

Each input is the JSONL emitted by `parakeet-benchmark`.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from score_parakeet import edit_distance, references, words


def load(path: Path) -> dict[str, str]:
    rows: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        row = json.loads(line)
        rows[row["id"]] = row["text"]
    return rows


def align(pivot: list[str], other: list[str]) -> list[str | None]:
    """Align `other` onto `pivot`.

    Returns one slot per pivot word holding the word `other` aligned there, or
    None where `other` has no word for that position. Insertions in `other`
    are dropped: ROVER needs a fixed set of voting slots, and the pivot defines
    them.
    """
    rows, columns = len(pivot), len(other)
    distance = [[0] * (columns + 1) for _ in range(rows + 1)]
    for row in range(rows + 1):
        distance[row][0] = row
    for column in range(columns + 1):
        distance[0][column] = column
    for row in range(1, rows + 1):
        for column in range(1, columns + 1):
            distance[row][column] = min(
                distance[row - 1][column] + 1,
                distance[row][column - 1] + 1,
                distance[row - 1][column - 1]
                + (pivot[row - 1] != other[column - 1]),
            )

    aligned: list[str | None] = [None] * rows
    row, column = rows, columns
    while row > 0 and column > 0:
        substitution = distance[row - 1][column - 1] + (
            pivot[row - 1] != other[column - 1]
        )
        if distance[row][column] == substitution:
            aligned[row - 1] = other[column - 1]
            row -= 1
            column -= 1
        elif distance[row][column] == distance[row - 1][column] + 1:
            row -= 1
        else:
            column -= 1
    return aligned


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--unified", type=Path, required=True)
    parser.add_argument("--balanced", type=Path, required=True)
    parser.add_argument("--fast", type=Path, required=True)
    args = parser.parse_args()

    reference_table = references()
    unified = load(args.unified)
    balanced = load(args.balanced)
    fast = load(args.fast)

    total = 0
    errors = {
        "unified": 0,
        "balanced": 0,
        "fast": 0,
        "oracle_2": 0,
        "oracle_3": 0,
        "consensus": 0,
        "rover": 0,
    }
    rescuable = 0

    for identifier, text in unified.items():
        reference = words(reference_table[identifier])
        total += len(reference)
        candidates = {
            "unified": words(text),
            "balanced": words(balanced[identifier]),
            "fast": words(fast[identifier]),
        }
        case = {
            name: edit_distance(reference, hypothesis)
            for name, hypothesis in candidates.items()
        }
        for name in ("unified", "balanced", "fast"):
            errors[name] += case[name]
        errors["oracle_2"] += min(case["unified"], case["balanced"])
        errors["oracle_3"] += min(case.values())
        if case["balanced"] < case["unified"]:
            rescuable += 1

        # Utterance-level consensus, ties broken toward the shipping default.
        def centrality(name: str) -> tuple[int, int]:
            spread = sum(
                edit_distance(candidates[name], candidates[other])
                for other in candidates
                if other != name
            )
            return (spread, 0 if name == "unified" else 1)

        errors["consensus"] += case[min(candidates, key=centrality)]

        # Word-level ROVER over the Unified pivot, ties broken toward Unified.
        pivot = candidates["unified"]
        others = [
            align(pivot, candidates["balanced"]),
            align(pivot, candidates["fast"]),
        ]
        voted: list[str] = []
        for index, word in enumerate(pivot):
            ballots = [word] + [
                other[index] for other in others if other[index] is not None
            ]
            tally = Counter(ballots).most_common()
            leading = tally[0][1]
            keeps_pivot = any(
                candidate == word and count == leading
                for candidate, count in tally
            )
            voted.append(word if keeps_pivot else tally[0][0])
        errors["rover"] += edit_distance(reference, voted)

    def show(label: str, key: str) -> None:
        print(f"{label:<34}{errors[key] / total:>8.4%}  ({errors[key]} errors)")

    print(f"{'reference words':<34}{total:>8}")
    print()
    show("Unified (shipping default)", "unified")
    show("Balanced", "balanced")
    show("Fast", "fast")
    print()
    show("ORACLE min(Unified, Balanced)", "oracle_2")
    show("ORACLE min(all three)", "oracle_3")
    print()
    show("utterance consensus", "consensus")
    show("word-level ROVER", "rover")
    print()
    print(f"utterances Balanced beats Unified: {rescuable}")


if __name__ == "__main__":
    main()
