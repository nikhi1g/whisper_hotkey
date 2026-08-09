#!/usr/bin/env python3
"""Bounded, content-free performance and resource profiling for local ASR.

The profiler is deliberately conservative.  It can measure a resident local
Whisper helper when a private corpus and model are supplied, but it never
copies audio, stores helper output, or prints a transcript.  When a second
engine is not installed *and* exposed through a compatible per-request
adapter, the placement comparison is recorded as unavailable instead of
being approximated.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
import platform
import re
import select
import shutil
import signal
import statistics
import subprocess
import tempfile
import threading
import time
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


SCHEMA = "whisper_hotkey_performance_v1"
MAX_CASES = 100
MAX_MEASUREMENTS = 500
MAX_AUDIO_SECONDS = 60.0
MAX_COMMAND_BYTES = 256 * 1024
MAX_EVENT_LINE_BYTES = 256 * 1024
MAX_TEMP_FILES = 256
MAX_DISCOVERED_PATHS = 1_000
MAX_PROFILE_SECONDS = 15 * 60.0
MAX_HELPER_TIMEOUT_SECONDS = 60.0
MAX_THREADS = 8

_CONTENT_KEYS = frozenset(
    {
        "audio",
        "audio_data",
        "audio_file",
        "audio_path",
        "audio_url",
        "hypothesis",
        "hypothesis_text",
        "prompt",
        "prompt_text",
        "reference",
        "reference_text",
        "samples",
        "segments",
        "text",
        "transcript",
        "transcript_text",
        "transcription",
        "tokens",
        "utterance",
        "utterance_text",
        "wav",
        "wav_data",
        "wav_path",
        "waveform",
        "words",
    }
)


class PerformanceError(RuntimeError):
    """Raised when a bounded measurement cannot be performed safely."""


def _normalise_key(key: object) -> str:
    rendered = re.sub(r"(?<!^)(?=[A-Z])", "_", str(key))
    rendered = re.sub(r"[^A-Za-z0-9]+", "_", rendered)
    return rendered.casefold().strip("_")


def assert_content_free(value: object) -> None:
    """Reject content-bearing fields before a report is written.

    The helper protocol necessarily returns a transcript to the in-memory
    caller.  The profiler never passes that object to this function; only the
    aggregate report is checked here.  A recursive check makes accidental
    future additions fail closed.
    """

    if isinstance(value, Mapping):
        for key, child in value.items():
            normalised = _normalise_key(key)
            if normalised in _CONTENT_KEYS:
                raise PerformanceError("content-bearing report field rejected")
            if normalised.endswith(("_path", "_text", "_transcript")):
                raise PerformanceError("content-bearing report field rejected")
            assert_content_free(child)
    elif isinstance(value, list):
        for child in value:
            assert_content_free(child)


def percentile(values: Sequence[float], fraction: float) -> float:
    """Return a deterministic nearest-rank percentile.

    Nearest-rank avoids interpolation that can imply precision not present in
    a small bounded sample.  The 0.95 and 0.99 values therefore always name an
    observed latency.
    """

    if not values:
        raise PerformanceError("percentile requires at least one sample")
    if not 0.0 <= fraction <= 1.0:
        raise PerformanceError("percentile fraction is outside [0, 1]")
    ordered = sorted(float(item) for item in values)
    index = min(len(ordered) - 1, max(0, math.ceil(fraction * len(ordered)) - 1))
    return ordered[index]


def summary(values: Sequence[float]) -> dict[str, float]:
    if not values:
        raise PerformanceError("cannot summarize an empty sample")
    return {
        "mean": statistics.fmean(values),
        "p50": percentile(values, 0.50),
        "p95": percentile(values, 0.95),
        "p99": percentile(values, 0.99),
        "max": max(values),
    }


def latency_metrics(latencies: Sequence[float], audio_seconds: Sequence[float]) -> dict[str, Any]:
    if len(latencies) != len(audio_seconds) or not latencies:
        raise PerformanceError("latency and audio samples must have equal non-zero length")
    rtf_values = [latency / duration for latency, duration in zip(latencies, audio_seconds)]
    total_audio = sum(audio_seconds)
    total_latency = sum(latencies)
    return {
        "sample_count": len(latencies),
        "latency_seconds": summary(latencies),
        "rtf": summary(rtf_values),
        "total_audio_seconds": total_audio,
        "total_wall_seconds": total_latency,
        "aggregate_rtf": total_latency / total_audio if total_audio else None,
    }


def _run_capture(command: Sequence[str], timeout: float = 2.0) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            list(command),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return 127, ""
    # Metadata is never persisted.  Keep parsing bounded if a tool behaves
    # unexpectedly.
    return completed.returncode, completed.stdout[:64 * 1024]


def _field(output: str, label: str) -> str | None:
    prefix = f"{label}:"
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith(prefix):
            return stripped[len(prefix):].strip() or None
    return None


def _integer(value: str | None) -> int | None:
    if value is None:
        return None
    match = re.search(r"\d+", value.replace(",", ""))
    return int(match.group()) if match else None


def host_metadata() -> dict[str, Any]:
    """Collect hardware facts without serials, UUIDs, usernames, or paths."""

    _, hardware = _run_capture(["system_profiler", "SPHardwareDataType", "SPDisplaysDataType"])
    _, os_output = _run_capture(["sw_vers"])
    _, kernel_output = _run_capture(["uname", "-srm"])

    core_matches = re.findall(r"Total Number of Cores:\s*(\d+)", hardware)
    memory_text = _field(hardware, "Memory")
    memory_match = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*GB", memory_text or "")
    memory_gb = float(memory_match.group(1)) if memory_match else None
    os_name = _field(os_output, "ProductName")
    os_version = _field(os_output, "ProductVersion")
    os_build = _field(os_output, "BuildVersion")

    return {
        "architecture": platform.machine(),
        "model_identifier": _field(hardware, "Model Identifier"),
        "chip": _field(hardware, "Chip") or _field(hardware, "Chipset Model"),
        "cpu_cores_reported": int(core_matches[0]) if core_matches else None,
        "gpu_cores_reported": int(core_matches[1]) if len(core_matches) > 1 else None,
        "memory_gb_reported": memory_gb,
        "os": {
            "name": os_name,
            "version": os_version,
            "build": os_build,
            "kernel": kernel_output.strip() or None,
        },
    }


def available_tool(name: str) -> dict[str, Any]:
    path = shutil.which(name)
    if not path:
        return {"name": name, "status": "unavailable"}
    version: str | None = None
    if name == "xctrace":
        _, output = _run_capture([path, "version"])
        version = output.splitlines()[0].strip() if output.splitlines() else None
    return {"name": name, "status": "available", "version": version}


def thermal_metadata() -> dict[str, Any]:
    """Record only whether a non-privileged thermal query succeeded."""

    code, output = _run_capture(["pmset", "-g", "therm"])
    # pmset can return zero while writing only diagnostic Error: lines when
    # the platform does not expose a thermal power source.  That is not a
    # successful thermal observation.
    usable_lines = [line for line in output.splitlines() if not line.strip().startswith("Error:")]
    if code == 0 and any(line.strip() for line in usable_lines):
        return {
            "status": "queried",
            "source": "pmset -g therm",
            "raw_output_recorded": False,
        }
    return {
        "status": "unavailable",
        "source": "pmset -g therm",
        "raw_output_recorded": False,
        "note": "thermal warning/performance state was not exposed without privileged sampling",
    }


@dataclass(frozen=True)
class AudioCase:
    """A validated input handle; its path never enters a report."""

    path: Path
    duration_seconds: float


def _private(path: Path) -> bool:
    try:
        return (path.stat().st_mode & 0o077) == 0
    except OSError:
        return False


def load_audio_cases(
    wav_root: Path,
    *,
    maximum_cases: int = MAX_CASES,
    maximum_audio_seconds: float = MAX_AUDIO_SECONDS,
) -> list[AudioCase]:
    """Validate a bounded, private 16 kHz mono PCM16 corpus."""

    maximum_cases = max(1, min(MAX_CASES, int(maximum_cases)))
    maximum_audio_seconds = max(0.1, min(MAX_AUDIO_SECONDS, float(maximum_audio_seconds)))
    root = wav_root.expanduser().resolve()
    if not root.is_dir() or not _private(root):
        raise PerformanceError("private WAV root is missing or not owner-only")
    paths: list[Path] = []
    discovered = 0
    # Path.rglob has no traversal bound.  Walk explicitly so a mistakenly
    # broad fixture root cannot turn a benchmark into an unbounded scan.
    for current, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories[:] = sorted(
            name for name in directories if not (Path(current) / name).is_symlink()
        )
        for name in sorted(files):
            discovered += 1
            if discovered > MAX_DISCOVERED_PATHS:
                raise PerformanceError("WAV corpus discovery bound exceeded")
            if not name.casefold().endswith(".wav"):
                continue
            path = Path(current) / name
            if path.is_file() and not path.is_symlink():
                paths.append(path)
                if len(paths) >= maximum_cases:
                    break
        if len(paths) >= maximum_cases:
            break
    if not paths:
        raise PerformanceError("private WAV corpus has no WAV files")
    cases: list[AudioCase] = []
    for path in paths[:maximum_cases]:
        if not _private(path):
            raise PerformanceError("WAV corpus contains a non-private file")
        try:
            with wave.open(str(path), "rb") as source:
                if (
                    source.getnchannels() != 1
                    or source.getsampwidth() != 2
                    or source.getframerate() != 16_000
                ):
                    raise PerformanceError("WAV corpus is not mono PCM16 at 16 kHz")
                duration = source.getnframes() / source.getframerate()
        except (OSError, wave.Error) as error:
            raise PerformanceError("WAV corpus contains an unreadable file") from error
        if not math.isfinite(duration) or duration <= 0 or duration > maximum_audio_seconds:
            raise PerformanceError("WAV duration exceeds the profiling bound")
        cases.append(AudioCase(path=path, duration_seconds=duration))
    if not cases:
        raise PerformanceError("WAV corpus selection is empty")
    return cases


def _storage(root: Path) -> tuple[int, int]:
    """Return bounded bytes/file count for a profiler-owned temp directory."""

    total = 0
    files = 0
    directories = 0
    if not root.exists():
        return total, files
    pending = [root]
    while pending:
        current = pending.pop()
        try:
            entries = list(current.iterdir())
        except OSError as error:
            raise PerformanceError("temporary storage could not be inspected") from error
        for entry in entries:
            if entry.is_symlink():
                raise PerformanceError("temporary storage contains a symlink")
            if entry.is_dir():
                directories += 1
                if directories > MAX_TEMP_FILES:
                    raise PerformanceError("temporary storage directory bound exceeded")
                pending.append(entry)
                continue
            files += 1
            if files > MAX_TEMP_FILES:
                raise PerformanceError("temporary storage file bound exceeded")
            try:
                total += entry.stat().st_size
            except OSError as error:
                raise PerformanceError("temporary storage could not be measured") from error
    return total, files


def _rss_bytes(pid: int) -> int | None:
    code, output = _run_capture(["ps", "-o", "rss=", "-p", str(pid)])
    if code != 0:
        return None
    match = re.search(r"\d+", output)
    return int(match.group()) * 1024 if match else None


class RSSSampler:
    def __init__(self, pid: int, interval_seconds: float = 0.02) -> None:
        self.pid = pid
        self.interval_seconds = max(0.01, min(0.25, interval_seconds))
        self._stop = threading.Event()
        self.peak: int | None = None
        self._thread = threading.Thread(target=self._run, daemon=True)

    def _run(self) -> None:
        while not self._stop.is_set():
            value = _rss_bytes(self.pid)
            if value is not None:
                self.peak = value if self.peak is None else max(self.peak, value)
            self._stop.wait(self.interval_seconds)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=1.0)


class BoundedJSONReader:
    """Read one JSONL event without allowing an unbounded protocol line."""

    def __init__(self, stream: Any) -> None:
        self.stream = stream
        self.fd = stream.fileno()
        self.buffer = bytearray()

    def read(self, timeout_seconds: float) -> Mapping[str, Any]:
        deadline = time.monotonic() + timeout_seconds
        while True:
            newline = self.buffer.find(b"\n")
            if newline >= 0:
                line = bytes(self.buffer[:newline]).strip()
                del self.buffer[: newline + 1]
                if len(line) > MAX_EVENT_LINE_BYTES:
                    raise PerformanceError("helper event exceeded the line bound")
                try:
                    event = json.loads(line.decode("utf-8"))
                except (UnicodeDecodeError, ValueError) as error:
                    raise PerformanceError("helper event was not valid JSON") from error
                if not isinstance(event, Mapping):
                    raise PerformanceError("helper event was not an object")
                return event
            if len(self.buffer) > MAX_EVENT_LINE_BYTES:
                raise PerformanceError("helper event exceeded the line bound")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("helper event timed out")
            ready, _, _ = select.select([self.fd], [], [], remaining)
            if not ready:
                raise TimeoutError("helper event timed out")
            chunk = os.read(self.fd, 4096)
            if not chunk:
                raise PerformanceError("helper closed its event channel")
            self.buffer.extend(chunk)


class WhisperHelper:
    """Minimal owned-process adapter for the existing local helper protocol."""

    def __init__(self, executable: Path, model: Path, threads: int, strategy: str) -> None:
        self.executable = executable.expanduser().resolve()
        self.model = model.expanduser().resolve()
        self.threads = max(1, min(MAX_THREADS, int(threads)))
        self.strategy = strategy
        self.process: subprocess.Popen[bytes] | None = None
        self.reader: BoundedJSONReader | None = None

    @property
    def pid(self) -> int:
        if self.process is None:
            raise PerformanceError("helper has not started")
        return self.process.pid

    def start(self, timeout_seconds: float) -> float:
        if self.process is not None:
            raise PerformanceError("helper was started twice")
        started = time.perf_counter()
        try:
            self.process = subprocess.Popen(
                [
                    str(self.executable),
                    "--model",
                    str(self.model),
                    "--threads",
                    str(self.threads),
                    "--strategy",
                    self.strategy,
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                bufsize=0,
            )
        except OSError as error:
            raise PerformanceError("Whisper helper could not be launched") from error
        assert self.process.stdout is not None
        self.reader = BoundedJSONReader(self.process.stdout)
        event = self.reader.read(timeout_seconds)
        if event.get("event") != "ready":
            self.cancel()
            raise PerformanceError("Whisper helper did not report ready")
        return time.perf_counter() - started

    def _send(self, payload: Mapping[str, Any]) -> None:
        if self.process is None or self.process.stdin is None:
            raise PerformanceError("helper stdin is unavailable")
        rendered = (json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8")
        if len(rendered) > MAX_COMMAND_BYTES:
            raise PerformanceError("helper command exceeded the line bound")
        try:
            self.process.stdin.write(rendered)
            self.process.stdin.flush()
        except (BrokenPipeError, OSError) as error:
            raise PerformanceError("helper command channel closed") from error

    def transcribe(self, audio: Path, timeout_seconds: float) -> None:
        self._send(
            {
                "command": "transcribe",
                "audioPath": str(audio),
                "strategy": self.strategy,
                "emitTimestamps": False,
                "emitTokenData": False,
            }
        )
        if self.reader is None:
            raise PerformanceError("helper event reader is unavailable")
        event = self.reader.read(timeout_seconds)
        if event.get("event") not in {"result", "resultRich"}:
            # Do not include helper message/text in an exception or report.
            raise PerformanceError("helper returned a non-result event")

    def cancel(self, wait_seconds: float = 2.0) -> bool:
        process = self.process
        if process is None:
            return True
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                process.terminate()
            try:
                process.wait(timeout=wait_seconds)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    process.kill()
                try:
                    process.wait(timeout=wait_seconds)
                except subprocess.TimeoutExpired:
                    return False
        for stream in (process.stdin, process.stdout):
            if stream is not None:
                try:
                    stream.close()
                except OSError:
                    pass
        return process.poll() is not None

    close = cancel


def _engine_blockers(executable: Path | None, model: Path | None, label: str) -> list[str]:
    blockers: list[str] = []
    if executable is None:
        blockers.append(f"{label} executable was not supplied")
    elif not executable.expanduser().is_file() or not os.access(executable.expanduser(), os.X_OK):
        blockers.append(f"missing executable: {executable.name}")
    if model is None:
        blockers.append(f"{label} model was not supplied")
    elif not model.expanduser().is_file():
        blockers.append(f"missing model: {model.name}")
    return blockers


def engine_preflight(
    *,
    whisper_helper: Path | None,
    whisper_model: Path | None,
    parakeet_runner: Path | None,
    wav_root: Path | None,
) -> dict[str, Any]:
    corpus_blocker: str | None = None
    if wav_root is None:
        corpus_blocker = "private WAV corpus root was not supplied"
    else:
        root = wav_root.expanduser()
        if not root.is_dir():
            corpus_blocker = "private WAV corpus root is missing"
        elif not _private(root):
            corpus_blocker = "private WAV corpus root is not owner-only"

    whisper_blockers = _engine_blockers(whisper_helper, whisper_model, "Whisper")
    if corpus_blocker:
        whisper_blockers.append(corpus_blocker)
    parakeet_blockers: list[str] = []
    if parakeet_runner is None:
        parakeet_blockers.append("Parakeet executable was not supplied")
    elif not parakeet_runner.expanduser().is_file() or not os.access(parakeet_runner.expanduser(), os.X_OK):
        parakeet_blockers.append(f"missing executable: {parakeet_runner.name}")
    if corpus_blocker:
        parakeet_blockers.append(corpus_blocker)
    if parakeet_runner is not None and parakeet_runner.name == "parakeet-benchmark":
        parakeet_blockers.append("batch JSONL runner has no bounded per-request adapter for overlap profiling")
    return {
        "whisper_cpp": {
            "status": "ready" if not whisper_blockers else "blocked",
            "blockers": whisper_blockers,
        },
        "parakeet": {
            "status": "ready" if not parakeet_blockers else "blocked",
            "blockers": parakeet_blockers,
        },
        "corpus": {
            "status": "ready" if corpus_blocker is None else "blocked",
            "blockers": [] if corpus_blocker is None else [corpus_blocker],
        },
    }


def placement_comparison(preflight: Mapping[str, Any]) -> dict[str, Any]:
    whisper = preflight.get("whisper_cpp", {})
    parakeet = preflight.get("parakeet", {})
    blockers: list[str] = []
    if whisper.get("status") != "ready":
        blockers.append("Whisper helper/model/corpus preflight is blocked")
    if parakeet.get("status") != "ready":
        blockers.append("Parakeet runner/model/corpus preflight is blocked")
    if not blockers:
        blockers.append("no heterogeneous per-request adapter is registered")
    return {
        "name": "sequential_vs_heterogeneous_concurrent",
        "status": "unavailable",
        "sequential": None,
        "heterogeneous_concurrent": None,
        "policy": "fail_closed_until_two_installed_per_request_engines_are_profileable",
        "blockers": blockers,
    }


def _empty_profile(name: str, blockers: Iterable[str]) -> dict[str, Any]:
    return {
        "name": name,
        "status": "unavailable",
        "blockers": list(blockers),
        "metrics": None,
    }


def lower_memory_matrix() -> dict[str, Any]:
    """Return unmeasured lower-memory rows until a real host is profiled."""

    tiers = []
    for memory_gb in (8, 16, 24):
        tiers.append(
            {
                "memory_gb": memory_gb,
                "status": "unmeasured",
                "metrics": None,
                "blockers": [
                    "requires a separate Apple Silicon host with this memory tier",
                    "requires the same verified helper, model, and private WAV fixture",
                ],
            }
        )
    return {
        "procedure": "repeat the same warm/cold, RTF, RSS, storage, soak, and thermal protocol per tier",
        "tiers": tiers,
    }


def _new_report() -> dict[str, Any]:
    revision: str | None = None
    code, output = _run_capture(["git", "rev-parse", "HEAD"])
    if code == 0:
        candidate = output.strip().splitlines()[0] if output.strip() else ""
        if re.fullmatch(r"[0-9a-f]{7,64}", candidate):
            revision = candidate
    return {
        "schema": SCHEMA,
        "run": {
            "kind": "preflight",
            "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "revision": revision,
        },
        "host": host_metadata(),
        "tools": [available_tool(name) for name in ("xctrace", "powermetrics", "pmset", "ps")],
        "thermal": thermal_metadata(),
        "bounds": {
            "max_cases": MAX_CASES,
            "max_measurements": MAX_MEASUREMENTS,
            "max_audio_seconds_per_case": MAX_AUDIO_SECONDS,
            "max_event_line_bytes": MAX_EVENT_LINE_BYTES,
            "max_discovered_paths": MAX_DISCOVERED_PATHS,
            "max_concurrent_engine_processes": 2,
        },
        "preflight": {},
        "lower_memory_matrix": lower_memory_matrix(),
        "profiles": [],
        "comparisons": [],
        "privacy": {
            "content_free_report": True,
            "audio_written": False,
            "transcript_written": False,
            "child_output_persisted": False,
            "ordinary_user_content": False,
            "temporary_directories_owner_only": True,
            "temporary_storage_scope": "profiler-owned directories only",
        },
    }


def run_profile(
    *,
    helper_path: Path,
    model_path: Path,
    cases: Sequence[AudioCase],
    repeats: int,
    threads: int,
    strategy: str,
    timeout_seconds: float,
    maximum_wall_seconds: float = MAX_PROFILE_SECONDS,
) -> dict[str, Any]:
    """Measure a warm helper and bounded process RSS without retaining content."""

    repeats = max(1, min(MAX_MEASUREMENTS, int(repeats)))
    if len(cases) * repeats > MAX_MEASUREMENTS:
        raise PerformanceError("profile measurement bound exceeded")
    helper = WhisperHelper(helper_path, model_path, threads, strategy)
    latencies: list[float] = []
    audio_seconds: list[float] = []
    rtf_values: list[float] = []
    peak_rss: int | None = None
    warm_rss: int | None = None
    cold_start: float | None = None
    failures = 0
    started_all = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="whisper-hotkey-profile-") as temporary:
        temp_root = Path(temporary)
        temp_root.chmod(0o700)
        sampler: RSSSampler | None = None
        try:
            cold_start = helper.start(timeout_seconds)
            sampler = RSSSampler(helper.pid)
            sampler.start()
            # Warm-up is intentionally unreported as a measured dictation.
            helper.transcribe(cases[0].path, timeout_seconds)
            warm_rss = _rss_bytes(helper.pid)
            for _ in range(repeats):
                for case in cases:
                    if time.monotonic() - started_all > maximum_wall_seconds:
                        raise PerformanceError("profile wall-time bound exceeded")
                    before_bytes, before_files = _storage(temp_root)
                    del before_bytes, before_files
                    started = time.perf_counter()
                    try:
                        helper.transcribe(case.path, timeout_seconds)
                    except (PerformanceError, TimeoutError):
                        failures += 1
                        raise
                    elapsed = time.perf_counter() - started
                    after_bytes, after_files = _storage(temp_root)
                    del after_files
                    latencies.append(elapsed)
                    audio_seconds.append(case.duration_seconds)
                    rtf_values.append(elapsed / case.duration_seconds)
                    if after_bytes < 0:
                        raise PerformanceError("temporary storage measurement underflow")
                    if sampler.peak is not None:
                        peak_rss = sampler.peak if peak_rss is None else max(peak_rss, sampler.peak)
            max_temp_bytes, max_temp_files = _storage(temp_root)
        finally:
            if sampler is not None:
                sampler.stop()
            # The process group is owned by this run and is always reaped.
            helper.cancel()
        process_leak_count = 0 if helper.process is not None and helper.process.poll() is not None else 1

    if not latencies:
        raise PerformanceError("profile produced no measured samples")
    metrics = latency_metrics(latencies, audio_seconds)
    metrics.update(
        {
            "peak_rss_bytes": peak_rss,
            "warm_helper_rss_bytes": warm_rss,
            "cold_start_seconds": cold_start,
            "temporary_storage": {
                "max_bytes": max_temp_bytes,
                "max_files": max_temp_files,
                "scope": "profiler-owned empty directory; input WAVs are never copied",
            },
            "helper_process": {
                "owned_process_reaped": process_leak_count == 0,
                "owned_process_leak_count": process_leak_count,
                "concurrent_calls_per_helper": 1,
            },
            "failures": failures,
            "rtf_samples": summary(rtf_values),
        }
    )
    return {
        "name": "whisper_cpp_warm_helper",
        "status": "measured",
        "engine": "whisper.cpp",
        "strategy": strategy,
        "model_residency": "one owned warm helper process",
        "metrics": metrics,
        "thermal_note": "thermal state is recorded separately; no accuracy-degrading fallback is applied by this harness",
    }


def _write_report(report: Mapping[str, Any], destination: Path | None) -> None:
    assert_content_free(report)
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if destination is None:
        print(rendered, end="")
        return
    destination = destination.expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(rendered, encoding="utf-8")
    destination.chmod(0o600)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper", type=Path)
    parser.add_argument("--model", type=Path)
    parser.add_argument("--wav-root", type=Path)
    parser.add_argument("--parakeet-runner", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--strategy", choices=("beam", "greedy", "adaptive"), default="beam")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--max-cases", type=int, default=10)
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
                _empty_profile("whisper_cpp_warm_helper", preflight["whisper_cpp"]["blockers"])
            )
            exit_code = 2
        else:
            try:
                cases = load_audio_cases(args.wav_root, maximum_cases=args.max_cases)
                report["run"]["kind"] = "engine_profile"
                report["profiles"].append(
                    run_profile(
                        helper_path=args.helper,
                        model_path=args.model,
                        cases=cases,
                        repeats=args.repeats,
                        threads=args.threads,
                        strategy=args.strategy,
                        timeout_seconds=max(0.1, min(MAX_HELPER_TIMEOUT_SECONDS, args.timeout_seconds)),
                    )
                )
            except (PerformanceError, OSError, ValueError) as error:
                report["profiles"].append(_empty_profile("whisper_cpp_warm_helper", [str(error)]))
                exit_code = 2
    elif args.preflight or not requested_run:
        report["run"]["kind"] = "preflight"
    if args.compare and report["comparisons"][0]["status"] != "eligible":
        exit_code = 2
    _write_report(report, args.output)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
