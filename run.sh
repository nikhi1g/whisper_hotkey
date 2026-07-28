#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${HOME}/.cache/whisper"
MODEL_BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
CHECK_ONLY=0
REQUESTED_MODELS=("base")

usage() {
    cat <<'EOF'
Usage: ./run.sh [options]

Build, install, launch, and open setup for whisper_hotkey.

  --model base|small|medium|turbo  Download one model (default: base)
  --all-models                    Download every supported model (~2.7 GB)
  --check                         Validate without changing anything
  -h, --help                      Show this help
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

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
    if verify_model "$model"; then
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
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            [[ $# -ge 2 ]] || die "--model requires a value"
            model_file "$2" >/dev/null
            REQUESTED_MODELS=("$2")
            shift 2
            ;;
        --all-models)
            REQUESTED_MODELS=("base" "small" "medium" "turbo")
            shift
            ;;
        --check) CHECK_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "macOS is required"
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || die "v1.0.0 supports Apple Silicon only"
[[ "$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)" -ge 14 ]] \
    || die "macOS 14 or newer is required"
/usr/bin/xcode-select -p >/dev/null 2>&1 \
    || die "install Xcode Command Line Tools first: xcode-select --install"
[[ -x /opt/homebrew/bin/brew ]] || die "install Homebrew first: https://brew.sh"

if ! /opt/homebrew/bin/brew list --versions whisper-cpp >/dev/null 2>&1; then
    [[ "$CHECK_ONLY" -eq 0 ]] || die "Homebrew whisper-cpp is not installed"
    note "Installing whisper-cpp with Homebrew"
    /opt/homebrew/bin/brew install whisper-cpp
fi

export WHISPER_CPP_PREFIX GGML_PREFIX
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

if [[ -z "${WHISPER_HOTKEY_CODESIGN_IDENTITY:-}" ]]; then
    SIGNING_IDENTITY="$(
        /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
            | /usr/bin/sed -n 's/.*"\(.*\)".*/\1/p' \
            | /usr/bin/head -1
    )"
    if [[ -n "$SIGNING_IDENTITY" ]]; then
        export WHISPER_HOTKEY_CODESIGN_IDENTITY="$SIGNING_IDENTITY"
        note "Using stable signing identity: $SIGNING_IDENTITY"
    else
        export WHISPER_HOTKEY_CODESIGN_IDENTITY="-"
        printf '%s\n' \
            "warning: no Apple signing identity was found." \
            "This source build will be ad-hoc signed; macOS may ask for" \
            "permissions again after future rebuilds." >&2
    fi
fi

cd "$ROOT"
note "Building whisper_hotkey $(/bin/cat VERSION)"
/usr/bin/python3 build_app.py
note "Installing and launching whisper_hotkey"
/usr/bin/python3 install.py
note "Opening permission setup"
"${HOME}/bin/whisper_hotkey" setup
printf '\n%s\n' "Installed. Hold Right Command to dictate."
