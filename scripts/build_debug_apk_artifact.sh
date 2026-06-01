#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_OUTPUT_DIR="/tmp"
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
BUILD_MODE="debug"
REQUESTED_MODE="debug"
ENABLE_DEBUG_LIVE_EVENTS=0
SKIP_BUILD=0
SIGNING_NOTE="debug build"

usage() {
  cat <<'USAGE'
Usage: scripts/build_debug_apk_artifact.sh [--release] [--debug-live-events] [--output-dir DIR] [--skip-build]

Builds an Android APK and copies it to /tmp with a clear filename plus a
SHA-256 sidecar. Debug is the default. Release mode reports whether it used
local release signing or the debug-signing fallback. This script does not read
or print OpenAI credentials.

Options:
  --release            Build a release APK. If android/key.properties is absent,
                       the project currently uses debug signing as a local
                       fallback, and the artifact filename will say so.
  --debug-live-events  Build with LIVE_TRANSLATE_DEBUG_E2E=true for the
                       installed-app generated-event E2E proof. Debug only.
  --output-dir DIR     Directory for copied APK artifacts. Defaults to /tmp.
  --skip-build         Copy the existing Flutter debug APK without rebuilding.
  --help               Show this help.
USAGE
}

while (($#)); do
  case "$1" in
    --release)
      REQUESTED_MODE="release"
      shift
      ;;
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

if [[ "$REQUESTED_MODE" == "release" ]] && ((ENABLE_DEBUG_LIVE_EVENTS)); then
  echo "--debug-live-events is only valid for debug APK artifacts." >&2
  exit 2
fi

if [[ "$REQUESTED_MODE" == "release" ]]; then
  BUILD_ARGS=(build apk --release)
  SOURCE_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"
  if [[ -f "$PROJECT_ROOT/android/key.properties" ]]; then
    BUILD_MODE="release-local-signed"
    SIGNING_NOTE="release build using local android/key.properties"
  else
    BUILD_MODE="release-debug-signed"
    SIGNING_NOTE="release build using debug signing fallback; not store-ready"
  fi
elif ((ENABLE_DEBUG_LIVE_EVENTS)); then
  BUILD_ARGS=(build apk --debug --dart-define=LIVE_TRANSLATE_DEBUG_E2E=true)
  SOURCE_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
  BUILD_MODE="debug-live-events"
else
  BUILD_ARGS=(build apk --debug)
  SOURCE_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
fi

if ((SKIP_BUILD == 0)); then
  flutter "${BUILD_ARGS[@]}"
fi

if [[ ! -f "$SOURCE_APK" ]]; then
  echo "APK not found: $SOURCE_APK" >&2
  echo "Run the matching flutter build command first or omit --skip-build." >&2
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
printf 'Signing note: %s\n' "$SIGNING_NOTE"

# Tester guidance. A debug-signed "release" artifact has repeatedly failed to
# install/run for testers on real devices (e.g. Play Protect rejecting a
# debug-signed build that presents as a release), even though it boots on the
# emulator. The debug APK is the supported installed-test artifact. Do not hand
# the release-debug-signed APK to a tester; keep it for store-signing rehearsal
# only until real local release-signing material exists (#24).
if [[ "$BUILD_MODE" == "release-debug-signed" ]]; then
  printf '\n'
  printf 'TESTER GUIDANCE: This is a debug-signed release artifact for signing\n'
  printf 'rehearsal only. Do NOT distribute it for installed device testing;\n'
  printf 'debug-signed release builds have failed to install/run for testers.\n'
  printf 'Build and share the debug APK instead:\n'
  printf '  scripts/build_debug_apk_artifact.sh\n'
elif [[ "$BUILD_MODE" == "release-local-signed" ]]; then
  printf '\n'
  printf 'TESTER GUIDANCE: Store-signed release artifact. For ad-hoc installed\n'
  printf 'testing prefer the debug APK unless a store-signed build is required.\n'
else
  printf '\n'
  printf 'TESTER GUIDANCE: Debug APK — this is the supported installed-test\n'
  printf 'artifact for ad-hoc device testing.\n'
fi
