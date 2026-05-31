#!/usr/bin/env bash
set -euo pipefail

# Repeatable Android release smoke validation (#39).
#
# Default (no-secret) flow:
#   1. Locate or build a debug APK artifact (with a SHA-256 sidecar).
#   2. APK metadata + signing preflight (scripts/check_apk_metadata.sh).
#   3. Resilient emulator cold boot (scripts/lib/android_emulator_boot.sh) so a
#      flaky cold boot no longer blocks the whole release.
#   4. Install, clear app state, launch, verify the missing-credential gate, and
#      prove startup reaches a bounded state (never stuck on
#      "Preparing live session") via
#      scripts/android_emulator_e2e.sh --verify-invalid-credential-recovery.
#   5. Print a sanitized result block and, when explicitly asked, record it to a
#      GitHub release or issue.
#
# The default path reads no OpenAI credential and makes no live OpenAI request.
# Live realtime validation stays opt-in via --with-live-credential, which is
# passed through to the E2E driver and reads the local secret file only then.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_ARTIFACT_DIR="/tmp/realtime-translate-mobile-release-smoke"
ARTIFACT_DIR="${ARTIFACT_DIR:-$DEFAULT_ARTIFACT_DIR}"
APK_PATH=""
SKIP_BUILD=0
WITH_LIVE_CREDENTIAL=0
RECORD_TO_RELEASE=""
RECORD_TO_ISSUE=""

usage() {
  cat <<'USAGE'
Usage: scripts/android_release_smoke.sh [--apk PATH] [--skip-build]
                                        [--with-live-credential]
                                        [--record-to-release TAG]
                                        [--record-to-issue NUMBER]
                                        [--artifact-dir DIR]

Repeatable Android release smoke validation. Builds or locates a debug APK,
runs an APK metadata + signing preflight, cold-boots the emulator resiliently,
installs the APK, clears app state, and proves startup reaches a bounded state
without a real OpenAI credential.

Options:
  --apk PATH              Validate this APK instead of building one. Implies no
                          build step.
  --skip-build            When no --apk is given, copy the existing Flutter
                          debug APK instead of rebuilding.
  --with-live-credential  Opt in to the live realtime path. Passes
                          --with-live-credential to the E2E driver, which reads
                          the local secret file. Off by default; the default
                          path makes no live OpenAI request.
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
else
  MODE_LABEL="no-secret (no OpenAI credential read; no live OpenAI request)"
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
  serial="$(adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
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
  log "Building debug APK artifact under $ARTIFACT_DIR"
  build_args=(--output-dir "$ARTIFACT_DIR")
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
log "Booting Android target with resilient cold boot (artifacts in $ARTIFACT_DIR)"
if (
  EMU_ARTIFACT_DIR="$ARTIFACT_DIR"
  EMU_REQUIRE_DEVICE_AUDIO=0
  emu_resilient_boot
); then
  STEP_BOOT="pass"
else
  STEP_BOOT="fail"
  fail "emulator did not reach a booted state; see $ARTIFACT_DIR/emulator-boot-attempt-*.log"
fi

# --- Step 4: install + no-secret bounded-state smoke ----------------------
e2e_args=(--apk "$APK_PATH")
if ((WITH_LIVE_CREDENTIAL)); then
  log "Running opt-in live installed-app smoke (reads local secret file)"
  e2e_args+=(--with-live-credential)
else
  log "Running no-secret install + bounded-state smoke"
  e2e_args+=(--verify-invalid-credential-recovery)
fi

if ARTIFACT_DIR="$ARTIFACT_DIR" "$SCRIPT_DIR/android_emulator_e2e.sh" "${e2e_args[@]}"; then
  STEP_SMOKE="pass"
else
  STEP_SMOKE="fail"
  fail "installed-app smoke failed"
fi

log "Android release smoke passed. Artifacts: $ARTIFACT_DIR"
