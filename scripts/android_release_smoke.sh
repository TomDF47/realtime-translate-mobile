#!/usr/bin/env bash
set -euo pipefail

# Repeatable Android release smoke validation (#39).
#
# Default (offline, no-credential) flow:
#   1. Locate or build an APK artifact (debug by default; --release for a
#      release-mode artifact), each with a SHA-256 sidecar.
#   2. APK metadata + signing preflight (scripts/check_apk_metadata.sh).
#   3. Resilient emulator cold boot (scripts/lib/android_emulator_boot.sh) so a
#      flaky cold boot no longer blocks the whole release.
#   4. Install, clear app state, launch, and prove startup reaches a bounded
#      state (the "OpenAI setup required" gate, never stuck on "Preparing live
#      session") via scripts/android_emulator_e2e.sh --verify-offline-startup.
#      With no credential saved the app short-circuits before any OpenAI
#      network call, so the default path reads no credential and is offline.
#   5. Print a sanitized result block and, when explicitly asked, record it to a
#      GitHub release or issue.
#
# The default path reads no OpenAI credential and makes no OpenAI network
# request of any kind. Two network paths are explicit opt-ins:
#   --verify-invalid-credential-recovery : makes a live OpenAI auth-rejection
#       request using a NON-SECRET placeholder credential (no real secret read)
#       to prove fail-closed recovery.
#   --with-live-credential : reads the local secret file and drives the live
#       realtime path with real credentials.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_ARTIFACT_DIR="/tmp/realtime-translate-mobile-release-smoke"
ARTIFACT_DIR="${ARTIFACT_DIR:-$DEFAULT_ARTIFACT_DIR}"
APK_PATH=""
SKIP_BUILD=0
RELEASE_BUILD=0
WITH_LIVE_CREDENTIAL=0
VERIFY_INVALID_CREDENTIAL=0
RECORD_TO_RELEASE=""
RECORD_TO_ISSUE=""

usage() {
  cat <<'USAGE'
Usage: scripts/android_release_smoke.sh [--apk PATH] [--release] [--skip-build]
                                        [--verify-invalid-credential-recovery]
                                        [--with-live-credential]
                                        [--record-to-release TAG]
                                        [--record-to-issue NUMBER]
                                        [--artifact-dir DIR]

Repeatable Android release smoke validation. Builds or locates an APK, runs an
APK metadata + signing preflight, cold-boots the emulator resiliently, installs
the APK, clears app state, and proves startup reaches a bounded state.

By default this is fully offline: with no credential saved the app reaches the
"OpenAI setup required" gate and never stays on "Preparing live session", and no
OpenAI network request is made. Network validation is explicit opt-in only.

Options:
  --apk PATH              Validate this APK instead of building one. Implies no
                          build step.
  --release               When no --apk is given, build a release-mode APK
                          artifact instead of the debug default. Release
                          artifacts are debug-signed and not store-ready unless
                          local android/key.properties is present.
  --skip-build            When no --apk is given, copy the existing Flutter APK
                          for the selected mode instead of rebuilding.
  --verify-invalid-credential-recovery
                          Opt in to the invalid-credential auth-recovery proof.
                          Saves a NON-SECRET placeholder credential and MAKES A
                          LIVE OpenAI AUTH-REJECTION NETWORK REQUEST to prove the
                          app fails closed to setup-required. Reads no real
                          secret. Not part of the default offline path.
  --with-live-credential  Opt in to the live realtime path. Passes
                          --with-live-credential to the E2E driver, which reads
                          the local secret file and makes live OpenAI requests.
                          Off by default.
  --record-to-release TAG Append the sanitized result block to the GitHub
                          release notes for TAG via gh (records pass or fail).
  --record-to-issue NUMBER
                          Post the sanitized result block as a comment on issue
                          NUMBER via gh (records pass or fail).
  --artifact-dir DIR      Directory for artifacts and the result block.
                          Defaults to /tmp/realtime-translate-mobile-release-smoke.
  --help                  Show this help.
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
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --release)
      RELEASE_BUILD=1
      shift
      ;;
    --verify-invalid-credential-recovery)
      VERIFY_INVALID_CREDENTIAL=1
      shift
      ;;
    --with-live-credential)
      WITH_LIVE_CREDENTIAL=1
      shift
      ;;
    --record-to-release)
      RECORD_TO_RELEASE="${2:-}"
      if [[ -z "$RECORD_TO_RELEASE" ]]; then
        echo "Missing value for --record-to-release" >&2
        exit 2
      fi
      shift 2
      ;;
    --record-to-issue)
      RECORD_TO_ISSUE="${2:-}"
      if [[ -z "$RECORD_TO_ISSUE" ]]; then
        echo "Missing value for --record-to-issue" >&2
        exit 2
      fi
      shift 2
      ;;
    --artifact-dir)
      ARTIFACT_DIR="${2:-}"
      if [[ -z "$ARTIFACT_DIR" ]]; then
        echo "Missing value for --artifact-dir" >&2
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

