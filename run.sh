#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${HOME}/.cache/whisper"
MODEL_BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
LOCAL_SIGNING_IDENTITY="whisper_hotkey Local Development"
BUNDLE_IDENTIFIER="local.whisperhotkey.app"
CHECK_ONLY=0
REQUESTED_MODELS=("base")
ENGINE="metal"
SELECTION_WAS_REQUESTED=0
SIGNING_TEMP_DIR=""
CREATED_SIGNING_IDENTITY=""
DOWNLOAD_TEMP_FILE=""
BOOTSTRAP_TEMP_FILE=""

usage() {
    cat <<'EOF'
Usage: ./run.sh [options]

Build, install, launch, and open setup for whisper_hotkey.

  --model base|turbo                Install and select one model (default: base)
  --engine metal|parakeet|cohere
                                    Install and select an engine (default: metal)
                                    parakeet fetches its model on first use
  --all-models                      Install every supported model (~2.7 GB)
  --check                           Validate without changing anything
  -h, --help                        Show this help

With no options, the recommended Base English model and whisper.cpp Metal
engine are installed. Missing Homebrew and signing setup are bootstrapped
interactively. At least one verified model is ready before the app launches,
and this script stays open until the complete macOS setup is verified.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

cleanup() {
    if [[ -n "$DOWNLOAD_TEMP_FILE" ]]; then
        /bin/rm -f "$DOWNLOAD_TEMP_FILE"
        DOWNLOAD_TEMP_FILE=""
    fi
    if [[ -n "$BOOTSTRAP_TEMP_FILE" ]]; then
        /bin/rm -f "$BOOTSTRAP_TEMP_FILE"
        BOOTSTRAP_TEMP_FILE=""
    fi
    if [[ -n "$SIGNING_TEMP_DIR" && -d "$SIGNING_TEMP_DIR" ]]; then
        /bin/rm -f \
            "${SIGNING_TEMP_DIR}/identity.key" \
            "${SIGNING_TEMP_DIR}/identity.crt" \
            "${SIGNING_TEMP_DIR}/identity.p12"
        /bin/rmdir "$SIGNING_TEMP_DIR" 2>/dev/null || true
        SIGNING_TEMP_DIR=""
    fi
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

model_file() {
    case "$1" in
        base) echo "ggml-base.en.bin" ;;
        small) echo "ggml-small.en.bin" ;;
        medium) echo "ggml-medium.en.bin" ;;
        turbo) echo "ggml-large-v3-turbo-q5_0.bin" ;;
        *) die "unknown model: $1" ;;
    esac
}

model_sha256() {
    case "$1" in
        base) echo "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002" ;;
        small) echo "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d" ;;
        medium) echo "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356" ;;
        turbo) echo "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2" ;;
        *) die "unknown model: $1" ;;
    esac
}

model_preference() {
    case "$1" in
        base) echo "baseEnglish" ;;
        turbo) echo "largeV3TurboQ5" ;;
        *) die "unknown model: $1" ;;
    esac
}

engine_preference() {
    case "$1" in
        metal) echo "whisperCppMetal" ;;
        parakeet) echo "parakeetCoreML" ;;
        cohere) echo "cohereCoreML" ;;
        *) die "unknown engine: $1" ;;
    esac
}

first_signing_identity() {
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | /usr/bin/sed -n \
            's/^[[:space:]]*[0-9][0-9]*) \([[:xdigit:]]\{40\}\) .*/\1/p' \
        | /usr/bin/head -1
}

login_keychain() {
    local keychain
    keychain="$(
        /usr/bin/security login-keychain 2>/dev/null \
            | /usr/bin/sed -n 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p'
    )"
    if [[ -n "$keychain" ]]; then
        printf '%s\n' "$keychain"
    else
        printf '%s\n' "${HOME}/Library/Keychains/login.keychain-db"
    fi
}

