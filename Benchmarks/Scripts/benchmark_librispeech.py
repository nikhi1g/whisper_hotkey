#!/usr/bin/env python3
"""Measure warm-helper latency and WER on deterministic LibriSpeech samples."""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Data" / "LibriSpeech"
RESULTS = ROOT / "Results"
TOKEN = re.compile(r"[a-z0-9]+(?:'[a-z0-9]+)?")


@dataclass(frozen=True)
class Example:
    split: str
    identifier: str
    audio: Path
    reference: str


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
                    previous[column - 1]
                    + (reference_word != hypothesis_word),
                )
            )
        previous = current
    return previous[-1]


def examples(split: str, limit: int) -> list[Example]:
    root = DATA / split
    transcripts: dict[str, str] = {}
    for path in sorted(root.rglob("*.trans.txt")):
        for line in path.read_text(encoding="utf-8").splitlines():
            identifier, reference = line.split(" ", 1)
            transcripts[identifier] = reference
    audio_files = sorted(root.rglob("*.flac"))
    if len(audio_files) < limit:
        raise RuntimeError(f"{split} has only {len(audio_files)} examples")
    if limit == 1:
        selected = [audio_files[0]]
    else:
        selected = [
            audio_files[index * (len(audio_files) - 1) // (limit - 1)]
            for index in range(limit)
        ]
    return [
        Example(
            split=split,
            identifier=path.stem,
            audio=path,
            reference=transcripts[path.stem],
        )
        for path in selected
    ]


class Helper:
    def __init__(
        self,
        executable: Path,
        model: Path,
        profile: str,
        threads: int,
    ) -> None:
        strategy = "beam" if profile == "accuracy" else profile
        self.process = subprocess.Popen(
            [
                str(executable),
                "--model",
                str(model),
                "--threads",
                str(threads),
                "--strategy",
                strategy,
                "--beam-size",
                "5",
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
        event = self._event()
        if event.get("event") != "ready":
            raise RuntimeError(f"helper did not become ready: {event}")

    def _event(self) -> dict:
        assert self.process.stdout is not None
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError(
                f"helper exited with status {self.process.poll()}"
            )
        return json.loads(line)

    def transcribe(self, audio: Path, prompt: str = "") -> dict:
        assert self.process.stdin is not None
        self.process.stdin.write(
            json.dumps(
                {
                    "command": "transcribe",
                    "audioPath": str(audio),
                    "prompt": prompt,
                },
                separators=(",", ":"),
            )
            + "\n"
        )
        self.process.stdin.flush()
        event = self._event()
        if event.get("event") != "result":
            raise RuntimeError(
                f"recognition failed with {event.get('code', 'unknown')}"
            )
        return event

    def close(self) -> None:
        if self.process.stdin:
            self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=5)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = round((len(ordered) - 1) * fraction)
    return ordered[index]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument(
        "--wav-root",
        type=Path,
        required=True,
    )
    parser.add_argument(
        "--profiles",
        nargs="+",
        choices=["accuracy", "greedy", "adaptive"],
        default=["accuracy", "greedy", "adaptive"],
    )
    parser.add_argument("--per-split", type=int, default=50)
    parser.add_argument(
        "--threads",
        type=int,
        default=min(8, max(4, (os.cpu_count() or 4) // 2)),
    )
    args = parser.parse_args()

    corpus = examples("test-clean", args.per_split)
    corpus += examples("test-other", args.per_split)
    RESULTS.mkdir(parents=True, exist_ok=True)
    summary: dict[str, object] = {
        "dataset": "LibriSpeech test-clean and test-other",
        "examples_per_split": args.per_split,
        "threads": args.threads,
        "profiles": {},
    }

    converted: list[tuple[Example, Path]] = []
    for example in corpus:
        wav = args.wav_root / example.split / f"{example.identifier}.wav"
        wav = wav.resolve()
        if not wav.is_file():
            raise SystemExit(f"missing benchmark WAV: {wav}")
        if wav.stat().st_mode & 0o077:
            raise SystemExit(f"benchmark WAV is not private: {wav}")
        converted.append((example, wav))

    helpers = {
        profile: Helper(
            args.helper.resolve(),
            args.model.expanduser().resolve(),
            profile,
            args.threads,
        )
        for profile in args.profiles
    }
    measurements = {
        profile: {
            "latencies": [],
            "fallback_count": 0,
            "average_log_probabilities": [],
            "weak_token_fractions": [],
            "cases": [],
            "split_edits": {"test-clean": 0, "test-other": 0},
            "split_words": {"test-clean": 0, "test-other": 0},
        }
        for profile in args.profiles
    }
    try:
        for index, (example, wav) in enumerate(converted):
            ordered_profiles = list(args.profiles)
            if index % 2:
                ordered_profiles.reverse()
            for profile in ordered_profiles:
                measurement = measurements[profile]
                started = time.perf_counter()
                event = helpers[profile].transcribe(wav)
                latency = time.perf_counter() - started
                measurement["latencies"].append(latency)
                hypothesis = str(event["text"])
                measurement["fallback_count"] += bool(
                    event.get("adaptiveFallback", False)
                )
                measurement["average_log_probabilities"].append(
                    float(event["averageLogProbability"])
                )
                measurement["weak_token_fractions"].append(
                    float(event["weakTokenFraction"])
                )
                reference_words = words(example.reference)
                edits = edit_distance(
                    reference_words,
                    words(hypothesis),
                )
                measurement["split_edits"][example.split] += edits
                measurement["split_words"][example.split] += len(
                    reference_words
                )
                measurement["cases"].append(
                    {
                        "id": example.identifier,
                        "split": example.split,
                        "reference_words": len(reference_words),
                        "word_errors": edits,
                        "average_log_probability": float(
                            event["averageLogProbability"]
                        ),
                        "weak_token_fraction": float(
                            event["weakTokenFraction"]
                        ),
                        "maximum_no_speech_probability": float(
                            event["maximumNoSpeechProbability"]
                        ),
                        "adaptive_fallback": bool(
                            event.get("adaptiveFallback", False)
                        ),
                        "seconds": latency,
                    }
                )
    finally:
        for helper in helpers.values():
            helper.close()

    for profile in args.profiles:
        measurement = measurements[profile]
        latencies = measurement["latencies"]
        split_edits = measurement["split_edits"]
        split_words = measurement["split_words"]
        profile_result = {
            "mean_seconds": statistics.fmean(latencies),
            "p50_seconds": statistics.median(latencies),
            "p95_seconds": percentile(latencies, 0.95),
            "total_seconds": sum(latencies),
            "test_clean_wer": (
                split_edits["test-clean"] / split_words["test-clean"]
            ),
            "test_other_wer": (
                split_edits["test-other"] / split_words["test-other"]
            ),
            "combined_wer": (
                sum(split_edits.values()) / sum(split_words.values())
            ),
            "fallback_fraction": (
                measurement["fallback_count"] / len(converted)
            ),
            "mean_average_log_probability": statistics.fmean(
                measurement["average_log_probabilities"]
            ),
            "mean_weak_token_fraction": statistics.fmean(
                measurement["weak_token_fractions"]
            ),
            "cases": measurement["cases"],
        }
        summary["profiles"][profile] = profile_result
        printable = {
            key: value
            for key, value in profile_result.items()
            if key != "cases"
        }
        print(profile, json.dumps(printable, sort_keys=True))

    destination = RESULTS / "latest.json"
    destination.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(destination)


if __name__ == "__main__":
    main()
