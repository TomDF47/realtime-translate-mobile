#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_PROPERTIES="$PROJECT_ROOT/android/key.properties"
APK_PATH=""

usage() {
  cat <<'USAGE'
Usage: scripts/check_android_release_signing.sh [--apk APK_PATH]

Validates local Android release-signing readiness without printing signing
secrets. The check requires android/key.properties, required signing fields, a
real keystore file, and a keystore path that is either outside the repo or
ignored by git. When --apk is supplied, it also verifies the APK signature and
fails if the artifact is debug-signed.

Options:
  --apk APK_PATH  Verify a built APK is signed and not Android debug-signed.
  --help          Show this help.
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

fail() {
  printf 'Store signing preflight failed: %s\n' "$*" >&2
  exit 1
}

resolve_path() {
  local raw_path="$1"
  if [[ "$raw_path" = /* ]]; then
    printf '%s\n' "$raw_path"
  elif [[ -e "$PROJECT_ROOT/android/app/$raw_path" ]]; then
    printf '%s\n' "$PROJECT_ROOT/android/app/$raw_path"
  elif [[ -e "$PROJECT_ROOT/android/$raw_path" ]]; then
    printf '%s\n' "$PROJECT_ROOT/android/$raw_path"
  else
    printf '%s\n' "$PROJECT_ROOT/$raw_path"
  fi
}

read_property() {
  local key="$1"
  awk -F= -v wanted="$key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      raw_key = $1
      sub(/^[[:space:]]+/, "", raw_key)
      sub(/[[:space:]]+$/, "", raw_key)
      if (raw_key == wanted) {
        $1 = ""
        sub(/^=/, "")
        sub(/^[[:space:]]+/, "")
        sub(/[[:space:]]+$/, "")
        print
        exit
      }
    }
  ' "$KEY_PROPERTIES"
}

reject_placeholder() {
  local field="$1"
  local value="$2"
  if [[ "$value" == *"<"* || "$value" == *">"* || "$value" == "TODO"* || "$value" == "todo"* ]]; then
    fail "$field still looks like a placeholder"
  fi
}

if [[ ! -f "$KEY_PROPERTIES" ]]; then
  fail "android/key.properties is missing. Copy android/key.properties.example locally and fill it with uncommitted release-signing values before a store-ready build."
fi

required_fields=(storePassword keyPassword keyAlias storeFile)
for field in "${required_fields[@]}"; do
  value="$(read_property "$field")"
  if [[ -z "$value" ]]; then
    fail "android/key.properties is missing required field '$field'"
  fi
  reject_placeholder "$field" "$value"
done

store_file_raw="$(read_property storeFile)"
store_file="$(resolve_path "$store_file_raw")"

if [[ ! -f "$store_file" ]]; then
  fail "storeFile does not reference an existing keystore file"
fi

store_file_real="$(realpath "$store_file")"
project_real="$(realpath "$PROJECT_ROOT")"

case "$store_file_real" in
  "$project_real"/*)
    if git -C "$PROJECT_ROOT" ls-files --error-unmatch "$store_file_real" >/dev/null 2>&1; then
      fail "storeFile points to a tracked file inside the repo"
    fi
    if ! git -C "$PROJECT_ROOT" check-ignore -q "$store_file_real"; then
      fail "storeFile is inside the repo but is not ignored by git; move it outside the repo or add a narrow ignore rule before creating the local file"
    fi
    ;;
esac

if [[ -n "$APK_PATH" ]]; then
  if [[ ! -f "$APK_PATH" ]]; then
    fail "APK not found for signature verification"
  fi

  apksigner_bin="${APKSIGNER:-}"
  if [[ -z "$apksigner_bin" ]]; then
    apksigner_bin="$(command -v apksigner || true)"
  fi
  if [[ -z "$apksigner_bin" && -d "${ANDROID_HOME:-}" ]]; then
    apksigner_bin="$(find "$ANDROID_HOME/build-tools" -path '*/apksigner' -type f 2>/dev/null | sort | tail -1)"
  fi
  if [[ -z "$apksigner_bin" && -d "$HOME/Android/Sdk" ]]; then
    apksigner_bin="$(find "$HOME/Android/Sdk/build-tools" -path '*/apksigner' -type f 2>/dev/null | sort | tail -1)"
  fi
  if [[ -z "$apksigner_bin" ]]; then
    fail "apksigner was not found; cannot verify APK signing status"
  fi

  cert_output="$("$apksigner_bin" verify --print-certs "$APK_PATH")"
  if [[ "$cert_output" == *"CN=Android Debug"* ]]; then
    fail "APK is signed with the Android debug certificate, not a local release certificate"
  fi
fi

printf 'Store signing preflight passed: local release signing config is present'
if [[ -n "$APK_PATH" ]]; then
  printf ' and APK is not debug-signed'
fi
printf '.\n'
