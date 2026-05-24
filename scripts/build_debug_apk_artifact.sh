#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_OUTPUT_DIR="/tmp"
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
BUILD_MODE="debug"
ENABLE_DEBUG_LIVE_EVENTS=0
SKIP_BUILD=0

usage() {
  cat <<'USAGE'
Usage: scripts/build_debug_apk_artifact.sh [--debug-live-events] [--output-dir DIR] [--skip-build]

Builds the Android debug APK and copies it to /tmp with a clear filename plus a
SHA-256 sidecar. This script does not read or print OpenAI credentials.

Options:
  --debug-live-events  Build with LIVE_TRANSLATE_DEBUG_E2E=true for the
                       installed-app generated-event E2E proof.
  --output-dir DIR     Directory for copied APK artifacts. Defaults to /tmp.
  --skip-build         Copy the existing Flutter debug APK without rebuilding.
  --help               Show this help.
USAGE
}

while (($#)); do
  case "$1" in
    --debug-live-events)
      ENABLE_DEBUG_LIVE_EVENTS=1
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      if [[ -z "$OUTPUT_DIR" ]]; then
        echo "Missing value for --output-dir" >&2
        exit 2
      fi
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
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

export PATH="/home/tom/.local/share/flutter/bin:$PATH"

cd "$PROJECT_ROOT"

if ((ENABLE_DEBUG_LIVE_EVENTS)); then
  BUILD_ARGS=(build apk --debug --dart-define=LIVE_TRANSLATE_DEBUG_E2E=true)
  BUILD_MODE="debug-live-events"
else
  BUILD_ARGS=(build apk --debug)
fi

if ((SKIP_BUILD == 0)); then
  flutter "${BUILD_ARGS[@]}"
fi

SOURCE_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -f "$SOURCE_APK" ]]; then
  echo "APK not found: $SOURCE_APK" >&2
  echo "Run flutter build apk --debug first or omit --skip-build." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

COMMIT="$(git rev-parse --short HEAD 2>/dev/null || printf 'nogit')"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
APK_NAME="realtime-translate-mobile-${BUILD_MODE}-${COMMIT}-${STAMP}.apk"
DEST_APK="$OUTPUT_DIR/$APK_NAME"
DEST_SHA="$DEST_APK.sha256"

cp "$SOURCE_APK" "$DEST_APK"
sha256sum "$DEST_APK" >"$DEST_SHA"

printf 'APK artifact: %s\n' "$DEST_APK"
printf 'SHA-256 sidecar: %s\n' "$DEST_SHA"
