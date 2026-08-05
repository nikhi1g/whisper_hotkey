#!/usr/bin/env python3
"""Create the signature-preserving ZIP that browsers download.

macOS blocks an unnotarized disk image before it can even mount, so the ZIP is
the primary human download: quarantine lands on the extracted app instead, and
one Privacy & Security > Open Anyway clears it. The DMG stays published for the
in-app updater, which downloads it directly and is never quarantined.
"""

from __future__ import annotations

import argparse
import hashlib
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP = ROOT / "dist" / "whisper_hotkey.app"
# Unversioned so that releases/latest/download/whisper_hotkey.zip stays stable.
DEFAULT_ZIP = ROOT / "dist" / "release" / "whisper_hotkey.zip"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def create_zip(app: Path, output: Path) -> Path:
    if not app.is_dir():
        raise RuntimeError(f"Application bundle not found at {app}")
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
        check=True,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
    # ditto preserves the code signature and resource forks; zip does not.
    subprocess.run(
        [
            "/usr/bin/ditto",
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            str(app),
            str(output),
        ],
        check=True,
    )
    checksum = Path(f"{output}.sha256")
    checksum.write_text(f"{sha256(output)}  {output.name}\n", encoding="utf-8")
    return checksum


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--output", type=Path, default=DEFAULT_ZIP)
    args = parser.parse_args()
    output = args.output.resolve()
    checksum = create_zip(args.app.resolve(), output)
    print(output)
    print(checksum)


if __name__ == "__main__":
    main()
