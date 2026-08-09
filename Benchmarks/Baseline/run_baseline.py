#!/usr/bin/env python3
"""Collect a deterministic, content-safe recognition baseline.

The existing benchmark runners remain the source of recognition measurements.
This wrapper records only aggregate metrics and provenance; it deliberately
omits per-utterance hypotheses, references, and audio paths from its output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable, Mapping, Sequence


SCHEMA = "whisper_hotkey_baseline_v1"
AUDITED_RELEASE_TAG = "v3.6.2"
AUDITED_RELEASE_COMMIT = "317fced"
AUDITED_CURRENT_MAIN_COMMIT = "210009e"
WHISPER_CPP_VERSION = "1.9.1"
WHISPER_CPP_COMMIT = "f049fff95a089aa9969deb009cdd4892b3e74916"

# These are the model pins documented by the repository.  A live run records
# the observed file digest as well; the pins remain useful when a run cannot
# be performed on a checkout without the ignored model cache.
MODEL_PINS = (
    (
        "ggml-base.en.bin",
        "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
    ),
    (
        "ggml-small.en.bin",
        "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d",
    ),
    (
        "ggml-medium.en.bin",
        "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356",
    ),
    (
        "ggml-large-v3-turbo-q5_0.bin",
        "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
    ),
)
MODEL_PIN_BY_NAME = dict(MODEL_PINS)

CORPUS_ID = "librispeech_test100_local"
CORPUS_MANIFEST = Path(
    "Benchmarks/BenchmarkSuite/datasets/merged/librispeech-100/manifest.json"
)
CORPUS_CASE_IDS = Path(
    "Benchmarks/BenchmarkSuite/datasets/merged/librispeech-100/case_ids.txt"
)

PROCESSING_MODES = (
    "afterRecording",
    "modelReady",
    "decodeWhileSpeaking",
)
DECODING_PROFILES = (
    "precision",
    "adaptive",
    "greedy",
)

# These keys are rejected anywhere in an input result, even though this
# collector only copies a whitelist of numeric aggregate fields. Rejecting the
# fields makes an accidental content-bearing result fail closed.
FORBIDDEN_CONTENT_KEYS = frozenset(
    {
        "audio",
        "audio_path",
        "audio_url",
        "audiofile",
        "audio_file",
        "audio_data",
        "hypothesis",
        "hypothesis_text",
        "prompt",
        "prompt_text",
        "reference",
        "reference_text",
        "references",
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
        "wav_path",
        "waveform",
        "words",
    }
)

LIBRISPEECH_METRIC_KEYS = (
    "combined_wer",
    "test_clean_wer",
    "test_other_wer",
    "mean_seconds",
    "p50_seconds",
    "p95_seconds",
    "total_seconds",
    "fallback_fraction",
    "mean_average_log_probability",
    "mean_weak_token_fraction",
)
PREDECODE_METRIC_KEYS = (
    "full_wer",
    "predecode_wer",
    "full_mean_release_seconds",
    "predecode_mean_release_seconds",
    "full_p50_release_seconds",
    "predecode_p50_release_seconds",
    "full_p95_release_seconds",
    "predecode_p95_release_seconds",
    "mean_chunks",
)


class BaselineError(RuntimeError):
    """Raised when baseline provenance or result safety cannot be established."""


def _run_capture(
    command: Sequence[str],
    *,
    cwd: Path | None = None,
) -> str | None:
    """Run a metadata command without exposing its output to the terminal."""

    try:
        completed = subprocess.run(
            list(command),
            cwd=str(cwd) if cwd else None,
            capture_output=True,
            check=False,
            text=True,
        )
    except (OSError, ValueError):
        return None
    if completed.returncode != 0:
        return None
    lines = completed.stdout.splitlines()
    return lines[0].strip() if lines else None


def _required_git(command: Sequence[str], repo_root: Path) -> str:
    value = _run_capture(command, cwd=repo_root)
    if not value:
        raise BaselineError("unable to read repository provenance")
    return value


def _safe_key(key: object) -> str:
    # JSON producers use both snake_case and camelCase.  Normalize both
    # forms before checking the fail-closed content deny-list.
    rendered = re.sub(r"(?<!^)(?=[A-Z])", "_", str(key))
    rendered = re.sub(r"[^A-Za-z0-9]+", "_", rendered)
    return rendered.casefold().strip("_")


def _reject_content_keys(value: object) -> None:
    """Reject content-bearing fields before any result is summarized."""

    if isinstance(value, Mapping):
        for key, child in value.items():
            if _safe_key(key) in FORBIDDEN_CONTENT_KEYS:
                raise BaselineError("benchmark result contains content-bearing fields")
            _reject_content_keys(child)
    elif isinstance(value, list):
        for child in value:
            _reject_content_keys(child)


def _finite_number(value: object, key: str) -> int | float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise BaselineError(f"benchmark metric is not numeric: {key}")
    numeric = float(value)
    if not math.isfinite(numeric):
        raise BaselineError(f"benchmark metric is not finite: {key}")
    return value


def _metric_subset(
    payload: Mapping[str, object],
    keys: Iterable[str],
) -> dict[str, int | float]:
    metrics: dict[str, int | float] = {}
    for key in keys:
        if key in payload:
            metrics[key] = _finite_number(payload[key], key)
    return metrics


def _result_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise BaselineError("unable to read benchmark result") from error
    return digest.hexdigest()


def _load_result(path: Path) -> tuple[Mapping[str, object], str]:
    if not path.is_file():
        raise BaselineError("benchmark result file is missing")
    try:
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError) as error:
        raise BaselineError("benchmark result is not valid JSON") from error
    if not isinstance(payload, Mapping):
        raise BaselineError("benchmark result must be a JSON object")
    _reject_content_keys(payload)
    return payload, _result_sha256(path)


def _profile_name(profile: str) -> str:
    # The existing runner calls the five-beam profile "accuracy". The product
    # calls that same deterministic profile Precision.
    return "precision" if profile == "accuracy" else profile


def summarize_result(path: Path) -> list[dict[str, object]]:
    """Return aggregate-only metric records from an existing runner result."""

    payload, digest = _load_result(path)
    records: list[dict[str, object]] = []

    profiles = payload.get("profiles")
    if isinstance(profiles, Mapping):
        for raw_profile in sorted(profiles):
            profile = str(raw_profile)
            entry = profiles[raw_profile]
            if not isinstance(entry, Mapping):
                raise BaselineError("benchmark profile is not an object")
            metrics = _metric_subset(entry, LIBRISPEECH_METRIC_KEYS)
            if "combined_wer" not in metrics:
                raise BaselineError("benchmark profile has no aggregate WER")
            records.append(
                {
                    "record_type": "metrics",
                    "benchmark": "librispeech_test100",
                    "dataset": "LibriSpeech test-clean + test-other",
                    "decode_profile": _profile_name(profile),
                    "processing_mode": "fullRecordingWarmHelper",
                    "source_result": path.name,
                    "source_result_sha256": digest,
                    "examples_per_split": payload.get("examples_per_split"),
                    "metrics": metrics,
                }
            )

    if "predecode_wer" in payload:
        metrics = _metric_subset(payload, PREDECODE_METRIC_KEYS)
        if "full_wer" not in metrics:
            raise BaselineError("predecode result has no full-recording WER")
        raw_strategy = str(payload.get("strategy", "accuracy"))
        records.append(
            {
                "record_type": "metrics",
                "benchmark": "librispeech_test100_predecode",
                "dataset": "LibriSpeech test-clean + test-other",
                "decode_profile": _profile_name(raw_strategy),
                "processing_mode": "decodeWhileSpeaking",
                "source_result": path.name,
                "source_result_sha256": digest,
                "examples_per_split": payload.get("examples_per_split"),
                "metrics": metrics,
            }
        )

    if not records:
        raise BaselineError("benchmark result has no supported aggregate metrics")
    return records


def _sha256_file(
    path: Path,
    *,
    required: bool,
    expected_sha256: str | None = None,
) -> dict[str, object] | None:
    if not path.is_file():
        if required:
            raise BaselineError("required model or helper file is missing")
        return None
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise BaselineError("unable to hash model or helper file") from error
    info: dict[str, object] = {
        "name": path.name,
        "size_bytes": path.stat().st_size,
        "sha256": digest.hexdigest(),
    }
    if expected_sha256 is not None:
        info["expected_sha256"] = expected_sha256
        info["sha256_verified"] = digest.hexdigest() == expected_sha256
    return info


def _model_metadata(path: Path) -> dict[str, object]:
    """Require a known model pin before a benchmark process can start."""

    expected_sha256 = MODEL_PIN_BY_NAME.get(path.name)
    if expected_sha256 is None:
        raise BaselineError("model filename has no recorded SHA-256 pin")
    info = _sha256_file(
        path.resolve(),
        required=True,
        expected_sha256=expected_sha256,
    )
    assert info is not None
    if not info["sha256_verified"]:
        raise BaselineError("model SHA-256 does not match the recorded pin")
    return info


def _tracked_file_metadata(
    repo_root: Path,
    relative_path: Path,
) -> dict[str, object]:
    """Hash a tracked manifest without copying its contents into the report."""

    path = repo_root / relative_path
    info = _sha256_file(path, required=False)
    if info is None:
        return {
            "path": relative_path.as_posix(),
            "status": "missing",
        }
    return {
        "path": relative_path.as_posix(),
        "size_bytes": info["size_bytes"],
        "sha256": info["sha256"],
        "status": "present",
    }


def _corpus_metadata(repo_root: Path) -> dict[str, object]:
    """Describe the frozen smoke selection and its missing runner hooks."""

    return {
        "id": CORPUS_ID,
        "dataset": "LibriSpeech test-clean + test-other",
        "selection": {
            "examples_per_split": 50,
            "manifest": _tracked_file_metadata(repo_root, CORPUS_MANIFEST),
            "case_ids": _tracked_file_metadata(repo_root, CORPUS_CASE_IDS),
        },
        "source": "OpenSLR",
        "license": "CC BY 4.0",
        "runner_hooks": {
            "selection_argument": "--per-split",
            "manifest_argument": None,
            "manifest_enforced": False,
            "missing": (
                "benchmark_librispeech.py reconstructs evenly spaced cases "
                "from the extracted corpus and does not consume the tracked "
                "case_ids.txt manifest"
            ),
        },
    }


def _sysctl(name: str) -> str | None:
    return _run_capture(("sysctl", "-n", name))


def runtime_metadata() -> dict[str, object]:
    """Capture stable host/runtime identifiers, never user content."""

    product_name = _run_capture(("sw_vers", "-productName"))
    product_version = _run_capture(("sw_vers", "-productVersion"))
    build_version = _run_capture(("sw_vers", "-buildVersion"))
    memory = _sysctl("hw.memsize")
    physical_cpu = _sysctl("hw.physicalcpu")
    logical_cpu = _sysctl("hw.logicalcpu")

    def integer(value: str | None) -> int | None:
        try:
            return int(value) if value is not None else None
        except ValueError:
            return None

    swift_version = _run_capture(("swift", "--version"))
    return {
        "os": {
            "name": product_name or platform.system(),
            "version": product_version,
            "build": build_version,
            "kernel": platform.release(),
        },
        "hardware": {
            "architecture": platform.machine(),
            "model": _sysctl("hw.model"),
            "physical_cpu": integer(physical_cpu),
            "logical_cpu": integer(logical_cpu),
            "memory_bytes": integer(memory),
        },
        "runtime": {
            "python": platform.python_version(),
            "swift": swift_version,
        },
    }


def _package_metadata(repo_root: Path, whisper_prefix: str | None) -> dict[str, object]:
    package_path = repo_root / "Package.swift"
    resolved_path = repo_root / "Package.resolved"
    swift_tools_version: str | None = None
    deployment_target: str | None = None
    if package_path.is_file():
        try:
            source = package_path.read_text(encoding="utf-8")
        except OSError as error:
            raise BaselineError("unable to read Package.swift") from error
        tools_match = re.search(r"swift-tools-version:\s*([0-9.]+)", source)
        target_match = re.search(r"\.macOS\(\.v([0-9.]+)\)", source)
        swift_tools_version = tools_match.group(1) if tools_match else None
        deployment_target = target_match.group(1) if target_match else None

    pins: list[dict[str, object]] = []
    if resolved_path.is_file():
        try:
            resolved = json.loads(resolved_path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise BaselineError("Package.resolved is not valid JSON") from error
        for pin in resolved.get("pins", []):
            if not isinstance(pin, Mapping):
                continue
            state = pin.get("state")
            if not isinstance(state, Mapping):
                state = {}
            pins.append(
                {
                    "identity": pin.get("identity"),
                    "location": pin.get("location"),
                    "version": state.get("version"),
                    "revision": state.get("revision"),
                }
            )
    pins.sort(key=lambda pin: str(pin.get("identity")))
    fluid_audio = next(
        (pin for pin in pins if pin.get("identity") == "fluidaudio"),
        None,
    )
    return {
        "swift_tools_version": swift_tools_version,
        "macos_deployment_target": deployment_target,
        "swift_package_pins": pins,
        "fluid_audio": fluid_audio,
        "whisper_cpp": {
            "declared_version": WHISPER_CPP_VERSION,
            "declared_commit": WHISPER_CPP_COMMIT,
            "prefix_name": Path(whisper_prefix).name if whisper_prefix else None,
            "version_source": "repository build policy",
        },
    }


def _revision_metadata(repo_root: Path, build_line: str) -> tuple[dict[str, object], list[dict[str, object]]]:
    commit = _required_git(("git", "rev-parse", "HEAD"), repo_root)
    branch = _required_git(("git", "branch", "--show-current"), repo_root)
    exact_tag = _run_capture(("git", "describe", "--tags", "--exact-match", "HEAD"), cwd=repo_root)
    dirty = bool(
        _run_capture(
            ("git", "status", "--porcelain", "--untracked-files=no"),
            cwd=repo_root,
        )
    )
    release_matches = commit.startswith(AUDITED_RELEASE_COMMIT)
    main_matches = commit.startswith(AUDITED_CURRENT_MAIN_COMMIT)
    if build_line == "auto":
        if release_matches:
            observed_line = "release"
        elif main_matches:
            observed_line = "current-main"
        else:
            observed_line = "candidate"
    else:
        observed_line = build_line

    revision = {
        "commit": commit,
        "branch": branch,
        "exact_tag": exact_tag,
        "working_tree_dirty": dirty,
        "build_line": observed_line,
        "release_reference": {
            "tag": AUDITED_RELEASE_TAG,
            "commit": AUDITED_RELEASE_COMMIT,
            "source": "MD/02_CURRENT_REPOSITORY_AUDIT.md",
        },
    }
    audit_diff = [
        {
            "fact": "current_main_commit",
            "expected": AUDITED_CURRENT_MAIN_COMMIT,
            "observed": commit,
            "status": "confirmed" if main_matches else "changed",
        },
        {
            "fact": "latest_public_release",
            "expected": f"{AUDITED_RELEASE_TAG}@{AUDITED_RELEASE_COMMIT}",
            "observed": f"{exact_tag or 'no exact tag'}@{commit}",
            "status": "confirmed" if release_matches and exact_tag == AUDITED_RELEASE_TAG else "changed",
        },
    ]
    return revision, audit_diff


def _mode_inventory() -> list[dict[str, object]]:
    return [
        {
            "id": "afterRecording",
            "status": "smoke_only",
            "benchmark_hook": "fullRecordingWarmHelper",
        },
        {
            "id": "modelReady",
            "status": "smoke_only",
            "benchmark_hook": "fullRecordingWarmHelper",
        },
        {
            "id": "decodeWhileSpeaking",
            "status": "measured_when_predecode_result_is_supplied",
            "benchmark_hook": "decodeWhileSpeaking",
        },
    ]


def _run_smoke(
    repo_root: Path,
    *,
    helper: Path,
    model: Path,
    wav_root: Path,
    per_split: int,
    threads: int | None,
    profiles: Sequence[str],
    include_predecode: bool,
    predecode_strategy: str,
) -> tuple[list[Path], Path]:
    scripts_root = repo_root / "Benchmarks" / "Scripts"
    runner = scripts_root / "benchmark_librispeech.py"
    if not runner.is_file():
        raise BaselineError("existing LibriSpeech benchmark runner is missing")
    command = [
        sys.executable,
        str(runner),
        "--helper",
        str(helper),
        "--model",
        str(model),
        "--wav-root",
        str(wav_root),
        "--profiles",
        *profiles,
        "--per-split",
        str(per_split),
    ]
    if threads is not None:
        command.extend(("--threads", str(threads)))
    try:
        completed = subprocess.run(
            command,
            cwd=str(repo_root),
            capture_output=True,
            check=False,
            text=True,
        )
    except OSError as error:
        raise BaselineError("unable to run existing LibriSpeech benchmark") from error
    if completed.returncode != 0:
        raise BaselineError("existing LibriSpeech benchmark failed")

    result_paths = [repo_root / "Benchmarks" / "Results" / "latest.json"]
    predecode_path = repo_root / "Benchmarks" / "Results" / "predecode-latest.json"
    if include_predecode:
        predecode_runner = scripts_root / "benchmark_predecode.py"
        if not predecode_runner.is_file():
            raise BaselineError("existing predecode benchmark runner is missing")
        predecode_command = [
            sys.executable,
            str(predecode_runner),
            "--helper",
            str(helper),
            "--model",
            str(model),
            "--wav-root",
            str(wav_root),
            "--per-split",
            str(per_split),
            "--strategy",
            predecode_strategy,
        ]
        if threads is not None:
            predecode_command.extend(("--threads", str(threads)))
        try:
            completed = subprocess.run(
                predecode_command,
                cwd=str(repo_root),
                capture_output=True,
                check=False,
                text=True,
            )
        except OSError as error:
            raise BaselineError("unable to run existing predecode benchmark") from error
        if completed.returncode != 0:
            raise BaselineError("existing predecode benchmark failed")
        result_paths.append(predecode_path)
    return result_paths, predecode_path


def collect_baseline(
    repo_root: Path,
    *,
    result_paths: Sequence[Path],
    model: Path | None,
    helper: Path | None,
    engine: str,
    whisper_prefix: str | None,
    build_line: str,
) -> list[dict[str, object]]:
    revision, audit_diff = _revision_metadata(repo_root, build_line)
    model_info = _model_metadata(model) if model else None
    helper_info = _sha256_file(helper.resolve(), required=True) if helper else None
    dependencies = _package_metadata(repo_root, whisper_prefix)
    metadata: dict[str, object] = {
        "schema": SCHEMA,
        "record_type": "metadata",
        "revision": revision,
        "audit_diff": audit_diff,
        "dependencies": dependencies,
        "model": model_info,
        "model_pins": [
            {
                "name": name,
                "sha256": sha256,
                "source": "docs/MODELS.md",
            }
            for name, sha256 in MODEL_PINS
        ],
        "helper": helper_info,
        "engine": engine,
        "runtime": runtime_metadata(),
        "benchmark_corpus": _corpus_metadata(repo_root),
        "reproduction": {
            "full_recording_runner": "Benchmarks/Scripts/benchmark_librispeech.py",
            "decode_while_speaking_runner": "Benchmarks/Scripts/benchmark_predecode.py",
            "subprocess_output_persisted": False,
            "application_lifecycle_smoke": False,
        },
        "processing_modes": _mode_inventory(),
        "decoding_profiles": list(DECODING_PROFILES),
        "content_policy": {
            "audio_persisted": False,
            "transcripts_persisted": False,
            "ordinary_user_content": False,
            "aggregate_metrics_only": True,
        },
    }
    records = [metadata]
    seen: set[tuple[str, str, str]] = set()
    for path in result_paths:
        for record in summarize_result(path.resolve()):
            key = (
                str(record["benchmark"]),
                str(record["decode_profile"]),
                str(record["source_result_sha256"]),
            )
            if key not in seen:
                records.append(record)
                seen.add(key)
    records[1:] = sorted(
        records[1:],
        key=lambda record: (
            str(record["benchmark"]),
            str(record["processing_mode"]),
            str(record["decode_profile"]),
        ),
    )
    return records


def jsonl(records: Sequence[Mapping[str, object]]) -> str:
    """Serialize records with stable key and record ordering."""

    return "".join(
        json.dumps(record, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        + "\n"
        for record in records
    )


def _write_private_output(path: Path, rendered: str) -> None:
    """Write aggregate output with owner-only permissions."""

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(rendered, encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError as error:
        raise BaselineError("unable to protect baseline output") from error


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Collect aggregate-only, reproducible whisper_hotkey baseline evidence."
    )
    parser.add_argument("--repo-root", type=Path, default=_default_repo_root())
    parser.add_argument("--result", action="append", type=Path, dest="results")
    parser.add_argument("--predecode-result", type=Path)
    parser.add_argument("--run-smoke", action="store_true")
    parser.add_argument("--skip-predecode", action="store_true")
    parser.add_argument("--helper", type=Path)
    parser.add_argument("--model", type=Path)
    parser.add_argument("--wav-root", type=Path)
    parser.add_argument("--per-split", type=int, default=50)
    parser.add_argument("--threads", type=int)
    parser.add_argument(
        "--profiles",
        nargs="+",
        choices=("accuracy", "greedy", "adaptive"),
        default=("accuracy", "greedy", "adaptive"),
    )
    parser.add_argument(
        "--predecode-strategy",
        choices=("accuracy", "adaptive"),
        default="accuracy",
    )
    parser.add_argument("--engine", default="whisperTurboMetal")
    parser.add_argument("--whisper-cpp-prefix", default=os.environ.get("WHISPER_CPP_PREFIX"))
    parser.add_argument(
        "--build-line",
        choices=("auto", "release", "current-main", "candidate"),
        default="auto",
    )
    parser.add_argument("--output", type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    repo_root = args.repo_root.resolve()
    result_paths: list[Path] = list(args.results or [])

    if args.run_smoke:
        if not args.helper or not args.model:
            parser.error("--run-smoke requires --helper and --model")
        # Validate the model before launching either benchmark subprocess. This
        # prevents a run with an unpinned or mismatched model from producing a
        # result that looks reproducible.
        _model_metadata(args.model)
        _sha256_file(args.helper.resolve(), required=True)
        wav_root = args.wav_root or repo_root / "Benchmarks" / "Data" / "WAV"
        generated, predecode_path = _run_smoke(
            repo_root,
            helper=args.helper.resolve(),
            model=args.model.resolve(),
            wav_root=wav_root.resolve(),
            per_split=args.per_split,
            threads=args.threads,
            profiles=args.profiles,
            include_predecode=not args.skip_predecode,
            predecode_strategy=args.predecode_strategy,
        )
        result_paths.extend(generated)
    elif args.predecode_result:
        result_paths.append(args.predecode_result)

    if not result_paths:
        default_result = repo_root / "Benchmarks" / "Results" / "latest.json"
        default_predecode = repo_root / "Benchmarks" / "Results" / "predecode-latest.json"
        result_paths = [default_result]
        if default_predecode.is_file():
            result_paths.append(default_predecode)

    if not args.model and args.run_smoke:
        parser.error("--run-smoke requires --model")
    records = collect_baseline(
        repo_root,
        result_paths=result_paths,
        model=args.model,
        helper=args.helper,
        engine=args.engine,
        whisper_prefix=args.whisper_cpp_prefix,
        build_line=args.build_line,
    )
    rendered = jsonl(records)
    if args.output:
        output = args.output.resolve()
        _write_private_output(output, rendered)
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BaselineError as error:
        print(f"baseline error: {error}", file=sys.stderr)
        raise SystemExit(2)
