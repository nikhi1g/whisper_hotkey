#!/usr/bin/env python3
"""Download one immutable WhisperKit bundle and verify every file with SHA-256."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
import urllib.request
from pathlib import Path


MODEL_REPOSITORY = "argmaxinc/whisperkit-coreml"
MODEL_REVISION = "97a5bf9bbc74c7d9c12c755d04dea59e672e3808"
TOKENIZER_FILES = (
    "added_tokens.json",
    "merges.txt",
    "normalizer.json",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "vocab.json",
)
MODELS = {
    "base": {
        "folder": "openai_whisper-base.en",
        "tokenizer": "openai/whisper-base.en",
        "tokenizer_revision": "911407f4214e0e1d82085af863093ec0b66f9cd6",
        "manifest_sha256": "2dba887e686e243624581a4dbecb7e96119073decb27a03ed27d197f2ea46eac",
    },
    "small": {
        "folder": "openai_whisper-small.en",
        "tokenizer": "openai/whisper-small.en",
        "tokenizer_revision": "e8727524f962ee844a7319d92be39ac1bd25655a",
        "manifest_sha256": "ef30e66089ed50dc4a1ac70d72f650ec346d96b2131500e9747abebaaf63f623",
    },
    "medium": {
        "folder": "openai_whisper-medium.en",
        "tokenizer": "openai/whisper-medium.en",
        "tokenizer_revision": "2e98eb6279edf5095af0c8dedb36bdec0acd172b",
        "manifest_sha256": "7b6a9746f3ca1987d0d07b7b956f90db23521bab9ac66a4980e60571c1a0687e",
    },
    "turbo": {
        "folder": "openai_whisper-large-v3-v20240930_626MB",
        "tokenizer": "openai/whisper-large-v3",
        "tokenizer_revision": "06f233fe06e710322aca913c1bc4249a0d71fce1",
        "manifest_sha256": "b3c7c827b05fc79353bdec78b3a2153a187c3023a2aa6d70f747747915578716",
    },
}


def read_json(url: str) -> object:
    with urllib.request.urlopen(url) as response:
        return json.load(response)


def model_paths(folder: str) -> list[str]:
    url = (
        f"https://huggingface.co/api/models/{MODEL_REPOSITORY}/tree/"
        f"{MODEL_REVISION}/{folder}?recursive=true&expand=true"
    )
    entries = read_json(url)
    return sorted(
        entry["path"].split("/", 1)[1]
        for entry in entries
        if entry.get("type") == "file"
    )


def download(url: str, destination: Path) -> str:
    destination.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    with urllib.request.urlopen(url) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
            digest.update(chunk)
    destination.chmod(0o600)
    return digest.hexdigest()


def manifest_digest(entries: list[tuple[str, str]]) -> str:
    content = "".join(
        f"{digest}  {path}\n" for path, digest in sorted(entries)
    )
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def verify_existing(
    destination: Path,
    relative_paths: list[str],
    expected: str,
) -> bool:
    entries: list[tuple[str, str]] = []
    for relative_path in relative_paths:
        path = destination / relative_path
        if not path.is_file():
            return False
        digest = hashlib.sha256()
        with path.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
        entries.append((relative_path, digest.hexdigest()))
    return manifest_digest(entries) == expected


def local_paths(destination: Path) -> list[str]:
    return sorted(
        str(path.relative_to(destination))
        for path in destination.rglob("*")
        if path.is_file()
    )


def install(
    model: str,
    destination_root: Path,
    verify_only: bool = False,
) -> Path:
    configuration = MODELS[model]
    folder = str(configuration["folder"])
    expected = str(configuration["manifest_sha256"])
    destination = destination_root / folder
    if verify_only and not destination_root.is_dir():
        raise RuntimeError(f"WhisperKit model is not installed: {destination}")
    destination_root.mkdir(parents=True, exist_ok=True)
    if not verify_only:
        destination_root.chmod(0o700)
    if destination.exists():
        paths = local_paths(destination)
        if destination.is_dir() and verify_existing(
            destination,
            paths,
            expected,
        ):
            return destination
        raise RuntimeError(f"existing WhisperKit model failed verification: {destination}")
    if verify_only:
        raise RuntimeError(f"WhisperKit model is not installed: {destination}")

    model_files = model_paths(folder)
    temporary = Path(
        tempfile.mkdtemp(prefix=f".{folder}.", dir=destination_root)
    )
    entries: list[tuple[str, str]] = []
    try:
        for relative_path in model_files:
            url = (
                f"https://huggingface.co/{MODEL_REPOSITORY}/resolve/"
                f"{MODEL_REVISION}/{folder}/{relative_path}"
            )
            digest = download(url, temporary / relative_path)
            entries.append((relative_path, digest))

        tokenizer = str(configuration["tokenizer"])
        tokenizer_revision = str(configuration["tokenizer_revision"])
        for relative_path in TOKENIZER_FILES:
            url = (
                f"https://huggingface.co/{tokenizer}/resolve/"
                f"{tokenizer_revision}/{relative_path}"
            )
            digest = download(url, temporary / relative_path)
            entries.append((relative_path, digest))

        actual = manifest_digest(entries)
        if actual != expected:
            raise RuntimeError(
                f"WhisperKit manifest checksum mismatch: expected {expected}, got {actual}"
            )
        os.replace(temporary, destination)
        return destination
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", choices=MODELS)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--verify-only", action="store_true")
    arguments = parser.parse_args()
    print(
        install(
            arguments.model,
            arguments.destination,
            verify_only=arguments.verify_only,
        )
    )


if __name__ == "__main__":
    main()
