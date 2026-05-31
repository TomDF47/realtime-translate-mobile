#!/usr/bin/env bash
set -euo pipefail

# APK metadata + signing preflight for the Android release smoke flow (#39).
#
# Validates a freshly built APK before it is installed on a device:
#   - recomputes the SHA-256 and compares it to a `.sha256` sidecar when present,
#   - confirms the package id and that version metadata exists,
#   - confirms requested permissions stay within the least-privilege allowlist,
#   - reports whether the APK is debug- or release-signed (debug is expected for
#     debug releases and is not a failure here).
#
# This script never reads OpenAI credentials and prints only sanitized facts.
# Store-ready signing enforcement stays in scripts/check_android_release_signing.sh.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_PACKAGE="com.tomdf47.realtime_translate_mobile"
APK_PATH=""
FACTS_FILE=""

usage() {
  cat <<'USAGE'
Usage: scripts/check_apk_metadata.sh --apk APK_PATH [--facts-file PATH]

Validates APK package id, version metadata, permission allowlist, SHA-256
sidecar (when present), and signing posture without installing the APK or
reading OpenAI credentials.

Options:
  --apk APK_PATH      APK to inspect (required).
  --facts-file PATH   Also write sanitized key=value facts to PATH for the
                      release smoke recorder.
  --help              Show this help.
USAGE
}

while (($#)); do
  case "$1" in
    --apk)
      APK_PATH="${2:-}"
      if [[ -z "$APK_PATH" ]]; then
        echo "Missing value for --apk" >&2
        exit 2
      fi
      shift 2
      ;;
    --facts-file)
      FACTS_FILE="${2:-}"
      if [[ -z "$FACTS_FILE" ]]; then
        echo "Missing value for --facts-file" >&2
        exit 2
      fi
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$APK_PATH" ]]; then
  echo "Missing required --apk APK_PATH" >&2
  usage >&2
  exit 2
fi

fail() {
  printf 'APK metadata preflight failed: %s\n' "$*" >&2
  exit 1
}

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"

resolve_tool() {
  # $1 = override env value, $2 = command name, $3 = build-tools binary name
  local override="$1" command_name="$2" build_tools_name="$3" found=""
  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  found="$(command -v "$command_name" 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi
  if [[ -d "$ANDROID_HOME/build-tools" ]]; then
    found="$(find "$ANDROID_HOME/build-tools" -maxdepth 2 -name "$build_tools_name" -type f 2>/dev/null | sort | tail -1)"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return 0
    fi
  fi
  return 1
}

