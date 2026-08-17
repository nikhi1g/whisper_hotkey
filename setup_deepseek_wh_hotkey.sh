#!/bin/bash
# setup_deepseek_wh_hotkey.sh — one-time DeepSeek API key setup for
# whisper_hotkey post-processing (post_processing branch only).
#
# Usage:
#   ./setup_deepseek_wh_hotkey.sh            # interactive, prompts for the key
#   ./setup_deepseek_wh_hotkey.sh "sk-..."   # non-interactive (visible in shell history)
#   ./setup_deepseek_wh_hotkey.sh --verify   # key already stored; test it against the API
#
# The key is stored as a generic password in the login keychain:
#   service: com.whisperhotkey.deepseek
#   account: api-key
# This is the same item the app reads through ProcessorKeychain (env
# DEEPSEEK_API_KEY still overrides it for development).

set -euo pipefail

SERVICE="com.whisperhotkey.deepseek"
ACCOUNT="api-key"
MODEL="${DEEPSEEK_PROCESSOR_MODEL:-deepseek-v4-flash}"

BOLD="$(tput bold 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
RED="$(tput setaf 1 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"

say()  { printf '%s\n' "$*"; }
ok()   { say "${GREEN}✓${RESET} $*"; }
fail() { say "${RED}✗${RESET} $*"; }
die()  { fail "$*"; exit 1; }

KEY="${1:-}"
VERIFY_ONLY=0
if [ "${KEY:-}" = "--verify" ]; then
    VERIFY_ONLY=1
    KEY=""
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

say "${BOLD}whisper_hotkey — DeepSeek post-processing setup${RESET}"

# --- 1. Branch guard ---------------------------------------------------------
BRANCH="$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || true)"
if [ "$BRANCH" != "post_processing" ]; then
    if [ "${WH_SKIP_BRANCH_CHECK:-0}" != "1" ]; then
        die "Not on the post_processing branch (current: '${BRANCH:-unknown}'). \
The post-processing code lives there. Re-run from that branch, or set WH_SKIP_BRANCH_CHECK=1 to force."
    fi
    say "Warning: not on post_processing (current: '${BRANCH:-unknown}'). Continuing because WH_SKIP_BRANCH_CHECK=1."
fi

# --- 2. Build the branch -----------------------------------------------------
if [ "$VERIFY_ONLY" -eq 0 ]; then
    say "${BOLD}Building the post_processing app…${RESET}"
    (cd "$REPO_DIR" && swift build 2>&1 | tail -n 3) || die "swift build failed — fix the branch before setting up the key."
    ok "Build complete."
fi

# --- 3. Obtain the key -------------------------------------------------------
if [ "$VERIFY_ONLY" -eq 0 ] && [ -z "$KEY" ]; then
    printf 'DeepSeek API key (input hidden): '
    IFS= read -rs KEY || die "Could not read the key."
    say ""
    if [ -z "$KEY" ]; then
        die "Empty key."
    fi
fi

if [ "$VERIFY_ONLY" -eq 0 ]; then
    case "$KEY" in
        *[[:space:]]*) die "The key must not contain whitespace." ;;
    esac

    # --- 4. Store in the login keychain -------------------------------------
    say "${BOLD}Storing the key in the login keychain…${RESET}"
    security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1 || true
    security add-generic-password -U -s "$SERVICE" -a "$ACCOUNT" -w "$KEY" \
        || die "Keychain write failed."

    # --- 5. Read-back verification ------------------------------------------
    STORED="$(security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null || true)"
    if [ "$STORED" = "$KEY" ]; then
        ok "Key stored and verified (service $SERVICE, account $ACCOUNT)."
    else
        die "Keychain read-back mismatch."
    fi
    unset STORED
fi

# --- 6. Optional live verification ------------------------------------------
if [ "$VERIFY_ONLY" -eq 1 ] || [ "${1:-}" = "--verify" ]; then
    say "${BOLD}Verifying the key against the DeepSeek API…${RESET}"
    API_KEY="$(security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null || true)"
    if [ -z "$API_KEY" ]; then
        die "No key stored yet — run ./setup_deepseek_wh_hotkey.sh first."
    fi
    PAYLOAD=$(python3 - "$MODEL" <<'PY'
import json, sys
print(json.dumps({
    "model": sys.argv[1],
    "messages": [{"role": "user", "content": "ping"}],
    "max_tokens": 1,
    "thinking": {"type": "disabled"},
}))
PY
)
    RESPONSE="$(curl -sS --max-time 20 -X POST https://api.deepseek.com/chat/completions \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" || true)"
    unset API_KEY
    if printf '%s' "$RESPONSE" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert "choices" in data, data.get("error", {}).get("message", "unexpected response")
sys.exit(0)
' 2>/dev/null; then
        ok "API key accepted by DeepSeek (model $MODEL reachable)."
    else
        ERR="$(printf '%s' "$RESPONSE" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("error", {}).get("message", "unknown error"))
except Exception:
    print("network error or invalid response")
' 2>/dev/null || true)"
        die "DeepSeek rejected the verification call: $ERR"
    fi
fi

# --- 7. Next steps -----------------------------------------------------------
say ""
say "${BOLD}Next steps:${RESET}"
say "  1. Launch the app from this branch (swift run WhisperHotkeyApp or the dev build)."
say "  2. Open Settings → Post-processing, enable the toggle, pick a profile."
say "  3. Dictate; review the processed text in the badge; Enter inserts, Esc cancels."
say "  4. Optional: set DEEPSEEK_PROCESSOR_MODEL to override the processor model."