if ((WITH_LIVE_CREDENTIAL)) && ((VERIFY_INVALID_CREDENTIAL)); then
  echo "Choose one network path: --with-live-credential or --verify-invalid-credential-recovery" >&2
  exit 2
fi

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/share/jdks/temurin-21}"
export PATH="/home/tom/.local/share/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# shellcheck source=scripts/lib/android_emulator_boot.sh
source "$SCRIPT_DIR/lib/android_emulator_boot.sh"

cd "$PROJECT_ROOT"
mkdir -p "$ARTIFACT_DIR"

META_FACTS="$ARTIFACT_DIR/apk-metadata-facts.txt"
RESULT_FILE="$ARTIFACT_DIR/release-smoke-result.md"
START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

STEP_BUILD="skipped"
STEP_METADATA="pending"
STEP_BOOT="pending"
STEP_SMOKE="pending"
DEVICE_LINE="not booted"

if ((WITH_LIVE_CREDENTIAL)); then
  MODE_LABEL="live opt-in (reads local secret file; live OpenAI request expected)"
elif ((VERIFY_INVALID_CREDENTIAL)); then
  MODE_LABEL="invalid-credential opt-in (non-secret placeholder; live OpenAI auth-rejection request)"
else
  MODE_LABEL="offline default (no OpenAI credential read; no OpenAI network request)"
fi

log() {
  printf '[release-smoke] %s\n' "$*"
}

warn() {
  printf '[release-smoke] WARN: %s\n' "$*" >&2
}

fail() {
  printf '[release-smoke] ERROR: %s\n' "$*" >&2
  exit 1
}

fact() {
  local key="$1"
  [[ -f "$META_FACTS" ]] || return 0
  awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$META_FACTS"
}

collect_device_facts() {
  local serial model api
  # Prefer the serial captured from the explicit resilient boot step so the
  # result block attributes the proof to the exact device that was booted.
  serial="${ADB_SERIAL:-}"
  if [[ -z "$serial" ]]; then
    serial="$(adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
  fi
  if [[ -z "$serial" ]]; then
    return 0
  fi
  model="$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
  api="$(adb -s "$serial" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)"
  DEVICE_LINE="$serial (${model:-unknown}, API ${api:-unknown})"
}

build_result_block() {
  local overall="$1"
  local apk_name
  apk_name="$(basename "${APK_PATH:-unknown}")"
  collect_device_facts
  {
    printf '## Android release smoke validation\n\n'
    printf -- '- Date (UTC): %s\n' "$START_TS"
    printf -- '- Result: %s\n' "$overall"
    printf -- '- Mode: %s\n' "$MODE_LABEL"
    printf -- '- APK: %s\n' "$apk_name"
    printf -- '- SHA-256: %s\n' "$(fact apk_sha256)"
    printf -- '- SHA-256 sidecar: %s\n' "$(fact apk_sha256_sidecar)"
    printf -- '- Package: %s\n' "$(fact apk_package)"
    printf -- '- Version: %s (code %s)\n' "$(fact apk_version_name)" "$(fact apk_version_code)"
    printf -- '- Permissions: %s\n' "$(fact apk_permissions)"
    printf -- '- Signing: %s\n' "$(fact apk_signing)"
    printf -- '- Device: %s\n' "$DEVICE_LINE"
    printf -- '- Checks:\n'
    printf -- '  - build artifact: %s\n' "$STEP_BUILD"
    printf -- '  - metadata + signing preflight: %s\n' "$STEP_METADATA"
    printf -- '  - resilient emulator boot: %s\n' "$STEP_BOOT"
    printf -- '  - install + bounded-state smoke: %s\n' "$STEP_SMOKE"
    printf -- '- Artifacts (local only): %s\n' "$ARTIFACT_DIR"
  } >"$RESULT_FILE"
}

contains_secret_pattern() {
  grep -Eq '(sk-(proj-)?[A-Za-z0-9_-]{20,}|sess-[A-Za-z0-9_-]{20,}|ek_[A-Za-z0-9_-]{20,}|(AKIA|ASIA)[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "$1"
}

record_result() {
  if [[ -z "$RECORD_TO_RELEASE" && -z "$RECORD_TO_ISSUE" ]]; then
    return 0
  fi
  if contains_secret_pattern "$RESULT_FILE"; then
    warn "refusing to record: result block tripped the secret-pattern scan"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    warn "gh not found; printed result block was not posted"
    return 0
  fi
  if [[ -n "$RECORD_TO_ISSUE" ]]; then
    if gh issue comment "$RECORD_TO_ISSUE" --body-file "$RESULT_FILE" >/dev/null 2>&1; then
      log "Recorded result to issue #$RECORD_TO_ISSUE"
    else
      warn "failed to record result to issue #$RECORD_TO_ISSUE"
    fi
  fi
  if [[ -n "$RECORD_TO_RELEASE" ]]; then
    local existing combined="$ARTIFACT_DIR/release-notes-combined.md"
    existing="$(gh release view "$RECORD_TO_RELEASE" --json body --jq .body 2>/dev/null || true)"
    : >"$combined"
    if [[ -n "$existing" ]]; then
      printf '%s\n\n' "$existing" >>"$combined"
    fi
    cat "$RESULT_FILE" >>"$combined"
    if gh release edit "$RECORD_TO_RELEASE" --notes-file "$combined" >/dev/null 2>&1; then
      log "Recorded result to release $RECORD_TO_RELEASE"
    else
      warn "failed to record result to release $RECORD_TO_RELEASE"
    fi
  fi
}

