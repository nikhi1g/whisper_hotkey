#!/usr/bin/env python3
"""Compare full-recording and pipelined release latency on LibriSpeech WAVs."""

from __future__ import annotations

import argparse
import array
import json
import math
import os
import statistics
import tempfile
import time
import wave
from pathlib import Path

from benchmark_librispeech import (
    RESULTS,
    Helper,
    edit_distance,
    examples,
    percentile,
    words,
)


MINIMUM_SEGMENT_SECONDS = 5.0
BOUNDARY_SILENCE_SECONDS = 0.3
MAXIMUM_SEGMENT_SECONDS = 8.0
WINDOW_SECONDS = 0.02
SPEECH_THRESHOLD_DBFS = -48.0


def decibels(samples: array.array[int]) -> float:
    if not samples:
        return -120.0
    square_mean = sum(sample * sample for sample in samples) / len(samples)
    if square_mean <= 0:
        return -120.0
    return 20 * math.log10(math.sqrt(square_mean) / 32_768)


def contains_confirmed_speech(path: Path) -> bool:
    with wave.open(str(path), "rb") as source:
        rate = source.getframerate()
        samples = array.array("h")
        samples.frombytes(source.readframes(source.getnframes()))
    window = round(rate * WINDOW_SECONDS)
    required = round(rate * 0.1)
    contiguous = 0
    for offset in range(0, len(samples), window):
        frame = samples[offset : offset + window]
        if decibels(frame) > SPEECH_THRESHOLD_DBFS:
            contiguous += len(frame)
            if contiguous >= required:
                return True
        else:
            contiguous = 0
    return False


def chunk_ranges(path: Path) -> tuple[int, list[tuple[int, int]]]:
    with wave.open(str(path), "rb") as source:
        if (
            source.getnchannels() != 1
            or source.getsampwidth() != 2
            or source.getframerate() != 16_000
        ):
            raise RuntimeError(f"unsupported benchmark WAV: {path}")
        rate = source.getframerate()
        samples = array.array("h")
        samples.frombytes(source.readframes(source.getnframes()))

    window = round(rate * WINDOW_SECONDS)
    minimum = round(rate * MINIMUM_SEGMENT_SECONDS)
    boundary_silence = round(rate * BOUNDARY_SILENCE_SECONDS)
    maximum = round(rate * MAXIMUM_SEGMENT_SECONDS)
    ranges: list[tuple[int, int]] = []
    start = 0
    trailing_silence = 0
    contains_speech = False

    for offset in range(0, len(samples), window):
        end = min(offset + window, len(samples))
        is_speech = decibels(samples[offset:end]) > SPEECH_THRESHOLD_DBFS
        contains_speech = contains_speech or is_speech
        trailing_silence = 0 if is_speech else trailing_silence + end - offset
        duration = end - start
        should_rotate = (
            contains_speech
            and duration >= minimum
            and (
                trailing_silence >= boundary_silence
                or duration >= maximum
            )
        )
        if should_rotate and end < len(samples):
            ranges.append((start, end))
            start = end
            trailing_silence = 0
            contains_speech = False
    ranges.append((start, len(samples)))
    return rate, ranges


