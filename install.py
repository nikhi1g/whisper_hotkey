#!/usr/bin/env python3
"""Install an already-built whisper_hotkey bundle and terminal controller."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
BUILT_APP = ROOT / "dist" / "whisper_hotkey.app"
BUILT_CLI = ROOT / "dist" / "whisper_hotkey"
INSTALLED_APP = Path("/Applications/whisper_hotkey.app")
INSTALLED_CLI = Path.home() / "bin" / "whisper_hotkey"
INSTALLED_EXECUTABLE = INSTALLED_APP / "Contents/MacOS/WhisperHotkeyApp"


def validate() -> None:
    if not BUILT_APP.is_dir() or not BUILT_CLI.is_file():
        raise FileNotFoundError("Run python3 build_app.py before installation.")
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(BUILT_APP)],
        check=True,
    )


def running_pids() -> list[int]:
    result = subprocess.run(
        [
            "/usr/bin/pgrep",
            "-f",
            f"^{re.escape(str(INSTALLED_EXECUTABLE))}$",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode == 1:
        return []
    if result.returncode != 0:
        raise RuntimeError(f"Could not inspect the running app: {result.stderr.strip()}")
    return [int(line) for line in result.stdout.splitlines() if line.strip()]


def stop_running_app() -> None:
    if not running_pids():
        return

    result = subprocess.run(
        [str(BUILT_CLI), "stop"],
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            "The installed app is running but could not be stopped safely"
            + (f": {detail}" if detail else ".")
        )

    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if not running_pids():
            return
        time.sleep(0.05)
    raise RuntimeError("The installed app did not finish stopping within five seconds.")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_installation() -> None:
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(INSTALLED_APP)],
        check=True,
    )
    built_executable = BUILT_APP / "Contents/MacOS/WhisperHotkeyApp"
    if sha256(built_executable) != sha256(INSTALLED_EXECUTABLE):
        raise RuntimeError("Built and installed app executables do not match.")
    if sha256(BUILT_CLI) != sha256(INSTALLED_CLI):
        raise RuntimeError("Built and installed terminal controllers do not match.")


def launch_and_verify() -> None:
    subprocess.run(["/usr/bin/open", "-gj", str(INSTALLED_APP)], check=True)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if running_pids():
            return
        time.sleep(0.05)
    raise RuntimeError(
        "The installed app did not launch from /Applications within five seconds."
    )


def install() -> None:
    validate()
    stop_running_app()
    if INSTALLED_APP.exists():
        backup = Path("/private/tmp") / f"whisper_hotkey.app.backup-{os.getpid()}"
        if backup.exists():
            shutil.rmtree(backup)
        shutil.move(INSTALLED_APP, backup)
        try:
            shutil.copytree(BUILT_APP, INSTALLED_APP, symlinks=True)
        except BaseException:
            if INSTALLED_APP.exists():
                shutil.rmtree(INSTALLED_APP)
            shutil.move(backup, INSTALLED_APP)
            raise
        shutil.rmtree(backup)
    else:
        shutil.copytree(BUILT_APP, INSTALLED_APP, symlinks=True)

    INSTALLED_CLI.parent.mkdir(parents=True, exist_ok=True)
    temporary_cli = INSTALLED_CLI.with_suffix(".new")
    shutil.copy2(BUILT_CLI, temporary_cli)
    temporary_cli.chmod(0o755)
    os.replace(temporary_cli, INSTALLED_CLI)

    verify_installation()
    launch_and_verify()
    print(INSTALLED_APP)
    print(INSTALLED_CLI)


if __name__ == "__main__":
    install()
