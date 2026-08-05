#!/usr/bin/env python3
"""Score a parakeet-benchmark JSONL run with the same WER math as
`benchmark_librispeech.py`, so Parakeet and whisper numbers are comparable."""
from __future__ import annotations

import json
import re
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Data" / "LibriSpeech"
WAV = ROOT / "Data" / "WAV"
TOKEN = re.compile(r"[a-z0-9]+(?:'[a-z0-9]+)?")


def words(text: str) -> list[str]:
    return TOKEN.findall(text.casefold())


def edit_distance(reference: list[str], hypothesis: list[str]) -> int:
    previous = list(range(len(hypothesis) + 1))
    for row, reference_word in enumerate(reference, 1):
        current = [row]
        for column, hypothesis_word in enumerate(hypothesis, 1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[column] + 1,
                    previous[column - 1] + (reference_word != hypothesis_word),
                )
            )
        previous = current
    return previous[-1]


def references() -> dict[str, str]:
    table: dict[str, str] = {}
    for path in DATA.rglob("*.trans.txt"):
        for line in path.read_text(encoding="utf-8").splitlines():
            identifier, text = line.split(" ", 1)
            table[identifier] = text
    return table


def durations() -> dict[str, float]:
    table: dict[str, float] = {}
    for path in WAV.rglob("*.wav"):
        with wave.open(str(path)) as handle:
            table[path.stem] = handle.getnframes() / handle.getframerate()
    return table


def split_of(identifier: str) -> str:
    for candidate in ("test-clean", "test-other"):
        if (WAV / candidate / f"{identifier}.wav").is_file():
            return candidate
    raise KeyError(identifier)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)]


def main() -> None:
    reference_table = references()
    duration_table = durations()
    # CoreML's E5RT layer occasionally writes diagnostics to stdout; skip
    # anything that is not one of our JSON records.
    rows = [
        json.loads(line)
        for line in Path(sys.argv[1]).read_text().splitlines()
        if line.startswith("{")
    ]

    edits = {"test-clean": 0, "test-other": 0}
    counts = {"test-clean": 0, "test-other": 0}
    latencies: list[float] = []
    audio = 0.0

    for row in rows:
        identifier = row["id"]
        split = split_of(identifier)
        reference_words = words(reference_table[identifier])
        edits[split] += edit_distance(reference_words, words(row["text"]))
        counts[split] += len(reference_words)
        latencies.append(row["seconds"])
        audio += duration_table[identifier]

    total_edits = sum(edits.values())
    total_words = sum(counts.values())
    total_time = sum(latencies)

    print(f"utterances      {len(rows)}")
    print(f"audio           {audio:.1f}s")
    print(f"wall time       {total_time:.2f}s")
    print(f"speed           {audio / total_time:.1f}x realtime (RTF {total_time / audio:.4f})")
    print(f"mean latency    {total_time / len(rows) * 1000:.1f} ms")
    print(f"p50 latency     {percentile(latencies, 0.50) * 1000:.1f} ms")
    print(f"p95 latency     {percentile(latencies, 0.95) * 1000:.1f} ms")
    print(f"WER combined    {100 * total_edits / total_words:.2f}%")
    print(f"WER test-clean  {100 * edits['test-clean'] / counts['test-clean']:.2f}%")
    print(f"WER test-other  {100 * edits['test-other'] / counts['test-other']:.2f}%")


if __name__ == "__main__":
    main()