on_exit() {
  local rc=$?
  local overall="PASS"
  if ((rc != 0)); then
    overall="FAIL"
  fi
  build_result_block "$overall"
  printf '\n'
  cat "$RESULT_FILE"
  record_result
}
trap on_exit EXIT

# --- Step 1: locate or build the APK -------------------------------------
if [[ -n "$APK_PATH" ]]; then
  if [[ ! -f "$APK_PATH" ]]; then
    fail "APK not found: $APK_PATH"
  fi
  STEP_BUILD="skipped (supplied --apk)"
  log "Using supplied APK: $APK_PATH"
else
  build_args=(--output-dir "$ARTIFACT_DIR")
  if ((RELEASE_BUILD)); then
    log "Building release APK artifact under $ARTIFACT_DIR"
    build_args+=(--release)
  else
    log "Building debug APK artifact under $ARTIFACT_DIR"
  fi
  if ((SKIP_BUILD)); then
    build_args+=(--skip-build)
  fi
  if ! build_output="$("$SCRIPT_DIR/build_debug_apk_artifact.sh" "${build_args[@]}")"; then
    STEP_BUILD="fail"
    fail "debug APK artifact build failed"
  fi
  printf '%s\n' "$build_output"
  APK_PATH="$(printf '%s\n' "$build_output" | awk -F': ' '/^APK artifact:/ { print $2; exit }')"
  if [[ -z "$APK_PATH" || ! -f "$APK_PATH" ]]; then
    STEP_BUILD="fail"
    fail "could not determine built APK artifact path"
  fi
  STEP_BUILD="pass"
fi

# --- Step 2: metadata + signing preflight --------------------------------
log "Running APK metadata + signing preflight"
if "$SCRIPT_DIR/check_apk_metadata.sh" --apk "$APK_PATH" --facts-file "$META_FACTS"; then
  STEP_METADATA="pass"
else
  STEP_METADATA="fail"
  fail "APK metadata + signing preflight failed"
fi

# --- Step 3: resilient emulator boot -------------------------------------
# Boot once here and capture the booted serial so it propagates to fact
# collection and the installed-app proof (the E2E driver reuses an exported
# ADB_SERIAL). The boot helper logs to stderr inside the capture subshell while
# only the resolved serial is returned on stdout; a failed boot exits non-zero
# (never hangs) and is attributed as STEP_BOOT=fail.
log "Booting Android target with resilient cold boot (artifacts in $ARTIFACT_DIR)"
ADB_SERIAL=""
if ADB_SERIAL="$(
  EMU_ARTIFACT_DIR="$ARTIFACT_DIR"
  EMU_REQUIRE_DEVICE_AUDIO=0
  emu_resilient_boot >&2
  printf '%s' "$ADB_SERIAL"
)"; then
  STEP_BOOT="pass"
  export ADB_SERIAL
  if [[ -n "$ADB_SERIAL" ]]; then
    log "Booted device: $ADB_SERIAL"
  fi
else
  STEP_BOOT="fail"
  fail "emulator did not reach a booted state; see $ARTIFACT_DIR/emulator-boot-attempt-*.log"
fi

# --- Step 4: install + bounded-state smoke --------------------------------
# Default is the offline bounded-state proof (no credential, no OpenAI request).
# The two network paths are explicit opt-ins and are reflected in MODE_LABEL.
e2e_args=(--apk "$APK_PATH")
if ((WITH_LIVE_CREDENTIAL)); then
  log "Running opt-in live installed-app smoke (reads local secret file; live OpenAI request)"
  e2e_args+=(--with-live-credential)
elif ((VERIFY_INVALID_CREDENTIAL)); then
  log "Running opt-in invalid-credential recovery smoke (non-secret placeholder; live auth-rejection request)"
  e2e_args+=(--verify-invalid-credential-recovery)
else
  log "Running offline install + bounded-state smoke (no credential, no OpenAI request)"
  e2e_args+=(--verify-offline-startup)
fi

if ARTIFACT_DIR="$ARTIFACT_DIR" "$SCRIPT_DIR/android_emulator_e2e.sh" "${e2e_args[@]}"; then
  STEP_SMOKE="pass"
else
  STEP_SMOKE="fail"
  fail "installed-app smoke failed"
fi

log "Android release smoke passed. Artifacts: $ARTIFACT_DIR"
