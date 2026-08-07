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
# Every model the first-run profile can select on its own, so no Mac starts on
# a model it does not have. Medium is deliberately absent: it is never chosen
# automatically, and all four together exceed the 2 GB release-asset limit.
BUNDLED_MODELS: dict[str, str] = {
    BASE_MODEL_NAME: BASE_MODEL_SHA256,
    "ggml-large-v3-turbo-q5_0.bin":
        "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
}

# Parakeet checkpoints ship inside the app as of 3.4.0, so the best engine is
# available on a fresh install with no download. Copied from FluidAudio's cache
# directory, which is where run.sh and the app both put them.
PARAKEET_CACHE = (
    Path.home() / "Library" / "Application Support" / "FluidAudio" / "Models"
)
BUNDLED_PARAKEET_MODELS: tuple[str, ...] = (
    "parakeet-tdt-ctc-110m",
    "parakeet-tdt-0.6b-v2",
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
    write_info_plist()
    write_login_agent_plist()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bundle_verified_models() -> None:
    if os.environ.get("WHISPER_HOTKEY_BUNDLE_MODEL") != "1":
        return
    configured_base = os.environ.get(
        "WHISPER_HOTKEY_BUNDLED_MODEL_PATH",
        "",
    ).strip()
    cache = Path.home() / ".cache" / "whisper"
    destination_directory = RESOURCES / "Models"
    destination_directory.mkdir(parents=True, exist_ok=True)
    for name, expected in BUNDLED_MODELS.items():
        source = (
            Path(configured_base).expanduser()
            if configured_base and name == BASE_MODEL_NAME
            else cache / name
        )
        if not source.is_file():
            raise RuntimeError(
                f"Release model not found at {source}. Run ./run.sh to "
                "download and verify every bundled model."
            )
        if file_sha256(source) != expected:
            raise RuntimeError(
                f"Refusing to bundle {source}: pinned SHA-256 verification "
                "failed."
            )
        shutil.copy2(source, destination_directory / name)


def bundle_parakeet_models() -> None:
    """Copy the Parakeet checkpoints into the app bundle.

    Kept separate from bundle_verified_models so each does one job: the whisper
    models are verified by pinned digest, these are verified by presence.

    These are directories of compiled Core ML models rather than single files,
    and FluidAudio owns their layout, so they are copied wholesale and verified
    by presence rather than by a digest we do not control.
    """
    if os.environ.get("WHISPER_HOTKEY_BUNDLE_MODEL") != "1":
        return
    destination_directory = RESOURCES / "ParakeetModels"
    destination_directory.mkdir(parents=True, exist_ok=True)
    for name in BUNDLED_PARAKEET_MODELS:
        source = PARAKEET_CACHE / name
        if not source.is_dir():
            raise RuntimeError(
                f"Parakeet checkpoint not found at {source}. Run ./run.sh to "
                "download every bundled model."
            )
        target = destination_directory / name
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(source, target)


def dependency_prefix(environment_key: str, formula: str) -> Path | None:
    configured = os.environ.get(environment_key, "").strip()
    if configured:
        return Path(configured).resolve()

    brew = shutil.which("brew")
    if brew is None:
        return None
    result = subprocess.run(
        [brew, "--prefix", formula],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return Path(result.stdout.strip()).resolve()


def bundled_dynamic_libraries() -> list[Path]:
    discovered_prefixes = [
        dependency_prefix("WHISPER_CPP_PREFIX", "whisper-cpp"),
        dependency_prefix("GGML_PREFIX", "ggml"),
    ]
    prefixes = [prefix for prefix in discovered_prefixes if prefix is not None]
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


def unnotarized_distribution() -> bool:
    """Public build signed with a development identity and never notarized.

    Notarization requires a Developer ID Application certificate, which in turn
    requires a paid Apple Developer Program membership. Without one, the app is
    signed with the same stable Apple Development identity on every release so
    that existing installs keep their designated requirement (in-app updates)
    and their Microphone, Accessibility, and Input Monitoring grants. Gatekeeper
    still blocks the first launch; the download instructions cover Open Anyway.
    """
    return (
        os.environ.get("WHISPER_HOTKEY_DISTRIBUTION") == "1"
        and os.environ.get("WHISPER_HOTKEY_UNNOTARIZED") == "1"
    )


def distribution_identity_prefixes() -> tuple[str, ...]:
    if unnotarized_distribution():
        return ("Developer ID Application:", "Apple Development:")
    return ("Developer ID Application:",)


def signing_identity() -> str:
    distribution = os.environ.get("WHISPER_HOTKEY_DISTRIBUTION") == "1"
    preview = os.environ.get("WHISPER_HOTKEY_PREVIEW") == "1"
    prefixes = distribution_identity_prefixes()
    explicit = os.environ.get("WHISPER_HOTKEY_CODESIGN_IDENTITY", "").strip()
    if explicit:
        if explicit == "-":
            if preview and not distribution:
                return explicit
            raise RuntimeError(
                "Ad-hoc signing is supported only for an explicitly opted-in "
                "preview build. Provide a stable code-signing identity."
            )
        if distribution and not explicit.startswith(prefixes):
            raise RuntimeError(
                "Distribution requires one of these identities: "
                + ", ".join(prefixes)
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
            if distribution and not any(prefix in line for prefix in prefixes):
                continue
            identity_hash = line.split(")", 1)[1].strip().split(maxsplit=1)[0]
            if identity_hash:
                return identity_hash
    if distribution:
        raise RuntimeError(
            "No distribution identity found. Expected one of: "
            + ", ".join(prefixes)
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
            command.append("--timestamp")
            if not unnotarized_distribution():
                # The hardened runtime is a notarization prerequisite. Enabling
                # it without notarization would only add entitlement
                # requirements for microphone access and library loading.
                command.extend(["--options", "runtime"])
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
    bundle_verified_models()
    bundle_parakeet_models()
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
