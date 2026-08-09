#!/usr/bin/env python3
"""Bounded helper restart/cancel soak checks with content-free results.

This harness exercises only owned helper processes.  It deliberately does not
pretend to test the app coordinator: cancellation is measured as process
termination, and stale-result suppression remains an application test.  Input
audio is read from a private existing corpus and is never copied or emitted.
"""

from __future__ import annotations

import argparse
import json
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Sequence

from profile_performance import (
    MAX_HELPER_TIMEOUT_SECONDS,
    MAX_MEASUREMENTS,
    PerformanceError,
    RSSSampler,
    WhisperHelper,
    _new_report,
    _storage,
    assert_content_free,
    engine_preflight,
    load_audio_cases,
    placement_comparison,
    summary,
)


MAX_ITERATIONS = 100
MAX_SOAK_SECONDS = 15 * 60.0


def run_soak(
    *,
    helper_path: Path,
    model_path: Path,
    cases: Sequence[Any],
    iterations: int,
    cancel_every: int,
    cancel_after_seconds: float,
    threads: int,
    strategy: str,
    timeout_seconds: float,
    maximum_wall_seconds: float = MAX_SOAK_SECONDS,
) -> dict[str, Any]:
    """Run bounded normal/cancel iterations and verify process reaping."""

    iterations = max(1, min(MAX_ITERATIONS, int(iterations)))
    cancel_every = max(0, min(iterations, int(cancel_every)))
    if iterations > MAX_MEASUREMENTS:
        raise PerformanceError("soak iteration bound exceeded")
    if not cases:
        raise PerformanceError("soak corpus selection is empty")
    cancel_after_seconds = max(0.01, min(10.0, float(cancel_after_seconds)))
    timeout_seconds = max(0.1, min(MAX_HELPER_TIMEOUT_SECONDS, float(timeout_seconds)))

    latencies: list[float] = []
    cancellation_latencies: list[float] = []
    completed = 0
    cancelled = 0
    failed = 0
    leaked_processes = 0
    peak_rss: int | None = None
    started_all = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="whisper-hotkey-soak-") as temporary:
        temporary_root = Path(temporary)
        temporary_root.chmod(0o700)
        maximum_temp_bytes = 0
        maximum_temp_files = 0
        for index in range(iterations):
            if time.monotonic() - started_all > maximum_wall_seconds:
                raise PerformanceError("soak wall-time bound exceeded")
            case = cases[index % len(cases)]
            helper = WhisperHelper(helper_path, model_path, threads, strategy)
            sampler: RSSSampler | None = None
            try:
                helper.start(timeout_seconds)
                sampler = RSSSampler(helper.pid)
                sampler.start()
                should_cancel = cancel_every > 0 and (index + 1) % cancel_every == 0
                if should_cancel:
                    operation_error: list[BaseException] = []

                    def transcribe() -> None:
                        try:
                            helper.transcribe(case.path, timeout_seconds)
                        except BaseException as error:  # process cancellation is expected
                            operation_error.append(error)

                    worker = threading.Thread(target=transcribe, daemon=True)
                    started = time.perf_counter()
                    worker.start()
                    time.sleep(cancel_after_seconds)
                    if not helper.cancel():
                        raise PerformanceError("cancelled helper was not reaped")
                    worker.join(timeout=2.0)
                    if worker.is_alive():
                        raise PerformanceError("cancelled helper reader did not stop")
                    cancellation_latencies.append(time.perf_counter() - started)
                    cancelled += 1
                    del operation_error
                else:
                    started = time.perf_counter()
                    helper.transcribe(case.path, timeout_seconds)
                    elapsed = time.perf_counter() - started
                    latencies.append(elapsed)
                    completed += 1
                if sampler.peak is not None:
                    peak_rss = sampler.peak if peak_rss is None else max(peak_rss, sampler.peak)
                temp_bytes, temp_files = _storage(temporary_root)
                maximum_temp_bytes = max(maximum_temp_bytes, temp_bytes)
                maximum_temp_files = max(maximum_temp_files, temp_files)
            except (PerformanceError, TimeoutError, OSError):
                failed += 1
                raise
            finally:
                if sampler is not None:
                    sampler.stop()
                if helper.process is not None and not helper.cancel():
                    leaked_processes += 1

    if completed == 0 and cancelled == 0:
        raise PerformanceError("soak produced no completed or cancelled iterations")
    result: dict[str, Any] = {
        "name": "whisper_cpp_restart_cancel_soak",
        "status": "measured",
        "engine": "whisper.cpp",
        "iterations": iterations,
        "cancel_every": cancel_every,
        "completed_iterations": completed,
        "cancelled_iterations": cancelled,
        "failed_iterations": failed,
        "leaked_owned_processes": leaked_processes,
        "peak_rss_bytes": peak_rss,
        "normal_latency_seconds": summary(latencies) if latencies else None,
        "cancel_latency_seconds": summary(cancellation_latencies) if cancellation_latencies else None,
        "temporary_storage": {
            "max_bytes": maximum_temp_bytes,
            "max_files": maximum_temp_files,
            "scope": "soak-owned empty directory; input WAVs are never copied",
        },
        "invariants": {
            "owned_processes_reaped": leaked_processes == 0,
            "cancel_suppresses_paste": "not observable in helper-only harness; app coordinator test required",
            "stale_result_suppression": "not observable in helper-only harness; generation test required",
        },
    }
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper", type=Path)
    parser.add_argument("--model", type=Path)
    parser.add_argument("--wav-root", type=Path)
    parser.add_argument("--parakeet-runner", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--iterations", type=int, default=10)
    parser.add_argument("--cancel-every", type=int, default=3)
    parser.add_argument("--cancel-after-ms", type=float, default=100.0)
    parser.add_argument("--max-cases", type=int, default=1)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--strategy", choices=("beam", "greedy", "adaptive"), default="beam")
    parser.add_argument("--timeout-seconds", type=float, default=30.0)
    parser.add_argument("--compare", action="store_true")
    parser.add_argument("--preflight", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    report = _new_report()
    preflight = engine_preflight(
        whisper_helper=args.helper,
        whisper_model=args.model,
        parakeet_runner=args.parakeet_runner,
        wav_root=args.wav_root,
    )
    report["preflight"] = preflight
    report["comparisons"].append(placement_comparison(preflight))
    requested_run = args.helper is not None or args.model is not None or args.wav_root is not None
    exit_code = 0
    if requested_run:
        if preflight["whisper_cpp"]["status"] != "ready":
            report["profiles"].append(
                {
                    "name": "whisper_cpp_restart_cancel_soak",
                    "status": "unavailable",
                    "blockers": preflight["whisper_cpp"]["blockers"],
                    "metrics": None,
                }
            )
            exit_code = 2
        else:
            try:
                cases = load_audio_cases(args.wav_root, maximum_cases=args.max_cases)
                report["run"]["kind"] = "soak_cancel"
                report["profiles"].append(
                    run_soak(
                        helper_path=args.helper,
                        model_path=args.model,
                        cases=cases,
                        iterations=args.iterations,
                        cancel_every=args.cancel_every,
                        cancel_after_seconds=args.cancel_after_ms / 1000.0,
                        threads=args.threads,
                        strategy=args.strategy,
                        timeout_seconds=args.timeout_seconds,
                    )
                )
            except (PerformanceError, OSError, ValueError) as error:
                report["profiles"].append(
                    {
                        "name": "whisper_cpp_restart_cancel_soak",
                        "status": "unavailable",
                        "blockers": [str(error)],
                        "metrics": None,
                    }
                )
                exit_code = 2
    else:
        report["run"]["kind"] = "preflight"
    if args.compare and report["comparisons"][0]["status"] != "eligible":
        exit_code = 2
    assert_content_free(report)
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output is None:
        print(rendered, end="")
    else:
        destination = args.output.expanduser().resolve()
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(rendered, encoding="utf-8")
        destination.chmod(0o600)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
