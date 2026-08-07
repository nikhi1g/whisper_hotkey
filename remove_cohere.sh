#!/bin/bash
#
# Removes the Cohere Transcribe engine and ships it as 3.5.9.
#
# The code change is already prepared on the `remove-cohere` branch and is
# not merged. This script merges it, bumps the version, runs the tests,
# builds, installs over /Applications, and deletes the 2.3 GB checkpoint from
# the FluidAudio cache.
#
# It stops at the first failure and does not push anything. Pass --release to
# also tag, push, and publish the GitHub release once everything else passed.
#
# Nothing here is irreversible until --release: the merge is a local commit
# you can `git reset --hard origin/main` away, and the only deleted file is a
# re-downloadable model cache.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH="remove-cohere"
VERSION="3.5.9"
TAG="v${VERSION}"
COHERE_CACHE="${HOME}/Library/Application Support/FluidAudio/Models/cohere-transcribe"
INSTALLED_APP="/Applications/whisper_hotkey.app"
DO_RELEASE=0

[[ "${1:-}" == "--release" ]] && DO_RELEASE=1

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

cd "$ROOT"

# --- Preconditions ---------------------------------------------------------

[[ -z "$(/usr/bin/git status --porcelain)" ]] \
    || die "working tree is dirty; commit or stash first"

[[ "$(/usr/bin/git rev-parse --abbrev-ref HEAD)" == "main" ]] \
    || die "not on main"

/usr/bin/git rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
    || die "the prepared branch '$BRANCH' does not exist"

# --- 1. Merge --------------------------------------------------------------

note "Merging $BRANCH into main"
/usr/bin/git merge --no-ff "$BRANCH" -m "Merge $BRANCH: remove the Cohere Transcribe engine"

# --- 2. Version and notes --------------------------------------------------

note "Setting version to $VERSION"
printf '%s\n' "$VERSION" > VERSION

/usr/bin/python3 - "$VERSION" <<'PY'
import sys, datetime, pathlib

version = sys.argv[1]
today = datetime.date.today().isoformat()

entry = f"""# Changelog

## {version}: {today}

- Removed the Cohere Transcribe engine. On this repository's own corpus it won
  exactly one measurement -- clean read speech, 1.13% word error rate against
  Parakeet Unified's 1.44% -- while losing every other axis: 4.21% against
  3.63% on noisy speech, 629 ms against 50 ms mean latency, and a 2.4 GB
  download against 594 MB
- Migrated a saved `cohereCoreML` selection to Parakeet Accurate, which is
  bundled and beats Cohere everywhere except clean read speech
- Dropped the Cohere runtime, installer, download offer, progress panel, and
  the `--engine cohere` option in run.sh

"""

changelog = pathlib.Path("CHANGELOG.md")
changelog.write_text(
    changelog.read_text().replace("# Changelog\n\n", entry, 1)
)

notes = f"""Version {version} removes the Cohere Transcribe engine.

Cohere was added in 3.5.0 as the highest-ranked permissively licensed model
with an existing Apple Silicon path. Measured on this repository's own corpus
rather than on a leaderboard, it won exactly one comparison:

| Engine | test-clean | test-other | Combined | Mean latency | Size |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cohere Transcribe | 1.13% | 4.21% | 2.57% | 629 ms | 2.4 GB |
| Parakeet Unified | 1.44% | 3.63% | 2.46% | 50 ms | 594 MB |

It is better on clean read speech and worse on everything else: noisy speech,
combined accuracy, latency by a factor of twelve, and download size by a
factor of four. One narrow win does not earn a permanent entry in a list that
every user has to read.

A saved Cohere selection migrates to Parakeet Accurate. Nothing else changes,
and the 2.4 GB checkpoint can be deleted from
~/Library/Application Support/FluidAudio/Models/cohere-transcribe.

The app is signed with a stable Apple Development identity and is not
notarized, so the first launch still needs one approval through System
Settings > Privacy & Security > Open Anyway. Audio and transcripts remain
local, and every bundled Whisper model is verified against a pinned SHA-256.
"""

pathlib.Path("RELEASE_NOTES.md").write_text(notes)
pathlib.Path(f"docs/releases/{version}.md").write_text(notes)
PY

/usr/bin/git add -A
/usr/bin/git commit -q -m "release: prepare ${VERSION}"

# --- 3. Verify -------------------------------------------------------------

note "Running the Swift test suite"
/usr/bin/swift test 2>&1 | /usr/bin/tail -3

note "Running the bootstrap tests"
/usr/bin/python3 Tests/BootstrapTests/test_run_sh.py 2>&1 | /usr/bin/tail -3

# --- 4. Build and install --------------------------------------------------

note "Building the app bundle"
WHISPER_HOTKEY_BUNDLE_MODEL=1 /usr/bin/python3 build_app.py >/dev/null

built="$(
    /usr/bin/defaults read \
        "${ROOT}/dist/whisper_hotkey.app/Contents/Info.plist" \
        CFBundleShortVersionString
)"
[[ "$built" == "$VERSION" ]] \
    || die "built bundle reports $built, expected $VERSION"

if [[ -x "${HOME}/bin/whisper_hotkey" ]]; then
    note "Stopping the running app"
    "${HOME}/bin/whisper_hotkey" stop >/dev/null 2>&1 || true
    /bin/sleep 1
fi

note "Installing $VERSION into /Applications"
/bin/rm -rf "$INSTALLED_APP"
/bin/cp -R "${ROOT}/dist/whisper_hotkey.app" /Applications/

# --- 5. Reclaim the checkpoint ---------------------------------------------

if [[ -d "$COHERE_CACHE" ]]; then
    note "Removing the Cohere checkpoint ($(
        /usr/bin/du -sh "$COHERE_CACHE" | /usr/bin/awk '{print $1}'
    ))"
    /bin/rm -rf "$COHERE_CACHE"
else
    note "No Cohere checkpoint on disk"
fi

# --- 6. Release (opt-in) ---------------------------------------------------

if [[ "$DO_RELEASE" -eq 1 ]]; then
    note "Pushing main and tagging $TAG"
    /usr/bin/git push origin main
    /usr/bin/git tag -a "$TAG" -m "whisper_hotkey ${VERSION}"
    /usr/bin/git push origin "$TAG"

    note "Packaging release assets"
    /bin/rm -rf "${ROOT}/dist/release"
    /usr/bin/python3 tools/package_release.py "$TAG" >/dev/null
    /usr/bin/python3 tools/package_dmg.py --unnotarized >/dev/null

    note "Publishing the GitHub release (this uploads ~2.7 GB)"
    gh release create "$TAG" \
        --title "whisper_hotkey ${VERSION}" \
        --notes-file RELEASE_NOTES.md \
        "${ROOT}"/dist/release/*
else
    note "Local only. Nothing pushed."
    printf '    Re-run with --release to tag, push, and publish.\n'
    printf '    To undo: git reset --hard origin/main\n'
fi

note "Launching whisper_hotkey"
/usr/bin/open -a "$INSTALLED_APP"

note "Done"
