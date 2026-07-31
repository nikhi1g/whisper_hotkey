#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${HOME}/.cache/whisper"
MODEL_BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
COREML_WHISPER_PREFIX="${HOME}/.local/share/whisper_hotkey/whisper.cpp-coreml-1.9.1"
CHECK_ONLY=0
REQUESTED_MODELS=("base")
ENGINE="metal"

usage() {
    cat <<'EOF'
Usage: ./run.sh [options]

Build, install, launch, and open setup for whisper_hotkey.

  --model base|small|medium|turbo  Download one model (default: base)
  --engine metal|coreml|whisperkit Recognition engine (default: metal)
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

coreml_encoder_name() {
    case "$1" in
        base) echo "ggml-base.en-encoder.mlmodelc.zip" ;;
        small) echo "ggml-small.en-encoder.mlmodelc.zip" ;;
        medium) echo "ggml-medium.en-encoder.mlmodelc.zip" ;;
        turbo) echo "ggml-large-v3-turbo-encoder.mlmodelc.zip" ;;
        *) die "unknown model: $1" ;;
    esac
}

coreml_encoder_sha256() {
    case "$1" in
        base) echo "8cf860309e2449e2bdc8be834cf838ab2565747ecc8c0ef914ef5975115e192b" ;;
        small) echo "b2ef1c506378b825b4b4341979a93e1656b5d6c129f17114cfb8fb78aabc2f89" ;;
        medium) echo "cdc44fee3c62b5743913e3147ed75f4e8ecfb52dd7a0f0f7387094b406ff0ee6" ;;
        turbo) echo "84bedfe895bd7b5de6e8e89a0803dfc5addf8c0c5bc4c937451716bf7cf7988a" ;;
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

download_coreml_encoder() {
    local model="$1" name archive temporary expected actual coreml_dir
    name="$(coreml_encoder_name "$model")"
    archive="${MODEL_DIR}/${name}"
    temporary="${archive}.download.$$"
    coreml_dir="${MODEL_DIR}/coreml"
    /bin/mkdir -p "$coreml_dir"
    /bin/chmod 700 "$coreml_dir"
    if [[ ! -f "$archive" ]]; then
        note "Downloading $name"
        /usr/bin/curl --fail --location --retry 3 --progress-bar \
            "${MODEL_BASE_URL}/${name}" --output "$temporary"
        expected="$(coreml_encoder_sha256 "$model")"
        actual="$(/usr/bin/shasum -a 256 "$temporary" | /usr/bin/awk '{print $1}')"
        [[ "$actual" == "$expected" ]] \
            || die "checksum verification failed for $name"
        /bin/chmod 600 "$temporary"
        /bin/mv "$temporary" "$archive"
    fi
    expected="$(coreml_encoder_sha256 "$model")"
    actual="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || die "invalid Core ML encoder archive"
    /usr/bin/ditto -x -k "$archive" "$coreml_dir"
    /bin/ln -sfn "../$(model_file "$model")" \
        "${coreml_dir}/$(model_file "$model")"
}

verify_coreml_encoder() {
    local model="$1" archive expected actual encoder model_link
    archive="${MODEL_DIR}/$(coreml_encoder_name "$model")"
    encoder="${MODEL_DIR}/coreml/$(
        coreml_encoder_name "$model" | /usr/bin/sed 's/\.zip$//'
    )"
    model_link="${MODEL_DIR}/coreml/$(model_file "$model")"
    [[ -f "$archive" && -d "$encoder" && -f "$model_link" ]] || return 1
    expected="$(coreml_encoder_sha256 "$model")"
    actual="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
    [[ "$actual" == "$expected" ]]
}

