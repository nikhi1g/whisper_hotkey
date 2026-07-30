#!/usr/bin/env python3
"""Download and verify the Whisper paper's LibriSpeech test splits."""

from __future__ import annotations

import hashlib
import tarfile
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARCHIVES = ROOT / "Data" / "Archives"
DATA = ROOT / "Data"
SPLITS = {
    "test-clean": (
        "https://www.openslr.org/resources/12/test-clean.tar.gz",
        "32fa31d27d2e1cad72775fee3f4849a9",
        "39fde525e59672dc6d1551919b1478f724438a95aa55f874b576be21967e6c23",
    ),
    "test-other": (
        "https://www.openslr.org/resources/12/test-other.tar.gz",
        "fb5a50374b501bb3bac4815ee91d3135",
        "d09c181bba5cf717b3dee7d4d592af11a3ee3a09e08ae025c5506f6ebe961c29",
    ),
}


def digest(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_members(archive: tarfile.TarFile):
    root = DATA.resolve()
    for member in archive.getmembers():
        destination = (DATA / member.name).resolve()
        if root not in destination.parents and destination != root:
            raise RuntimeError(f"unsafe archive member: {member.name}")
        if member.issym() or member.islnk():
            raise RuntimeError(f"links are not accepted: {member.name}")
        yield member


def main() -> None:
    ARCHIVES.mkdir(parents=True, exist_ok=True)
    for split, (url, expected_md5, expected_sha256) in SPLITS.items():
        archive_path = ARCHIVES / f"{split}.tar.gz"
        if not archive_path.exists():
            print(f"downloading {split}")
            urllib.request.urlretrieve(url, archive_path)
        actual_md5 = digest(archive_path, "md5")
        actual_sha256 = digest(archive_path, "sha256")
        if actual_md5 != expected_md5 or actual_sha256 != expected_sha256:
            raise SystemExit(
                f"{archive_path.name}: checksum verification failed"
            )
        destination = DATA / "LibriSpeech" / split
        if not destination.exists():
            print(f"extracting {split}")
            with tarfile.open(archive_path, "r:gz") as archive:
                archive.extractall(DATA, members=safe_members(archive))
        print(f"{split}: verified")


if __name__ == "__main__":
    main()
