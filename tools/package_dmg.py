#!/usr/bin/env python3
"""Create, sign, notarize, staple, and verify the public release DMG."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP = ROOT / "dist" / "whisper_hotkey.app"
DEFAULT_DMG = ROOT / "dist" / "release" / "whisper_hotkey.dmg"
MODEL_NAME = "ggml-base.en.bin"
MODEL_SHA256 = (
    "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
)


def run(command: list[str], *, capture: bool = False) -> str:
    result = subprocess.run(
        command,
        check=True,
        text=True,
        capture_output=capture,
    )
    return result.stdout if capture else ""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_release_app(app: Path) -> str:
    if not app.is_dir():
        raise RuntimeError(f"Application bundle not found at {app}")
    model = app / "Contents" / "Resources" / "Models" / MODEL_NAME
    if not model.is_file() or sha256(model) != MODEL_SHA256:
        raise RuntimeError(
            "The release app must contain the pinned, verified Base English model."
        )
    result = subprocess.run(
        ["/usr/bin/codesign", "--display", "--verbose=4", str(app)],
        check=True,
        text=True,
        capture_output=True,
    )
    details = f"{result.stdout}\n{result.stderr}"
    authority = re.search(r"^Authority=(Developer ID Application:.+)$", details, re.M)
    if authority is None:
        raise RuntimeError(
            "The public DMG requires a Developer ID Application-signed app."
        )
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    return authority.group(1)


def notarize(dmg: Path) -> None:
    required = {
        "NOTARY_APPLE_ID": os.environ.get("NOTARY_APPLE_ID", "").strip(),
        "NOTARY_PASSWORD": os.environ.get("NOTARY_PASSWORD", "").strip(),
        "APPLE_TEAM_ID": os.environ.get("APPLE_TEAM_ID", "").strip(),
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        raise RuntimeError(
            "Missing notarization environment: " + ", ".join(missing)
        )
    run([
        "/usr/bin/xcrun",
        "notarytool",
        "submit",
        str(dmg),
        "--apple-id",
        required["NOTARY_APPLE_ID"],
        "--password",
        required["NOTARY_PASSWORD"],
        "--team-id",
        required["APPLE_TEAM_ID"],
        "--wait",
    ])
    run(["/usr/bin/xcrun", "stapler", "staple", str(dmg)])
    run(["/usr/bin/xcrun", "stapler", "validate", str(dmg)])


def create_dmg(app: Path, output: Path, *, should_notarize: bool) -> Path:
    identity = verify_release_app(app)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="whisper_hotkey-dmg-") as temporary:
        staging = Path(temporary) / "whisper_hotkey"
        staging.mkdir()
        run(["/usr/bin/ditto", str(app), str(staging / app.name)])
        (staging / "Applications").symlink_to("/Applications")
        run([
            "/usr/bin/hdiutil",
            "create",
            "-volname",
            "whisper_hotkey",
            "-srcfolder",
            str(staging),
            "-format",
            "UDZO",
            "-ov",
            str(output),
        ])
    run([
        "/usr/bin/codesign",
        "--force",
        "--timestamp",
        "--sign",
        identity,
        str(output),
    ])
    run(["/usr/bin/codesign", "--verify", "--verbose=2", str(output)])
    run(["/usr/bin/hdiutil", "verify", str(output)])
    if should_notarize:
        notarize(output)
        run([
            "/usr/sbin/spctl",
            "--assess",
            "--type",
            "open",
            "--context",
            "context:primary-signature",
            "--verbose=2",
            str(output),
        ])
    checksum = output.with_suffix(f"{output.suffix}.sha256")
    checksum.write_text(f"{sha256(output)}  {output.name}\n", encoding="utf-8")
    return checksum


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--output", type=Path, default=DEFAULT_DMG)
    parser.add_argument(
        "--notarize",
        action="store_true",
        help="submit with notarytool, staple, and run a Gatekeeper assessment",
    )
    args = parser.parse_args()
    checksum = create_dmg(
        args.app.resolve(),
        args.output.resolve(),
        should_notarize=args.notarize,
    )
    print(args.output.resolve())
    print(checksum)


if __name__ == "__main__":
    main()