prepare_coreml_runtime() {
    local source_dir build_dir
    WHISPER_CPP_PREFIX="$COREML_WHISPER_PREFIX"
    GGML_PREFIX="$WHISPER_CPP_PREFIX"
    source_dir="${HOME}/.cache/whisper_hotkey/whisper.cpp-1.9.1"
    build_dir="${source_dir}/build-coreml"
    if [[ ! -f "${WHISPER_CPP_PREFIX}/share/whisper_hotkey/macos-14" ]]; then
        /bin/mkdir -p "$(/usr/bin/dirname "$source_dir")"
        if [[ ! -d "${source_dir}/.git" ]]; then
            note "Fetching pinned whisper.cpp 1.9.1 source"
            /usr/bin/git clone --depth 1 --branch v1.9.1 \
                https://github.com/ggml-org/whisper.cpp.git "$source_dir"
        fi
        [[ "$(/usr/bin/git -C "$source_dir" rev-parse HEAD)" \
            == "f049fff95a089aa9969deb009cdd4892b3e74916" ]] \
            || die "whisper.cpp source revision is not the pinned v1.9.1 commit"
        note "Building whisper.cpp with Core ML and Metal"
        /opt/homebrew/bin/cmake -S "$source_dir" -B "$build_dir" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
            -DCMAKE_INSTALL_PREFIX="$WHISPER_CPP_PREFIX" \
            -DWHISPER_COREML=ON \
            -DWHISPER_COREML_ALLOW_FALLBACK=ON \
            -DWHISPER_BUILD_EXAMPLES=OFF \
            -DWHISPER_BUILD_TESTS=OFF \
            -DGGML_METAL=ON \
            -DBUILD_SHARED_LIBS=ON
        /opt/homebrew/bin/cmake --build "$build_dir" --parallel
        /opt/homebrew/bin/cmake --install "$build_dir"
        /bin/mkdir -p "${WHISPER_CPP_PREFIX}/share/whisper_hotkey"
        /usr/bin/touch \
            "${WHISPER_CPP_PREFIX}/share/whisper_hotkey/macos-14"
    fi
    export WHISPER_HOTKEY_COREML=1
}

use_installed_coreml_runtime() {
    if [[ -f "${COREML_WHISPER_PREFIX}/lib/libwhisper.dylib" ]]; then
        WHISPER_CPP_PREFIX="$COREML_WHISPER_PREFIX"
        GGML_PREFIX="$COREML_WHISPER_PREFIX"
        export WHISPER_CPP_PREFIX GGML_PREFIX
        export WHISPER_HOTKEY_COREML=1
    fi
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
        --engine)
            [[ $# -ge 2 ]] || die "--engine requires a value"
            case "$2" in
                metal|coreml|whisperkit) ENGINE="$2" ;;
                *) die "unknown engine: $2" ;;
            esac
            shift 2
            ;;
        --check) CHECK_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "macOS is required"
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || die "v3.0.5 supports Apple Silicon only"
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
    case "$ENGINE" in
        coreml)
            [[ -f "${COREML_WHISPER_PREFIX}/share/whisper_hotkey/macos-14" ]] \
                || die "the pinned Core ML whisper.cpp runtime is missing"
            for model in "${REQUESTED_MODELS[@]}"; do
                verify_coreml_encoder "$model" \
                    || die "the Core ML encoder for $model is missing or invalid"
            done
            ;;
        whisperkit)
            for model in "${REQUESTED_MODELS[@]}"; do
                /usr/bin/python3 \
                    "${ROOT}/scripts/download_whisperkit_model.py" \
                    "$model" --destination "${HOME}/.cache/whisperkit" \
                    --verify-only
            done
            ;;
    esac
    note "Prerequisites and requested models are ready"
    exit 0
fi

/bin/mkdir -p "$MODEL_DIR"
/bin/chmod 700 "$MODEL_DIR"
for model in "${REQUESTED_MODELS[@]}"; do download_model "$model"; done
case "$ENGINE" in
    coreml)
        prepare_coreml_runtime
        for model in "${REQUESTED_MODELS[@]}"; do
            download_coreml_encoder "$model"
        done
        ;;
    whisperkit)
        for model in "${REQUESTED_MODELS[@]}"; do
            note "Downloading verified WhisperKit $model model"
            /usr/bin/python3 "${ROOT}/scripts/download_whisperkit_model.py" \
                "$model" --destination "${HOME}/.cache/whisperkit"
        done
        ;;
esac
use_installed_coreml_runtime

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
        die "no stable code-signing identity was found"
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
