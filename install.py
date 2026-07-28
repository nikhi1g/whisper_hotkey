#!/usr/bin/env python3
"""Install an already-built whisper_hotkey bundle and terminal controller."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
BUILT_APP = ROOT / "dist" / "whisper_hotkey.app"
BUILT_CLI = ROOT / "dist" / "whisper_hotkey"
INSTALLED_APP = Path("/Applications/whisper_hotkey.app")
INSTALLED_CLI = Path.home() / "bin" / "whisper_hotkey"


def validate() -> None:
    if not BUILT_APP.is_dir() or not BUILT_CLI.is_file():
        raise FileNotFoundError("Run python3 build_app.py before installation.")
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(BUILT_APP)],
        check=True,
    )


def install() -> None:
    validate()
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

    subprocess.run(["/usr/bin/open", "-gj", str(INSTALLED_APP)], check=True)
    print(INSTALLED_APP)
    print(INSTALLED_CLI)


if __name__ == "__main__":
    install()
