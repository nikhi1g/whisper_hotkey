#!/usr/bin/env python3
"""Create and verify the release, unnotarized-release, or preview DMG.

Exactly one channel must be requested, so an artifact can never be published
under the public release name without stating how it was signed:

  --notarize    Developer ID Application, submitted to Apple and stapled.
  --unnotarized Stable named identity, no Apple ticket. Gatekeeper blocks the
                first launch until the user chooses Open Anyway.
  --preview     Ad-hoc signature only, published under a preview asset name.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

# Imported rather than duplicated. A copy of this list drifted out of step with
# build_app.py the moment a model was retired, and the release only failed at
# packaging time, after the tag was already pushed.
from build_app import (  # noqa: E402
    BUNDLED_MODELS,
    BUNDLED_PARAKEET_MODELS,
)
DEFAULT_APP = ROOT / "dist" / "whisper_hotkey.app"
DEFAULT_DMG = ROOT / "dist" / "release" / "whisper_hotkey.dmg"


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


def verify_release_app(app: Path, *, channel: str) -> str:
    if not app.is_dir():
        raise RuntimeError(f"Application bundle not found at {app}")
    models = app / "Contents" / "Resources" / "Models"
    for name, expected in BUNDLED_MODELS.items():
        model = models / name
        if not model.is_file() or sha256(model) != expected:
            raise RuntimeError(
                f"The release app must contain the pinned, verified {name}."
            )
    # Parakeet checkpoints are directories of compiled Core ML models whose
    # layout FluidAudio owns, so they are verified by presence rather than by a
    # digest this project does not control.
    parakeet = app / "Contents" / "Resources" / "ParakeetModels"
    for name in BUNDLED_PARAKEET_MODELS:
        if not (parakeet / name).is_dir():
            raise RuntimeError(
                f"The release app must contain the bundled {name} checkpoint."
            )
    result = subprocess.run(
        ["/usr/bin/codesign", "--display", "--verbose=4", str(app)],
        check=True,
        text=True,
        capture_output=True,
    )
    details = f"{result.stdout}\n{result.stderr}"
    authority = re.search(r"^Authority=(.+)$", details, re.M)
    adhoc = re.search(r"^Signature=adhoc$", details, re.M) is not None
    if channel == "preview":
        if not adhoc or authority is not None:
            raise RuntimeError(
                "A preview DMG accepts only an ad-hoc signature. An app signed "
                "by a named identity belongs in --notarize or --unnotarized."
            )
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
        return "-"
    if authority is None:
        raise RuntimeError(
            "The DMG requires a signed app with a named code-signing authority."
        )
    if channel == "notarize" and not authority.group(1).startswith(
        "Developer ID Application:"
    ):
        raise RuntimeError(
            "The notarized DMG requires a Developer ID Application-signed app."
        )
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    with tempfile.TemporaryDirectory(
        prefix="whisper-hotkey-signing-certificate-"
    ) as temporary:
        certificate_prefix = Path(temporary) / "certificate"
        run([
            "/usr/bin/codesign",
            "--display",
            f"--extract-certificates={certificate_prefix}",
            str(app),
        ])
        leaf_certificate = Path(f"{certificate_prefix}0")
        if not leaf_certificate.is_file():
            raise RuntimeError(
                "Could not resolve the app's exact signing certificate."
            )
        return hashlib.sha1(leaf_certificate.read_bytes()).hexdigest()


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


def create_dmg(app: Path, output: Path, *, channel: str) -> Path:
    preview = channel == "preview"
    if preview and output.name == DEFAULT_DMG.name:
        raise RuntimeError(
            f"A preview build must not be written as {DEFAULT_DMG.name}; that "
            "asset name is what the product page and the in-app updater fetch."
        )
    identity = verify_release_app(app, channel=channel)
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
    signing_command = [
        "/usr/bin/codesign",
        "--force",
        "--timestamp=none" if preview else "--timestamp",
        "--sign",
        identity,
        str(output),
    ]
    run(signing_command)
    run(["/usr/bin/codesign", "--verify", "--verbose=2", str(output)])
    run(["/usr/bin/hdiutil", "verify", str(output)])
    if channel == "notarize":
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
    channels = parser.add_mutually_exclusive_group(required=True)
    channels.add_argument(
        "--notarize",
        dest="channel",
        action="store_const",
        const="notarize",
        help="submit with notarytool, staple, and run a Gatekeeper assessment",
    )
    channels.add_argument(
        "--unnotarized",
        dest="channel",
        action="store_const",
        const="unnotarized",
        help="publish a stably signed release that Apple has not notarized",
    )
    channels.add_argument(
        "--preview",
        dest="channel",
        action="store_const",
        const="preview",
        help="allow an explicitly labeled, ad-hoc-signed preview app",
    )
    args = parser.parse_args()
    checksum = create_dmg(
        args.app.resolve(),
        args.output.resolve(),
        channel=args.channel,
    )
    print(args.output.resolve())
    print(checksum)


if __name__ == "__main__":
    main()