create_local_signing_identity() {
    local keychain passphrase serial identity
    keychain="$(login_keychain)"
    [[ -f "$keychain" ]] \
        || die "the login keychain was not found at $keychain"

    SIGNING_TEMP_DIR="$(
        /usr/bin/mktemp -d \
            "${TMPDIR:-/private/tmp}/whisper_hotkey-signing.XXXXXX"
    )"
    /bin/chmod 700 "$SIGNING_TEMP_DIR"
    passphrase="$(/usr/bin/uuidgen)$(/usr/bin/uuidgen)"
    serial="$(/bin/date +%s)"

    note "Creating a stable local code-signing identity in your login keychain" >&2
    /usr/bin/openssl req \
        -new -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes \
        -set_serial "$serial" \
        -subj "/CN=${LOCAL_SIGNING_IDENTITY}/O=Local Development/" \
        -addext "basicConstraints=critical,CA:true" \
        -addext "keyUsage=critical,digitalSignature,keyCertSign" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -keyout "${SIGNING_TEMP_DIR}/identity.key" \
        -out "${SIGNING_TEMP_DIR}/identity.crt" >/dev/null 2>&1
    /bin/chmod 600 "${SIGNING_TEMP_DIR}/identity.key"
    /usr/bin/openssl pkcs12 -export \
        -inkey "${SIGNING_TEMP_DIR}/identity.key" \
        -in "${SIGNING_TEMP_DIR}/identity.crt" \
        -name "$LOCAL_SIGNING_IDENTITY" \
        -passout "pass:${passphrase}" \
        -out "${SIGNING_TEMP_DIR}/identity.p12"
    /usr/bin/security import "${SIGNING_TEMP_DIR}/identity.p12" \
        -k "$keychain" -f pkcs12 -P "$passphrase" \
        -T /usr/bin/codesign >/dev/null
    /usr/bin/security add-trusted-cert \
        -r trustRoot -p codeSign -k "$keychain" \
        "${SIGNING_TEMP_DIR}/identity.crt" >/dev/null

    identity="$(first_signing_identity)"
    [[ -n "$identity" ]] || die "the local signing identity could not be activated"
    CREATED_SIGNING_IDENTITY="$identity"
    cleanup
}

ensure_developer_tools() {
    if /usr/bin/xcode-select -p >/dev/null 2>&1; then
        return
    fi
    [[ "$CHECK_ONLY" -eq 0 ]] \
        || die "Xcode Command Line Tools are not installed"
    note "Opening the Xcode Command Line Tools installer"
    /usr/bin/xcode-select --install >/dev/null 2>&1 \
        || die "could not open the Xcode Command Line Tools installer"
    if [[ ! -t 0 ]]; then
        die "finish installing Xcode Command Line Tools, then run ./run.sh again"
    fi
    printf 'Finish the Apple installer, then press Return here to continue. '
    read -r _
    /usr/bin/xcode-select -p >/dev/null 2>&1 \
        || die "Xcode Command Line Tools are still unavailable"
}

ensure_homebrew() {
    local installer
    if [[ -x /opt/homebrew/bin/brew ]]; then
        return
    fi
    [[ "$CHECK_ONLY" -eq 0 ]] || die "Homebrew is not installed"
    note "Homebrew is required; starting its official installer"
    installer="$(/usr/bin/mktemp "${TMPDIR:-/private/tmp}/homebrew-install.XXXXXX")"
    BOOTSTRAP_TEMP_FILE="$installer"
    if ! /usr/bin/curl --fail --location --retry 3 --silent --show-error \
        "$HOMEBREW_INSTALL_URL" --output "$installer"
    then
        /bin/rm -f "$installer"
        die "could not download the official Homebrew installer"
    fi
    if ! /bin/bash "$installer"; then
        /bin/rm -f "$installer"
        die "Homebrew installation did not complete"
    fi
    /bin/rm -f "$installer"
    BOOTSTRAP_TEMP_FILE=""
    [[ -x /opt/homebrew/bin/brew ]] \
        || die "Homebrew did not install at /opt/homebrew"
}

ensure_signing_identity() {
    local identity
    if [[ -n "${WHISPER_HOTKEY_CODESIGN_IDENTITY:-}" ]]; then
        [[ "$WHISPER_HOTKEY_CODESIGN_IDENTITY" != "-" ]] \
            || die "ad-hoc signing is not supported; provide a stable identity"
        note "Using requested signing identity: $WHISPER_HOTKEY_CODESIGN_IDENTITY"
        return
    fi
    identity="$(first_signing_identity)"
    if [[ -z "$identity" ]]; then
        [[ "$CHECK_ONLY" -eq 0 ]] || die "no stable code-signing identity was found"
        create_local_signing_identity
        identity="$CREATED_SIGNING_IDENTITY"
    fi
    export WHISPER_HOTKEY_CODESIGN_IDENTITY="$identity"
    note "Using stable signing identity: $identity"
}

persist_requested_selection() {
    local model
    [[ "$SELECTION_WAS_REQUESTED" -eq 1 ]] || return 0
    model="${REQUESTED_MODELS[0]}"
    /usr/bin/defaults write "$BUNDLE_IDENTIFIER" dictationModel \
        -string "$(model_preference "$model")"
    /usr/bin/defaults write "$BUNDLE_IDENTIFIER" recognitionEngine \
        -string "$(engine_preference "$ENGINE")"
    note "Selected $(model_preference "$model") with $(engine_preference "$ENGINE")"
}

