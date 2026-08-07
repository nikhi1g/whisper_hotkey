#!/bin/bash
#
# Returns this Mac to the state a brand-new user's Mac is in, so the first-run
# experience can be tested against the real download from the site.
#
# Everything it removes is either re-downloadable or backed up first. Your
# settings are archived to a timestamped plist under
# ~/Library/Application Support/whisper_hotkey/fresh-test-backups/ and can be
# put back with --restore.
#
#   ./fresh_restart_application_test.sh              # reset, then print next steps
#   ./fresh_restart_application_test.sh --download   # also fetch and mount the DMG
#   ./fresh_restart_application_test.sh --keep-models  # leave the ~5.8 GB caches
#   ./fresh_restart_application_test.sh --restore    # put the newest backup back
#   ./fresh_restart_application_test.sh --list       # show what would be removed
#
# It never touches the repository, the build output, or the source tree.

set -euo pipefail

BUNDLE_ID="local.whisperhotkey.app"
INSTALLED_APP="/Applications/whisper_hotkey.app"
CLI="${HOME}/bin/whisper_hotkey"
MODEL_CACHE="${HOME}/Library/Caches/${BUNDLE_ID}"
FLUID_CACHE="${HOME}/Library/Application Support/FluidAudio"
WHISPERKIT_CACHE="${HOME}/Library/Caches/whisperkit-cli"
SUPPORT_DIR="${HOME}/Library/Application Support/whisper_hotkey"
BACKUP_DIR="${SUPPORT_DIR}/fresh-test-backups"
DMG_URL="https://github.com/nikhi1g/whisper_hotkey/releases/latest/download/whisper_hotkey.dmg"
SITE_URL="https://nikhi1g.github.io/whisper_hotkey/"
STAGED_DMG="${TMPDIR:-/tmp}/whisper_hotkey_fresh_test.dmg"

KEEP_MODELS=0
DO_DOWNLOAD=0
MODE="reset"

for argument in "$@"; do
    case "$argument" in
        --keep-models) KEEP_MODELS=1 ;;
        --download)    DO_DOWNLOAD=1 ;;
        --restore)     MODE="restore" ;;
        --list)        MODE="list" ;;
        -h|--help)     MODE="help" ;;
        *) printf 'error: unknown option: %s\n' "$argument" >&2; exit 1 ;;
    esac
done

note() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

size_of() {
    [[ -e "$1" ]] || { printf 'absent'; return; }
    /usr/bin/du -sh "$1" 2>/dev/null | /usr/bin/awk '{print $1}'
}

if [[ "$MODE" == "help" ]]; then
    /usr/bin/awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' \
        "${BASH_SOURCE[0]}"
    exit 0
fi

# --- Inventory -------------------------------------------------------------

if [[ "$MODE" == "list" ]]; then
    note "Would remove"
    info "app bundle        $(size_of "$INSTALLED_APP")	${INSTALLED_APP}"
    info "model cache       $(size_of "$MODEL_CACHE")	${MODEL_CACHE}"
    info "FluidAudio cache  $(size_of "$FLUID_CACHE")	${FLUID_CACHE}"
    info "WhisperKit cache  $(size_of "$WHISPERKIT_CACHE")	${WHISPERKIT_CACHE}"
    info "preferences       $(/usr/bin/defaults read "$BUNDLE_ID" >/dev/null 2>&1 \
        && echo present || echo absent)	${BUNDLE_ID}"
    info "CLI shim          $(size_of "$CLI")	${CLI}"
    info "stale test domains $(/usr/bin/defaults domains | /usr/bin/tr ',' '\n' \
        | /usr/bin/grep -c 'login-item-tests' || true)"
    note "Backups on disk"
    if [[ -d "$BACKUP_DIR" ]]; then
        /bin/ls -1t "$BACKUP_DIR" | /usr/bin/head -10 | while read -r name; do
            info "$name"
        done
    else
        info "none"
    fi
    exit 0
fi

# --- Restore ---------------------------------------------------------------

if [[ "$MODE" == "restore" ]]; then
    newest="$(/bin/ls -1t "${BACKUP_DIR}"/*.plist 2>/dev/null | /usr/bin/head -1 || true)"
    [[ -n "$newest" ]] || { printf 'error: no backup found in %s\n' "$BACKUP_DIR" >&2; exit 1; }

    note "Restoring preferences from $(/usr/bin/basename "$newest")"
    /usr/bin/defaults import "$BUNDLE_ID" "$newest"
    /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
    info "Models are not restored; the app re-downloads them on demand."
    exit 0
fi

# --- 1. Stop and remove the app -------------------------------------------

