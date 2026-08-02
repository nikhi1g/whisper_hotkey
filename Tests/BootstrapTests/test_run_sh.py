from __future__ import annotations

import subprocess
import sys
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
            "for value in base small medium turbo; do model_preference \"$value\"; done"
        )
        engines = self.evaluate_bootstrap_function(
            "for value in metal coreml whisperkit; do engine_preference \"$value\"; done"
        )

        self.assertEqual(
            models.splitlines(),
            ["baseEnglish", "smallEnglish", "mediumEnglish", "largeV3TurboQ5"],
        )
        self.assertEqual(
            engines.splitlines(),
            ["whisperCppMetal", "whisperCppCoreML", "whisperKitCoreML"],
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
            clear=False,
        ):
            with self.assertRaisesRegex(RuntimeError, "Ad-hoc signing is not supported"):
                build_app.signing_identity()


if __name__ == "__main__":
    unittest.main()