wait_for_verified_setup() {
    local controller verification previous_verification
    controller="${HOME}/bin/whisper_hotkey"
    previous_verification=""

    while true; do
        if verification="$("$controller" verify-setup 2>&1)"; then
            printf '\n%s\n' "$verification"
            note "Model installation and macOS setup are verified"
            return 0
        fi

        if [[ "$verification" != "$previous_verification" ]]; then
            printf '\n%s\n' "$verification"
            previous_verification="$verification"
        fi

        if [[ -t 0 ]]; then
            "$controller" setup >/dev/null 2>&1 || true
            printf '%s' \
                "Complete every item in the setup window, then press Return to verify again. "
            read -r _
        else
            note "Waiting for setup verification; checking again in 2 seconds"
            /bin/sleep 2
        fi
    done
}

verify_model() {
    local model="$1" file expected actual
    file="${MODEL_DIR}/$(model_file "$model")"
    expected="$(model_sha256 "$model")"
    [[ -f "$file" ]] || return 1
    actual="$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
    [[ "$actual" == "$expected" ]]
}

download_model() {
    local model="$1" name destination temporary expected actual
    name="$(model_file "$model")"
    destination="${MODEL_DIR}/${name}"
    temporary="${destination}.download.$$"
    DOWNLOAD_TEMP_FILE="$temporary"
    if verify_model "$model"; then
        DOWNLOAD_TEMP_FILE=""
        note "$name is already present and verified"
        return
    fi
    [[ ! -e "$destination" ]] \
        || die "$destination exists but does not match the published checksum"
    note "Downloading $name"
    if ! /usr/bin/curl --fail --location --retry 3 --progress-bar \
        "${MODEL_BASE_URL}/${name}" --output "$temporary"
    then
        /bin/rm -f "$temporary"
        die "download failed for $name"
    fi
    /bin/chmod 600 "$temporary"
    expected="$(model_sha256 "$model")"
    actual="$(/usr/bin/shasum -a 256 "$temporary" | /usr/bin/awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        /bin/rm -f "$temporary"
        die "checksum verification failed for $name"
    fi
    /bin/mv "$temporary" "$destination"
    DOWNLOAD_TEMP_FILE=""
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            [[ $# -ge 2 ]] || die "--model requires a value"
            model_file "$2" >/dev/null
            REQUESTED_MODELS=("$2")
            SELECTION_WAS_REQUESTED=1
            shift 2
            ;;
        --all-models)
            REQUESTED_MODELS=("base" "turbo")
            SELECTION_WAS_REQUESTED=1
            shift
            ;;
        --engine)
            [[ $# -ge 2 ]] || die "--engine requires a value"
            case "$2" in
                metal|parakeet|cohere) ENGINE="$2" ;;
                *) die "unknown engine: $2" ;;
            esac
            SELECTION_WAS_REQUESTED=1
            shift 2
            ;;
        --check) CHECK_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

[[ "$EUID" -ne 0 ]] \
    || die "do not run this bootstrap with sudo; run it from your normal account"
[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "macOS is required"
[[ "$(/usr/bin/uname -m)" == "arm64" ]] \
    || die "whisper_hotkey supports Apple Silicon only"
[[ "$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)" -ge 14 ]] \
    || die "macOS 14 or newer is required"
[[ -w /Applications ]] \
    || die "your account cannot install apps in /Applications"
ensure_developer_tools
ensure_homebrew
ensure_signing_identity

if ! /opt/homebrew/bin/brew list --versions whisper-cpp >/dev/null 2>&1; then
    [[ "$CHECK_ONLY" -eq 0 ]] || die "Homebrew whisper-cpp is not installed"
    note "Installing whisper-cpp with Homebrew"
    /opt/homebrew/bin/brew install whisper-cpp
fi

export WHISPER_CPP_PREFIX GGML_PREFIX HOMEBREW_PREFIX
HOMEBREW_PREFIX="$(/opt/homebrew/bin/brew --prefix)"
WHISPER_CPP_PREFIX="$(/opt/homebrew/bin/brew --prefix whisper-cpp)"
GGML_PREFIX="$(/opt/homebrew/bin/brew --prefix ggml)"

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    for model in "${REQUESTED_MODELS[@]}"; do
        verify_model "$model" || die "$(model_file "$model") is missing or invalid"
    done
    note "Prerequisites and requested models are ready"
    exit 0
fi

/bin/mkdir -p "$MODEL_DIR"
/bin/chmod 700 "$MODEL_DIR"
for model in "${REQUESTED_MODELS[@]}"; do download_model "$model"; done

cd "$ROOT"
note "Building whisper_hotkey $(/bin/cat VERSION)"
/usr/bin/python3 build_app.py
persist_requested_selection
note "Installing and launching whisper_hotkey"
/usr/bin/python3 install.py
note "Opening permission setup"
"${HOME}/bin/whisper_hotkey" setup
wait_for_verified_setup
printf '\n%s\n' \
    "Installed and verified. Use your selected dictation key anywhere text can be entered."
printf '%s\n' "Check readiness any time with: ${HOME}/bin/whisper_hotkey status"