note "Stopping whisper_hotkey"
[[ -x "$CLI" ]] && "$CLI" stop >/dev/null 2>&1 || true
/usr/bin/osascript -e 'tell application "whisper_hotkey" to quit' >/dev/null 2>&1 || true
/bin/sleep 2
/usr/bin/pkill -f 'whisper_hotkey.app/Contents/MacOS/WhisperHotkeyApp' 2>/dev/null || true
/bin/sleep 1
/usr/bin/pgrep -f WhisperHotkeyApp >/dev/null 2>&1 \
    && info "still running; continuing anyway" \
    || info "stopped"

if [[ -d "$INSTALLED_APP" ]]; then
    note "Removing $INSTALLED_APP ($(size_of "$INSTALLED_APP"))"
    /bin/rm -rf "$INSTALLED_APP"
else
    note "No installed app bundle"
fi

if [[ -e "$CLI" ]]; then
    note "Removing the CLI shim"
    /bin/rm -f "$CLI"
fi

# --- 2. Back up and clear preferences -------------------------------------

/bin/mkdir -p "$BACKUP_DIR"
stamp="$(/bin/date +%Y%m%d-%H%M%S)"
backup="${BACKUP_DIR}/${stamp}.plist"

if /usr/bin/defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    note "Backing up preferences"
    /usr/bin/defaults export "$BUNDLE_ID" "$backup"
    info "$backup"

    note "Clearing preferences so first run presents itself"
    /usr/bin/defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
else
    note "No preferences to back up"
fi

# Test runs leave one throwaway domain behind per login-item case.
stale="$(/usr/bin/defaults domains | /usr/bin/tr ',' '\n' \
    | /usr/bin/grep 'login-item-tests' | /usr/bin/tr -d ' ' || true)"
if [[ -n "$stale" ]]; then
    note "Deleting $(printf '%s\n' "$stale" | /usr/bin/wc -l | /usr/bin/tr -d ' ') stale test domains"
    printf '%s\n' "$stale" | while read -r domain; do
        [[ -n "$domain" ]] && /usr/bin/defaults delete "$domain" >/dev/null 2>&1 || true
    done
fi

/usr/bin/killall cfprefsd >/dev/null 2>&1 || true

# --- 3. Clear the downloaded models ---------------------------------------

if [[ "$KEEP_MODELS" -eq 1 ]]; then
    note "Keeping the model caches (--keep-models)"
    info "The install will not need to download, so the download progress bar"
    info "will not be exercised."
else
    for cache in "$MODEL_CACHE" "$FLUID_CACHE" "$WHISPERKIT_CACHE"; do
        if [[ -d "$cache" ]]; then
            note "Removing $(size_of "$cache") from $(/usr/bin/basename "$cache")"
            /bin/rm -rf "$cache"
        fi
    done
fi

# --- 4. Revoke the permissions a new user has not granted -----------------

note "Revoking TCC grants for $BUNDLE_ID"
for service in Microphone Accessibility ListenEvent; do
    /usr/bin/tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 \
        && info "reset $service" \
        || info "$service had no grant to reset"
done

# Launch Services keeps pointing at the deleted bundle otherwise.
note "Rebuilding the Launch Services database entry"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -kill -r -domain local -domain user >/dev/null 2>&1 || true

# --- 5. Stage the download (opt-in) ---------------------------------------

if [[ "$DO_DOWNLOAD" -eq 1 ]]; then
    note "Downloading the current release DMG"
    /usr/bin/curl -fL --progress-bar -o "$STAGED_DMG" "$DMG_URL"

    note "Applying a real quarantine flag, as a browser download would"
    /usr/bin/xattr -w com.apple.quarantine \
        "0081;$(/usr/bin/printf '%x' "$(/bin/date +%s)");Safari;" "$STAGED_DMG"

    note "Mounting"
    /usr/bin/hdiutil attach -nobrowse "$STAGED_DMG"
    info "Drag whisper_hotkey.app from the mounted volume into /Applications,"
    info "then eject it. Do not use cp: the point is to test the Finder path."
fi

# --- Report ----------------------------------------------------------------

note "This Mac now looks like a new user's"
info "no app bundle, no preferences, no models, no permission grants"
printf '\n'
info "Next:"
info "  1. Open ${SITE_URL}"
info "  2. Download, open the DMG, drag the app to Applications"
info "  3. Launch it. Gatekeeper should require one approval through"
info "     System Settings > Privacy & Security > Open Anyway"
info "  4. Expect: first-run setup, then Microphone, Accessibility, and"
info "     Input Monitoring prompts, then a model download with the"
info "     in-Settings progress bar"
printf '\n'
info "To get your settings back afterwards:"
info "  ./fresh_restart_application_test.sh --restore"
printf '\n'
