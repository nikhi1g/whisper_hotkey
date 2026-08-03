#!/usr/bin/env python3
"""Build and stably sign the local whisper_hotkey application bundle."""

from __future__ import annotations

import hashlib
import os
import plistlib
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
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
BASE_MODEL_NAME = "ggml-base.en.bin"
BASE_MODEL_SHA256 = (
    "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
)


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
        "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": VERSION,
        "LSMinimumSystemVersion": "14.0",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "NSMicrophoneUsageDescription": (
            "whisper_hotkey records only during an active dictation gesture "
            "and transcribes the temporary audio locally."
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
    if os.environ.get("WHISPER_HOTKEY_COREML") == "1":
        (RESOURCES / "CoreMLEnabled").touch()
    write_info_plist()
    write_login_agent_plist()


def bundle_verified_base_model() -> None:
    if os.environ.get("WHISPER_HOTKEY_BUNDLE_MODEL") != "1":
        return
    configured_source = os.environ.get(
        "WHISPER_HOTKEY_BUNDLED_MODEL_PATH",
        "",
    ).strip()
    source = (
        Path(configured_source).expanduser()
        if configured_source
        else Path.home() / ".cache" / "whisper" / BASE_MODEL_NAME
    )
    if not source.is_file():
        raise RuntimeError(
            f"Release model not found at {source}. Run ./run.sh or set "
            "WHISPER_HOTKEY_BUNDLED_MODEL_PATH."
        )
    digest = hashlib.sha256()
    with source.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != BASE_MODEL_SHA256:
        raise RuntimeError(
            f"Refusing to bundle {source}: pinned SHA-256 verification failed."
        )
    destination_directory = RESOURCES / "Models"
    destination_directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination_directory / BASE_MODEL_NAME)


def bundled_dynamic_libraries() -> list[Path]:
    configured_prefixes = [
        os.environ.get("WHISPER_CPP_PREFIX", "").strip(),
        os.environ.get("GGML_PREFIX", "").strip(),
    ]
    prefixes = [Path(value).resolve() for value in configured_prefixes if value]
    homebrew = os.environ.get("HOMEBREW_PREFIX", "").strip()
    allowed_roots = [*prefixes]
    if homebrew:
        allowed_roots.append(Path(homebrew).resolve())
    if not prefixes:
        return []
    helper = MACOS / "WhisperModelHelper"
    pending = [helper]
    copied: dict[Path, Path] = {}
    while pending:
        binary = pending.pop()
        result = subprocess.run(
            ["/usr/bin/otool", "-L", str(binary)],
            capture_output=True,
            text=True,
            check=True,
        )
        for line in result.stdout.splitlines()[1:]:
            dependency_text = line.strip().split(" (", 1)[0]
            if dependency_text.startswith("@rpath/"):
                dependency = next(
                    (
                        prefix / "lib" / Path(dependency_text).name
                        for prefix in prefixes
                        if (prefix / "lib" / Path(dependency_text).name).exists()
                    ),
                    None,
                )
                if dependency is None:
                    continue
            else:
                dependency = Path(dependency_text)
                if not any(
                    dependency.resolve().is_relative_to(prefix)
                    for prefix in allowed_roots
                ):
                    continue
            source = dependency.resolve()
            destination = FRAMEWORKS / Path(dependency_text).name
            if source not in copied:
                shutil.copy2(source, destination)
                destination.chmod(0o755)
                copied[source] = destination
                pending.append(destination)
            run([
                "/usr/bin/install_name_tool",
                "-change",
                dependency_text,
                f"@rpath/{destination.name}",
                str(binary),
            ])
    for library in copied.values():
        run([
            "/usr/bin/install_name_tool",
            "-id",
            f"@rpath/{library.name}",
            str(library),
        ])
    return list(copied.values())