def write_chunks(
    source_path: Path,
    destination: Path,
    ranges: list[tuple[int, int]],
) -> list[Path]:
    with wave.open(str(source_path), "rb") as source:
        parameters = source.getparams()
        frames = source.readframes(source.getnframes())
    samples = array.array("h")
    samples.frombytes(frames)

    paths: list[Path] = []
    for index, (start, end) in enumerate(ranges):
        path = destination / f"{index:03d}.wav"
        with wave.open(str(path), "wb") as output:
            output.setparams(parameters)
            output.writeframes(samples[start:end].tobytes())
        path.chmod(0o600)
        paths.append(path)
    return paths


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--wav-root", type=Path, required=True)
    parser.add_argument("--per-split", type=int, default=50)
    parser.add_argument("--maximum-examples", type=int)
    parser.add_argument(
        "--strategy",
        choices=["accuracy", "adaptive"],
        default="accuracy",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=min(8, max(4, (os.cpu_count() or 4) // 2)),
    )
    args = parser.parse_args()

    corpus = examples("test-clean", args.per_split)
    corpus += examples("test-other", args.per_split)
    if args.maximum_examples is not None:
        corpus = corpus[: args.maximum_examples]
    helper = Helper(
        args.helper.resolve(),
        args.model.expanduser().resolve(),
        args.strategy,
        args.threads,
    )
    full_latencies: list[float] = []
    release_latencies: list[float] = []
    full_edits = 0
    chunked_edits = 0
    reference_word_count = 0
    chunk_counts: list[int] = []
    cases: list[dict[str, object]] = []

    try:
        for example in corpus:
            wav = (
                args.wav_root
                / example.split
                / f"{example.identifier}.wav"
            ).resolve()
            if not wav.is_file() or wav.stat().st_mode & 0o077:
                raise RuntimeError(f"missing or non-private WAV: {wav}")

            started = time.perf_counter()
            full_event = helper.transcribe(wav)
            full_latency = time.perf_counter() - started

            rate, ranges = chunk_ranges(wav)
            with tempfile.TemporaryDirectory(
                prefix="whisper_hotkey-predecode-"
            ) as temporary:
                directory = Path(temporary)
                directory.chmod(0o700)
                chunk_paths = write_chunks(wav, directory, ranges)
                backend_available_at = 0.0
                hypotheses: list[str] = []
                for path, (_, end) in zip(chunk_paths, ranges):
                    available_at = end / rate
                    if not contains_confirmed_speech(path):
                        text = ""
                        decode_seconds = 0.0
                    else:
                        started = time.perf_counter()
                        try:
                            event = helper.transcribe(path)
                            text = str(event["text"]).strip()
                        except RuntimeError as error:
                            if "no_speech" not in str(error):
                                raise
                            text = ""
                        decode_seconds = time.perf_counter() - started
                    backend_available_at = (
                        max(available_at, backend_available_at)
                        + decode_seconds
                    )
                    if text:
                        hypotheses.append(text)

            duration = ranges[-1][1] / rate
            release_latency = max(0.0, backend_available_at - duration)
            reference = words(example.reference)
            full_hypothesis = words(str(full_event["text"]))
            chunked_hypothesis = words(" ".join(hypotheses))
            reference_word_count += len(reference)
            full_case_edits = edit_distance(reference, full_hypothesis)
            chunked_case_edits = edit_distance(reference, chunked_hypothesis)
            full_edits += full_case_edits
            chunked_edits += chunked_case_edits
            full_latencies.append(full_latency)
            release_latencies.append(release_latency)
            chunk_counts.append(len(ranges))
            cases.append(
                {
                    "id": example.identifier,
                    "split": example.split,
                    "audio_seconds": duration,
                    "chunks": len(ranges),
                    "full_word_errors": full_case_edits,
                    "predecode_word_errors": chunked_case_edits,
                    "full_release_seconds": full_latency,
                    "predecode_release_seconds": release_latency,
                }
            )
    finally:
        helper.close()

    result = {
        "dataset": "LibriSpeech test-clean and test-other",
        "examples_per_split": args.per_split,
        "strategy": args.strategy,
        "threads": args.threads,
        "full_wer": full_edits / reference_word_count,
        "predecode_wer": chunked_edits / reference_word_count,
        "full_mean_release_seconds": statistics.fmean(full_latencies),
        "predecode_mean_release_seconds": statistics.fmean(release_latencies),
        "full_p50_release_seconds": statistics.median(full_latencies),
        "predecode_p50_release_seconds": statistics.median(release_latencies),
        "full_p95_release_seconds": percentile(full_latencies, 0.95),
        "predecode_p95_release_seconds": percentile(
            release_latencies,
            0.95,
        ),
        "mean_chunks": statistics.fmean(chunk_counts),
        "cases": cases,
    }
    RESULTS.mkdir(parents=True, exist_ok=True)
    destination = RESULTS / "predecode-latest.json"
    destination.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {key: value for key, value in result.items() if key != "cases"},
            indent=2,
            sort_keys=True,
        )
    )
    print(destination)


if __name__ == "__main__":
    main()
