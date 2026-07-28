#!/usr/bin/env python3
"""Create a source archive and checksum for a release tag."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RELEASE_DIR = ROOT / "dist" / "release"


def output(command: list[str]) -> str:
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("tag", help="existing tag, for example v1.0.0")
    args = parser.parse_args()
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    expected = f"v{version}"
    if args.tag != expected:
        raise SystemExit(f"VERSION is {version}; expected tag {expected}")
    output(["git", "rev-parse", "--verify", f"{args.tag}^{{commit}}"])
    if output(["git", "status", "--porcelain"]):
        raise SystemExit("refusing to package a dirty working tree")

    RELEASE_DIR.mkdir(parents=True, exist_ok=True)
    archive = RELEASE_DIR / f"whisper_hotkey-{version}-source.tar.gz"
    subprocess.run(
        [
            "git", "archive", "--format=tar.gz",
            f"--prefix=whisper_hotkey-{version}/",
            f"--output={archive}", args.tag,
        ],
        cwd=ROOT,
        check=True,
    )
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = Path(f"{archive}.sha256")
    checksum.write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    print(archive)
    print(checksum)


if __name__ == "__main__":
    main()