AAPT2_BIN="$(resolve_tool "${AAPT2:-}" aapt2 aapt2 || true)"
APKSIGNER_BIN="$(resolve_tool "${APKSIGNER:-}" apksigner apksigner || true)"
APKANALYZER_BIN=""
if [[ -z "$AAPT2_BIN" ]]; then
  if [[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer" ]]; then
    APKANALYZER_BIN="$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer"
  else
    APKANALYZER_BIN="$(command -v apkanalyzer 2>/dev/null || true)"
  fi
fi

if [[ ! -f "$APK_PATH" ]]; then
  fail "APK not found: $APK_PATH"
fi

# --- SHA-256 vs sidecar ---------------------------------------------------
APK_SHA256="$(sha256sum "$APK_PATH" | awk '{print $1}')"
SHA_STATUS="no-sidecar"
if [[ -f "$APK_PATH.sha256" ]]; then
  EXPECTED_SHA="$(awk '{print $1; exit}' "$APK_PATH.sha256")"
  if [[ "$EXPECTED_SHA" == "$APK_SHA256" ]]; then
    SHA_STATUS="verified"
  else
    fail "SHA-256 does not match sidecar $APK_PATH.sha256 (expected $EXPECTED_SHA, got $APK_SHA256)"
  fi
fi

# --- Manifest metadata ----------------------------------------------------
PACKAGE_NAME=""
VERSION_CODE=""
VERSION_NAME=""
PERMISSIONS=""

extract_quoted() {
  # $1 = key, reads a single badging line on stdin, prints key='value' value.
  local key="$1"
  grep -o "${key}='[^']*'" | head -1 | sed "s/^${key}='//; s/'$//"
}

if [[ -n "$AAPT2_BIN" ]]; then
  BADGING="$("$AAPT2_BIN" dump badging "$APK_PATH" 2>/dev/null || true)"
  if [[ -z "$BADGING" ]]; then
    fail "aapt2 could not read badging for $APK_PATH"
  fi
  PACKAGE_LINE="$(printf '%s\n' "$BADGING" | awk '/^package:/{print; exit}')"
  PACKAGE_NAME="$(printf '%s\n' "$PACKAGE_LINE" | extract_quoted name)"
  VERSION_CODE="$(printf '%s\n' "$PACKAGE_LINE" | extract_quoted versionCode)"
  VERSION_NAME="$(printf '%s\n' "$PACKAGE_LINE" | extract_quoted versionName)"
  PERMISSIONS="$(
    printf '%s\n' "$BADGING" |
      awk '/^uses-permission/' |
      grep -o "name='[^']*'" |
      sed "s/^name='//; s/'$//" |
      sort -u
  )"
elif [[ -n "$APKANALYZER_BIN" ]]; then
  PACKAGE_NAME="$("$APKANALYZER_BIN" manifest application-id "$APK_PATH" 2>/dev/null | tr -d '\r' || true)"
  VERSION_CODE="$("$APKANALYZER_BIN" manifest version-code "$APK_PATH" 2>/dev/null | tr -d '\r' || true)"
  VERSION_NAME="$("$APKANALYZER_BIN" manifest version-name "$APK_PATH" 2>/dev/null | tr -d '\r' || true)"
  PERMISSIONS="$("$APKANALYZER_BIN" manifest permissions "$APK_PATH" 2>/dev/null | tr -d '\r' | sort -u || true)"
else
  fail "neither aapt2 nor apkanalyzer was found; install Android build-tools or cmdline-tools"
fi

if [[ "$PACKAGE_NAME" != "$EXPECTED_PACKAGE" ]]; then
  fail "unexpected package id '$PACKAGE_NAME' (expected '$EXPECTED_PACKAGE')"
fi
if [[ -z "$VERSION_CODE" || -z "$VERSION_NAME" ]]; then
  fail "APK is missing versionCode/versionName metadata"
fi

# --- Permission allowlist -------------------------------------------------
# RECORD_AUDIO: live microphone capture. INTERNET: direct OpenAI calls (debug/
# profile overlays). DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION: AndroidX self-
# scoped signature permission generated for runtime receivers on Android 14+.
UNEXPECTED_PERMISSIONS=""
while IFS= read -r permission; do
  [[ -z "$permission" ]] && continue
  case "$permission" in
    android.permission.RECORD_AUDIO) ;;
    android.permission.INTERNET) ;;
    "$EXPECTED_PACKAGE".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION) ;;
    *)
      UNEXPECTED_PERMISSIONS+="${UNEXPECTED_PERMISSIONS:+ }$permission"
      ;;
  esac
done <<<"$PERMISSIONS"

if [[ -n "$UNEXPECTED_PERMISSIONS" ]]; then
  fail "APK requests permission(s) outside the least-privilege allowlist: $UNEXPECTED_PERMISSIONS"
fi

# --- Signing posture (report only; debug is expected for debug releases) --
SIGNING="unknown"
if [[ -n "$APKSIGNER_BIN" ]]; then
  CERT_OUTPUT="$("$APKSIGNER_BIN" verify --print-certs "$APK_PATH" 2>&1 || true)"
  if ! "$APKSIGNER_BIN" verify "$APK_PATH" >/dev/null 2>&1; then
    fail "APK signature did not verify with apksigner"
  fi
  if grep -q "CN=Android Debug" <<<"$CERT_OUTPUT"; then
    SIGNING="debug"
  else
    SIGNING="release"
  fi
else
  SIGNING="unverified (apksigner not found)"
fi

PERMISSIONS_CSV="$(printf '%s' "$PERMISSIONS" | paste -sd, - 2>/dev/null || printf '%s' "$PERMISSIONS" | tr '\n' ',')"
PERMISSIONS_CSV="${PERMISSIONS_CSV%,}"

printf 'APK metadata preflight passed.\n'
printf '  apk: %s\n' "$APK_PATH"
printf '  sha256: %s (%s)\n' "$APK_SHA256" "$SHA_STATUS"
printf '  package: %s\n' "$PACKAGE_NAME"
printf '  version: %s (code %s)\n' "$VERSION_NAME" "$VERSION_CODE"
printf '  permissions: %s\n' "$PERMISSIONS_CSV"
printf '  signing: %s\n' "$SIGNING"

if [[ -n "$FACTS_FILE" ]]; then
  mkdir -p "$(dirname "$FACTS_FILE")" >/dev/null 2>&1 || true
  {
    printf 'apk_path=%s\n' "$APK_PATH"
    printf 'apk_sha256=%s\n' "$APK_SHA256"
    printf 'apk_sha256_sidecar=%s\n' "$SHA_STATUS"
    printf 'apk_package=%s\n' "$PACKAGE_NAME"
    printf 'apk_version_name=%s\n' "$VERSION_NAME"
    printf 'apk_version_code=%s\n' "$VERSION_CODE"
    printf 'apk_permissions=%s\n' "$PERMISSIONS_CSV"
    printf 'apk_signing=%s\n' "$SIGNING"
  } >"$FACTS_FILE"
fi