def verify_bundled_dependencies(binaries: list[Path]) -> None:
    failures = []
    for binary in binaries:
        result = subprocess.run(
            ["/usr/bin/otool", "-L", str(binary)],
            capture_output=True,
            text=True,
            check=True,
        )
        for line in result.stdout.splitlines()[1:]:
            dependency = line.strip().split(" (", 1)[0]
            if dependency.startswith("@rpath/"):
                bundled = FRAMEWORKS / Path(dependency).name
                if not bundled.exists():
                    failures.append(f"{binary.name} is missing {dependency}")
            elif dependency.startswith("/") and not dependency.startswith(
                ("/usr/lib/", "/System/Library/")
            ):
                failures.append(f"{binary.name} references {dependency}")
    if failures:
        raise RuntimeError(
            "Application bundle has unresolved dynamic libraries: "
            + "; ".join(failures)
        )


def minimum_macos_version(binary: Path) -> tuple[int, ...] | None:
    result = subprocess.run(
        ["/usr/bin/otool", "-l", str(binary)],
        capture_output=True,
        text=True,
        check=True,
    )
    match = re.search(r"^\s+minos\s+([0-9.]+)$", result.stdout, re.MULTILINE)
    if match is None:
        match = re.search(
            r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([0-9.]+)",
            result.stdout,
        )
    if match is None:
        return None
    return tuple(int(component) for component in match.group(1).split("."))


def verify_distribution_targets(binaries: list[Path]) -> None:
    if os.environ.get("WHISPER_HOTKEY_DISTRIBUTION") != "1":
        return
    incompatible = []
    for binary in binaries:
        minimum = minimum_macos_version(binary)
        if minimum is not None and minimum > (14, 0):
            version = ".".join(str(component) for component in minimum)
            incompatible.append(f"{binary.name} requires macOS {version}")
    if incompatible:
        raise RuntimeError(
            "Distribution contains binaries newer than the declared macOS 14 "
            "minimum: " + "; ".join(incompatible)
        )


def signing_identity() -> str:
    distribution = os.environ.get("WHISPER_HOTKEY_DISTRIBUTION") == "1"
    explicit = os.environ.get("WHISPER_HOTKEY_CODESIGN_IDENTITY", "").strip()
    if explicit:
        if explicit == "-":
            raise RuntimeError(
                "Ad-hoc signing is not supported. Provide a stable code-signing identity."
            )
        if distribution and not explicit.startswith("Developer ID Application:"):
            raise RuntimeError(
                "Distribution requires a Developer ID Application identity."
            )
        return explicit

    result = subprocess.run(
        ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True,
        text=True,
        check=True,
    )
    for line in result.stdout.splitlines():
        if ")" in line and '"' in line:
            if distribution and "Developer ID Application:" not in line:
                continue
            identity_hash = line.split(")", 1)[1].strip().split(maxsplit=1)[0]
            if identity_hash:
                return identity_hash
    if distribution:
        raise RuntimeError(
            "No Developer ID Application identity found for distribution."
        )
    raise RuntimeError(
        "No stable code-signing identity found. Run ./run.sh to create the local "
        "development identity, install an Apple Development or Developer ID "
        "Application certificate, or set WHISPER_HOTKEY_CODESIGN_IDENTITY. "
        "Ad-hoc signing is intentionally refused."
    )


def sign(identity: str, libraries: list[Path]) -> None:
    distribution = os.environ.get("WHISPER_HOTKEY_DISTRIBUTION") == "1"
    targets = [
        *((library, None) for library in libraries),
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
        ]
        if distribution:
            command.extend(["--timestamp", "--options", "runtime"])
        else:
            command.append("--timestamp=none")
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
    bundle_verified_base_model()
    libraries = bundled_dynamic_libraries()
    verify_bundled_dependencies([
        *libraries,
        MACOS / "WhisperModelHelper",
    ])
    verify_distribution_targets([
        *libraries,
        MACOS / "WhisperHotkeyApp",
        MACOS / "WhisperModelHelper",
        MACOS / LOGIN_LAUNCHER_NAME,
        DIST / "whisper_hotkey",
    ])
    identity = signing_identity()
    sign(identity, libraries)
    print(APP)


if __name__ == "__main__":
    main()
