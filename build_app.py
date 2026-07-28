#!/usr/bin/env python3
"""Build and stably sign the local whisper_hotkey application bundle."""

from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "Assets"
DIST = ROOT / "dist"
APP = DIST / "whisper_hotkey.app"
CONTENTS = APP / "Contents"
MACOS = CONTENTS / "MacOS"
RESOURCES = CONTENTS / "Resources"
FRAMEWORKS = CONTENTS / "Frameworks"
LAUNCH_AGENTS = CONTENTS / "Library" / "LaunchAgents"
BUNDLE_ID = "local.whisperhotkey.app"
LOGIN_LAUNCHER_NAME = "WhisperHotkeyLoginLauncher"
LOGIN_AGENT_LABEL = f"{BUNDLE_ID}.login-launcher"
LOGIN_AGENT_PLIST_NAME = f"{LOGIN_AGENT_LABEL}.plist"
LOGIN_AGENT_BUNDLE_PROGRAM = f"Contents/MacOS/{LOGIN_LAUNCHER_NAME}"


def run(command: list[str], *, cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    subprocess.run(command, cwd=cwd, env=env, check=True)


def swift_build() -> Path:
    module_cache = ROOT / ".build" / "module-cache"
    module_cache.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(module_cache)
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(module_cache)
    run(["swift", "build", "-c", "release"], env=environment)
    return ROOT / ".build" / "release"


def write_info_plist() -> None:
    plist = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": "WhisperHotkeyApp",
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "whisper_hotkey",
        "CFBundleDisplayName": "whisper_hotkey",
        "CFBundleIconFile": "AppIcon",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "14.0",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "NSMicrophoneUsageDescription": (
            "whisper_hotkey records only while Right Command is held and "
            "transcribes the temporary audio locally."
        ),
    }
    with (CONTENTS / "Info.plist").open("wb") as handle:
        plistlib.dump(plist, handle)


def write_login_agent_plist() -> None:
    plist = {
        "Label": LOGIN_AGENT_LABEL,
        "BundleProgram": LOGIN_AGENT_BUNDLE_PROGRAM,
        "RunAtLoad": True,
    }
    path = LAUNCH_AGENTS / LOGIN_AGENT_PLIST_NAME
    with path.open("wb") as handle:
        plistlib.dump(plist, handle, fmt=plistlib.FMT_XML, sort_keys=False)
    path.chmod(0o600)


def bundle(products: Path) -> None:
    if APP.exists():
        shutil.rmtree(APP)
    for directory in (MACOS, RESOURCES, FRAMEWORKS, LAUNCH_AGENTS):
        directory.mkdir(parents=True, exist_ok=True)

    shutil.copy2(products / "WhisperHotkeyApp", MACOS / "WhisperHotkeyApp")
    # CFBundleCopyAuxiliaryExecutableURL searches Contents/MacOS.
    shutil.copy2(products / "WhisperModelHelper", MACOS / "WhisperModelHelper")
    shutil.copy2(products / LOGIN_LAUNCHER_NAME, MACOS / LOGIN_LAUNCHER_NAME)
    shutil.copy2(products / "whisper_hotkey", DIST / "whisper_hotkey")
    shutil.copy2(ROOT / "purpose.md", RESOURCES / "purpose.md")
    shutil.copy2(ASSETS / "AppIcon.icns", RESOURCES / "AppIcon.icns")
    write_info_plist()
    write_login_agent_plist()


def signing_identity() -> str:
    explicit = os.environ.get("WHISPER_HOTKEY_CODESIGN_IDENTITY", "").strip()
    if explicit:
        return explicit

    result = subprocess.run(
        ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True,
        text=True,
        check=True,
    )
    for line in result.stdout.splitlines():
        if ")" in line and '"' in line:
            return line.split('"', 2)[1]
    raise RuntimeError(
        "No stable code-signing identity found. Create an Apple Development or "
        "Developer ID Application certificate, or set "
        "WHISPER_HOTKEY_CODESIGN_IDENTITY. Ad-hoc signing is intentionally refused."
    )


def sign(identity: str) -> None:
    targets = [
        (MACOS / "WhisperModelHelper", None),
        (MACOS / LOGIN_LAUNCHER_NAME, LOGIN_AGENT_LABEL),
        (DIST / "whisper_hotkey", None),
        (APP, BUNDLE_ID),
    ]
    for target, identifier in targets:
        command = [
            "/usr/bin/codesign",
            "--force",
            "--sign",
            identity,
            "--timestamp=none",
        ]
        if identifier:
            command.extend(["--identifier", identifier])
        command.append(str(target))
        run(command)

    run([
        "/usr/bin/codesign",
        "--verify",
        "--strict",
        "--verbose=2",
        str(MACOS / LOGIN_LAUNCHER_NAME),
    ])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(APP)])


def main() -> None:
    products = swift_build()
    DIST.mkdir(parents=True, exist_ok=True)
    bundle(products)
    identity = signing_identity()
    sign(identity)
    print(APP)


if __name__ == "__main__":
    main()
