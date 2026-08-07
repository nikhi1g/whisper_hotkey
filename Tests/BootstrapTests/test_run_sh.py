from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
RUN_SH = ROOT / "run.sh"
sys.path.insert(0, str(ROOT))

import build_app  # noqa: E402


class RunScriptTests(unittest.TestCase):
    def run_script(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(RUN_SH), *arguments],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def evaluate_bootstrap_function(self, expression: str) -> str:
        source = RUN_SH.read_text(encoding="utf-8")
        functions = source.split('while [[ $# -gt 0 ]]', maxsplit=1)[0]
        result = subprocess.run(
            ["/bin/bash", "-c", f"{functions}\n{expression}"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()

    def test_script_has_valid_bash_syntax(self) -> None:
        result = subprocess.run(
            ["/bin/bash", "-n", str(RUN_SH)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_help_describes_one_command_bootstrap_and_selection(self) -> None:
        result = self.run_script("--help")

        self.assertEqual(result.returncode, 0)
        self.assertIn("Install and select one model", result.stdout)
        self.assertIn("Missing Homebrew and signing setup", result.stdout)
        self.assertIn("At least one verified model is ready", result.stdout)
        self.assertIn("stays open until the complete macOS setup", result.stdout)
        self.assertEqual(result.stderr, "")

    def test_unknown_model_fails_before_bootstrap_changes(self) -> None:
        result = self.run_script("--model", "unknown")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("error: unknown model: unknown", result.stderr)

    def test_model_and_engine_options_match_swift_preference_values(self) -> None:
        models = self.evaluate_bootstrap_function(
            "for value in base turbo; do model_preference \"$value\"; done"
        )
        engines = self.evaluate_bootstrap_function(
            "for value in metal parakeet; do engine_preference \"$value\"; done"
        )

        self.assertEqual(
            models.splitlines(),
            ["baseEnglish", "largeV3TurboQ5"],
        )
        self.assertEqual(
            engines.splitlines(),
            [
                "whisperCppMetal",
                "parakeetCoreML",
            ],
        )

    def test_default_selection_persistence_is_a_successful_no_op(self) -> None:
        result = self.evaluate_bootstrap_function(
            "SELECTION_WAS_REQUESTED=0; persist_requested_selection; printf done"
        )

        self.assertEqual(result, "done")

    def test_build_refuses_explicit_ad_hoc_signing(self) -> None:
        with patch.dict(
            "os.environ",
            {"WHISPER_HOTKEY_CODESIGN_IDENTITY": "-"},
            clear=True,
        ):
            with self.assertRaisesRegex(RuntimeError, "explicitly opted-in preview"):
                build_app.signing_identity()

    def test_preview_explicitly_allows_ad_hoc_signing(self) -> None:
        with patch.dict(
            "os.environ",
            {
                "WHISPER_HOTKEY_CODESIGN_IDENTITY": "-",
                "WHISPER_HOTKEY_PREVIEW": "1",
            },
            clear=True,
        ):
            self.assertEqual(build_app.signing_identity(), "-")

    def test_distribution_refuses_non_developer_id_identity(self) -> None:
        with patch.dict(
            "os.environ",
            {
                "WHISPER_HOTKEY_CODESIGN_IDENTITY": "Apple Development: Local",
                "WHISPER_HOTKEY_DISTRIBUTION": "1",
            },
            clear=False,
        ):
            with self.assertRaisesRegex(RuntimeError, "Developer ID Application"):
                build_app.signing_identity()

    def test_automatic_signing_uses_unique_certificate_hash(self) -> None:
        identity_output = (
            '  1) ABCDEF123456 "Apple Development: Duplicate Name"\n'
            '  2) 0123456789AB "Apple Development: Duplicate Name"\n'
        )
        result = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout=identity_output,
            stderr="",
        )
        with (
            patch.dict("os.environ", {}, clear=True),
            patch.object(build_app.subprocess, "run", return_value=result),
        ):
            self.assertEqual(build_app.signing_identity(), "ABCDEF123456")

    def test_distribution_rejects_binary_newer_than_macos_14(self) -> None:
        result = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout="cmd LC_BUILD_VERSION\n  cmdsize 32\n platform 1\n    minos 15.0\n      sdk 15.0\n",
            stderr="",
        )
        with (
            patch.dict(
                "os.environ",
                {"WHISPER_HOTKEY_DISTRIBUTION": "1"},
                clear=False,
            ),
            patch.object(build_app.subprocess, "run", return_value=result),
        ):
            with self.assertRaisesRegex(RuntimeError, "requires macOS 15.0"):
                build_app.verify_distribution_targets([Path("helper")])

    def test_release_build_bundles_only_a_pinned_model(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / build_app.BASE_MODEL_NAME
            resources = root / "Resources"
            source.write_bytes(b"verified model fixture")
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            with (
                patch.object(build_app, "RESOURCES", resources),
                patch.object(build_app, "BASE_MODEL_SHA256", digest),
                # Only the fixture is on disk, so restrict the bundle set to it
                # rather than requiring a populated model cache.
                patch.object(
                    build_app,
                    "BUNDLED_MODELS",
                    {build_app.BASE_MODEL_NAME: digest},
                ),
                patch.dict(
                    "os.environ",
                    {
                        "WHISPER_HOTKEY_BUNDLE_MODEL": "1",
                        "WHISPER_HOTKEY_BUNDLED_MODEL_PATH": str(source),
                    },
                    clear=False,
                ),
            ):
                build_app.bundle_verified_models()

            bundled = resources / "Models" / build_app.BASE_MODEL_NAME
            self.assertEqual(bundled.read_bytes(), source.read_bytes())

    def test_release_build_rejects_mismatched_model(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / build_app.BASE_MODEL_NAME
            source.write_bytes(b"wrong model")
            with (
                patch.object(build_app, "RESOURCES", root / "Resources"),
                patch.object(
                    build_app,
                    "BUNDLED_MODELS",
                    {build_app.BASE_MODEL_NAME: build_app.BASE_MODEL_SHA256},
                ),
                patch.dict(
                    "os.environ",
                    {
                        "WHISPER_HOTKEY_BUNDLE_MODEL": "1",
                        "WHISPER_HOTKEY_BUNDLED_MODEL_PATH": str(source),
                    },
                    clear=False,
                ),
            ):
                with self.assertRaisesRegex(RuntimeError, "verification failed"):
                    build_app.bundle_verified_models()


if __name__ == "__main__":
    unittest.main()
