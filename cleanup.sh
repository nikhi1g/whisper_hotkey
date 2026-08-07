#!/bin/bash
#
# One-off maintenance for the 3.5.7 engine prune.
#
# 1. Installs the freshly built bundle from dist/ over /Applications.
# 2. Deletes the cache artifacts left behind by the retired Core ML encoder
#    and WhisperKit engines and by the Small/Medium models retired in 3.4.1.
#
# Safe to re-run: every step checks before it acts, and nothing that is still
# reachable from the app is touched.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_APP="${ROOT}/dist/whisper_hotkey.app"
INSTALLED_APP="/Applications/whisper_hotkey.app"
CACHE_DIR="${HOME}/.cache/whisper"

# Retired with the engines they served. The two ggml bins that remain --
# ggml-base.en.bin (discovery fallback) and ggml-large-v3-turbo-q5_0.bin
# (Whisper Turbo) -- are deliberately absent from this list.
DEAD_PATHS=(
    "${CACHE_DIR}/coreml"
    "${CACHE_DIR}/ggml-large-v3-turbo-encoder.mlmodelc.zip"
    "${CACHE_DIR}/ggml-medium.en.bin"
    "${CACHE_DIR}/ggml-small.en.bin"
    "${HOME}/.cache/whisperkit"
)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

# --- 1. Install ------------------------------------------------------------

[[ -d "$SOURCE_APP" ]] \
    || die "no build at $SOURCE_APP; run: python3 build_app.py"

/usr/bin/codesign --verify --deep --strict "$SOURCE_APP" >/dev/null 2>&1 \
    || die "the build at $SOURCE_APP is not validly signed"

version="$(
    /usr/bin/defaults read \
        "${SOURCE_APP}/Contents/Info.plist" CFBundleShortVersionString \
        2>/dev/null || echo unknown
)"

if [[ -x "${HOME}/bin/whisper_hotkey" ]]; then
    note "Stopping the running app"
    "${HOME}/bin/whisper_hotkey" stop >/dev/null 2>&1 || true
    /bin/sleep 1
fi

if [[ -d "$INSTALLED_APP" ]]; then
    note "Removing the previous install"
    /bin/rm -rf "$INSTALLED_APP"
fi

note "Installing whisper_hotkey $version into /Applications"
/bin/cp -R "$SOURCE_APP" /Applications/

# --- 2. Cache cleanup ------------------------------------------------------

reclaimed=0
for path in "${DEAD_PATHS[@]}"; do
    [[ -e "$path" ]] || continue
    size="$(/usr/bin/du -sk "$path" | /usr/bin/awk '{print $1}')"
    reclaimed=$((reclaimed + size))
    note "Removing $(/usr/bin/basename "$path") ($(
        /usr/bin/du -sh "$path" | /usr/bin/awk '{print $1}'
    ))"
    /bin/rm -rf "$path"
done

if [[ "$reclaimed" -gt 0 ]]; then
    note "Reclaimed $((reclaimed / 1024)) MB"
else
    note "Cache already clean"
fi

if [[ -d "$CACHE_DIR" ]]; then
    note "Remaining in ${CACHE_DIR}:"
    /bin/ls -1 "$CACHE_DIR" | /usr/bin/sed 's/^/    /'
fi

# --- 3. Launch -------------------------------------------------------------

note "Launching whisper_hotkey"
/usr/bin/open -a "$INSTALLED_APP"

note "Done"
