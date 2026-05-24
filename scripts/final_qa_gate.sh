#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_OUTPUT_DIR="/tmp"
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
RUN_EMULATOR_SMOKE=0
REQUIRE_STORE_SIGNING=0

usage() {
  cat <<'USAGE'
Usage: scripts/final_qa_gate.sh [--emulator-smoke] [--require-store-signing] [--output-dir DIR]

Runs the non-live final QA gate for local handoff:
  - flutter pub get
  - flutter analyze
  - flutter test
  - docs and supply-chain gates
  - shell syntax checks for repo scripts
  - git diff --check
  - fresh debug and release APK handoff artifacts with SHA-256 sidecars

The gate does not read, export, print, or pass OpenAI credentials. Release
artifacts keep the signing status in the filename through
scripts/build_debug_apk_artifact.sh. If android/key.properties is absent, the
release artifact is debug-signed and not store-ready.

Options:
  --emulator-smoke  Install the fresh release artifact and verify the
                    no-credential setup-required gate. This makes no live
                    OpenAI request and does not read the local secret file.
  --require-store-signing
                    Require local release-signing config before building the
                    release artifact, then verify the release APK is not
                    debug-signed. Use for store-ready preflight only.
  --output-dir DIR  Directory for copied APK artifacts. Defaults to /tmp.
  --help           Show this help.
USAGE
}

while (($#)); do
  case "$1" in
    --emulator-smoke)
      RUN_EMULATOR_SMOKE=1
      shift
      ;;
    --require-store-signing)
      REQUIRE_STORE_SIGNING=1
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
mkdir -p "$OUTPUT_DIR"

log() {
  printf '[final-qa] %s\n' "$*"
}

run_step() {
  log "$*"
  "$@"
}

extract_apk_path() {
  awk -F': ' '/^APK artifact:/ { print $2; exit }'
}

if ((REQUIRE_STORE_SIGNING)); then
  run_step scripts/check_android_release_signing.sh
fi

log "Running non-live repository gates"
run_step flutter pub get
run_step flutter analyze
run_step flutter test
run_step bash scripts/check-docs.sh
run_step bash scripts/check-supply-chain.sh
run_step bash -n scripts/build_debug_apk_artifact.sh
run_step bash -n scripts/android_emulator_e2e.sh
run_step bash -n scripts/check-docs.sh
run_step bash -n scripts/check-supply-chain.sh
run_step bash -n scripts/check_android_release_signing.sh
run_step bash -n scripts/final_qa_gate.sh
run_step git diff --check

log "Building fresh debug APK handoff artifact"
debug_output="$(scripts/build_debug_apk_artifact.sh --output-dir "$OUTPUT_DIR")"
printf '%s\n' "$debug_output"
debug_apk="$(printf '%s\n' "$debug_output" | extract_apk_path)"
if [[ -z "$debug_apk" || ! -f "$debug_apk" ]]; then
  echo "Could not determine debug APK artifact path" >&2
  exit 1
fi

log "Building fresh release APK handoff artifact"
release_output="$(scripts/build_debug_apk_artifact.sh --release --output-dir "$OUTPUT_DIR")"
printf '%s\n' "$release_output"
release_apk="$(printf '%s\n' "$release_output" | extract_apk_path)"
if [[ -z "$release_apk" || ! -f "$release_apk" ]]; then
  echo "Could not determine release APK artifact path" >&2
  exit 1
fi

if ((REQUIRE_STORE_SIGNING)); then
  run_step scripts/check_android_release_signing.sh --apk "$release_apk"
fi

if ((RUN_EMULATOR_SMOKE)); then
  log "Running no-live installed-app smoke against the release artifact"
  ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/realtime-translate-mobile-e2e-final-qa}" \
    scripts/android_emulator_e2e.sh --apk "$release_apk"
fi

log "Final QA gate passed"
printf 'Debug APK: %s\n' "$debug_apk"
printf 'Debug SHA-256 sidecar: %s.sha256\n' "$debug_apk"
printf 'Release APK: %s\n' "$release_apk"
printf 'Release SHA-256 sidecar: %s.sha256\n' "$release_apk"
