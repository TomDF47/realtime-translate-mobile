#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="com.tomdf47.realtime_translate_mobile"
MAIN_ACTIVITY=".MainActivity"
DEFAULT_APK="build/app/outputs/flutter-apk/app-debug.apk"
DEFAULT_SECRET_FILE="/home/tom/.openclaw/secrets/realtime-translate-openai-api-key"
DEFAULT_ARTIFACT_DIR="/tmp/realtime-translate-mobile-e2e"
EMULATOR_LOG="/tmp/realtime-translate-emulator.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIO_EMULATOR_LAUNCHER="$SCRIPT_DIR/android_pixel9_host_audio.sh"

APK_PATH="${APK_PATH:-$DEFAULT_APK}"
SECRET_FILE="${OPENAI_SECRET_FILE:-$DEFAULT_SECRET_FILE}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$DEFAULT_ARTIFACT_DIR}"
USE_LIVE_CREDENTIAL=0
RUN_DEBUG_LIVE_EVENTS=0
VERIFY_CREDENTIAL_RESET=0
VERIFY_INVALID_CREDENTIAL_RECOVERY=0
REQUIRE_DEVICE_AUDIO=0
AUDIO_PREFLIGHT_ONLY=0
SHOULD_CLEANUP_APP_DATA=0

usage() {
  cat <<'USAGE'
Usage: scripts/android_emulator_e2e.sh [--with-live-credential] [--debug-live-events] [--verify-credential-reset] [--verify-invalid-credential-recovery] [--require-device-audio] [--audio-preflight-only] [--apk PATH]

Installs the debug APK on Pixel_9_API_36_Play or an already-connected Android
emulator, drives the phone-local setup flow with UIAutomator/adb, writes
screenshot and UI XML evidence under /tmp, and clears app data afterward.

Options:
  --with-live-credential  Read the OpenAI credential from the local secret file
                          and drive the setup -> permission -> live surface flow.
                          The credential is never printed. App data is cleared.
  --debug-live-events     After reaching the live surface, drive the opt-in
                          debug-only generated-event proof, restart the app,
                          and verify persisted meeting history / AI context.
                          Build the APK with
                          --dart-define=LIVE_TRANSLATE_DEBUG_E2E=true first.
  --verify-credential-reset
                          Save a non-secret placeholder credential through the
                          setup UI, remove it, and verify live start returns to
                          the setup-required gate. Does not read live secrets.
  --verify-invalid-credential-recovery
                          Save a non-secret invalid placeholder credential,
                          grant microphone permission, and verify a direct
                          OpenAI auth rejection fails closed to setup-required.
                          Does not read live secrets.
  --require-device-audio  Before installed-app validation, fail if the selected
                          emulator/device is known not to have usable audio.
                          This rejects emulators launched with -no-audio and
                          requires emulator launches to include
                          -allow-host-audio so mic/speaker claims cannot pass
                          silently. Physical devices are accepted.
  --audio-preflight-only  Run only the device-audio preflight and exit. Does not
                          install the APK, read live secrets, or launch the app.
  --apk PATH              APK to install. Defaults to build/app/outputs/flutter-apk/app-debug.apk.
  --help                  Show this help.
USAGE
}

while (($#)); do
  case "$1" in
    --with-live-credential)
      USE_LIVE_CREDENTIAL=1
      shift
      ;;
    --debug-live-events)
      RUN_DEBUG_LIVE_EVENTS=1
      shift
      ;;
    --verify-credential-reset)
      VERIFY_CREDENTIAL_RESET=1
      shift
      ;;
    --verify-invalid-credential-recovery)
      VERIFY_INVALID_CREDENTIAL_RECOVERY=1
      shift
      ;;
    --require-device-audio)
      REQUIRE_DEVICE_AUDIO=1
      shift
      ;;
    --audio-preflight-only)
      AUDIO_PREFLIGHT_ONLY=1
      REQUIRE_DEVICE_AUDIO=1
      shift
      ;;
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

if ((RUN_DEBUG_LIVE_EVENTS)) && ((! USE_LIVE_CREDENTIAL)); then
  echo "--debug-live-events requires --with-live-credential" >&2
  exit 2
fi

if ((USE_LIVE_CREDENTIAL)) && ((VERIFY_INVALID_CREDENTIAL_RECOVERY)); then
  echo "--verify-invalid-credential-recovery cannot be combined with --with-live-credential" >&2
  exit 2
fi

if ((AUDIO_PREFLIGHT_ONLY)) && ((USE_LIVE_CREDENTIAL || RUN_DEBUG_LIVE_EVENTS || VERIFY_CREDENTIAL_RESET || VERIFY_INVALID_CREDENTIAL_RECOVERY)); then
  echo "--audio-preflight-only cannot be combined with app-flow validation options" >&2
  exit 2
fi

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/share/jdks/temurin-21}"
export PATH="/home/tom/.local/share/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# Shared resilient cold-boot helper (#39). Replaces the previous single-shot
# launch + unbounded `adb wait-for-device` with bounded retries and a watchdog.
# shellcheck source=scripts/lib/android_emulator_boot.sh
source "$SCRIPT_DIR/lib/android_emulator_boot.sh"

mkdir -p "$ARTIFACT_DIR"

log() {
  printf '[android-e2e] %s\n' "$*"
}

fail() {
  printf '[android-e2e] ERROR: %s\n' "$*" >&2
  if ((AUDIO_PREFLIGHT_ONLY == 0)); then
    dump_ui_to "$ARTIFACT_DIR/failure-window.xml" || true
    screencap_to "$ARTIFACT_DIR/failure.png" || true
  fi
  exit 1
}

# Device discovery and cold-boot live in scripts/lib/android_emulator_boot.sh.
ADB_SERIAL=""

adb_cmd() {
  if [[ -n "$ADB_SERIAL" ]]; then
    adb -s "$ADB_SERIAL" "$@"
  else
    adb "$@"
  fi
}

ensure_emulator() {
  # Resilient cold boot (#39): reuse an online device or cold-boot the AVD with
  # bounded retries and a process watchdog, setting ADB_SERIAL. emu_resilient_boot
  # exits non-zero instead of hanging when no booted device can be obtained.
  EMU_LOG="$EMULATOR_LOG"
  EMU_ARTIFACT_DIR="$ARTIFACT_DIR"
  EMU_REQUIRE_DEVICE_AUDIO="$REQUIRE_DEVICE_AUDIO"
  EMU_AUDIO_LAUNCHER="$AUDIO_EMULATOR_LAUNCHER"
  emu_resilient_boot
}

selected_device_is_emulator() {
  [[ "$ADB_SERIAL" == emulator-* ]] && return 0
  [[ "$(adb_cmd shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')" == "1" ]]
}

emulator_process_args() {
  local serial_port
  serial_port="${ADB_SERIAL#emulator-}"
  ps -eo comm=,args= |
    awk -v serial="$ADB_SERIAL" -v port="$serial_port" '
      $1 ~ /^(emulator|qemu-system)/ {
        args = substr($0, index($0, $2))
        if (args ~ ("-port " port) || args ~ ("-ports " port ",") || args ~ serial || args ~ "Pixel_9_API_36_Play") {
          print args
        }
      }
    ' |
    head -n 1
}

run_audio_preflight() {
  local report_path model api is_emulator args status detail
  report_path="$ARTIFACT_DIR/audio-preflight.txt"
  model="$(adb_cmd shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
  api="$(adb_cmd shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)"
  is_emulator="false"
  args=""
  status="pass"
  detail="physical device or non-emulator Android device"

  if selected_device_is_emulator; then
    is_emulator="true"
    args="$(emulator_process_args || true)"
    detail="emulator launched with explicit host audio"
    if [[ -z "$args" ]]; then
      status="fail"
      detail="could not inspect emulator process arguments for audio flags"
    elif grep -Fq -- "-no-audio" <<<"$args"; then
      status="fail"
      detail="emulator was launched with -no-audio"
    elif ! grep -Fq -- "-allow-host-audio" <<<"$args"; then
      status="fail"
      detail="emulator was not launched with -allow-host-audio"
    fi
  fi

  {
    printf 'status=%s\n' "$status"
    printf 'device=%s\n' "$ADB_SERIAL"
    printf 'model=%s\n' "$model"
    printf 'api=%s\n' "$api"
    printf 'emulator=%s\n' "$is_emulator"
    printf 'detail=%s\n' "$detail"
    if [[ -n "$args" ]]; then
      printf 'emulator_args=%s\n' "$args"
    fi
  } >"$report_path"

  if [[ "$status" != "pass" ]]; then
    fail "device audio preflight failed: $detail. See $report_path"
  fi
  log "Device audio preflight passed: $detail"
}

dump_ui() {
  local adb_args=()
  if [[ -n "$ADB_SERIAL" ]]; then
    adb_args=(-s "$ADB_SERIAL")
  fi
  timeout 10s adb "${adb_args[@]}" shell uiautomator dump \
    /sdcard/realtime-translate-window.xml >/dev/null 2>&1
  timeout 10s adb "${adb_args[@]}" exec-out cat \
    /sdcard/realtime-translate-window.xml |
    tr -d '\r' |
    sed 's/></>\n</g'
}

dump_ui_to() {
  local path="$1"
  dump_ui >"$path"
}

screencap_to() {
  local path="$1"
  adb_cmd exec-out screencap -p >"$path"
}

wait_for_ui() {
  local needle="$1"
  local timeout_seconds="${2:-40}"
  local deadline=$((SECONDS + timeout_seconds))
  while ((SECONDS < deadline)); do
    if dump_ui | grep -Fq "$needle"; then
      return
    fi
    sleep 1
  done
  dump_ui_to "$ARTIFACT_DIR/wait-timeout-window.xml" || true
  fail "timed out waiting for UI text/content-desc containing: $needle"
}

tap_ui() {
  local needle="$1"
  local xml line bounds x1 y1 x2 y2 x y
  xml="$(dump_ui)"
  line="$(printf '%s\n' "$xml" | grep -F "$needle" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    dump_ui_to "$ARTIFACT_DIR/tap-missing-window.xml" || true
    fail "could not find tappable UI text/content-desc containing: $needle"
  fi
  bounds="$(printf '%s\n' "$line" | sed -n 's/.*bounds="\[\([0-9]\+\),\([0-9]\+\)\]\[\([0-9]\+\),\([0-9]\+\)\]".*/\1 \2 \3 \4/p')"
  if [[ -z "$bounds" ]]; then
    fail "found UI element for '$needle' but could not parse bounds"
  fi
  read -r x1 y1 x2 y2 <<<"$bounds"
  x=$(((x1 + x2) / 2))
  y=$(((y1 + y2) / 2))
  adb_cmd shell input tap "$x" "$y"
}

assert_ui_contains() {
  local needle="$1"
  if ! dump_ui | grep -Fq "$needle"; then
    dump_ui_to "$ARTIFACT_DIR/assert-missing-window.xml" || true
    fail "expected UI text/content-desc containing: $needle"
  fi
}

assert_ui_absent() {
  local needle="$1"
  if dump_ui | grep -Fq "$needle"; then
    dump_ui_to "$ARTIFACT_DIR/assert-unexpected-window.xml" || true
    fail "unexpected UI text/content-desc found: $needle"
  fi
}

assert_active_live_surface() {
  assert_ui_contains "Listening"
  assert_ui_contains "Stop listening"
  assert_ui_contains "Pause listening"
  assert_ui_absent "Auto-detect Spanish"
  assert_ui_absent "Translate Text"
  assert_ui_absent "Read Aloud"
  assert_ui_absent "Pause Read Aloud"
  assert_ui_absent "Resume Read Aloud"
  assert_ui_absent "Speaker Active"
  assert_ui_absent "Headphones Active"
  assert_ui_absent "Switch Direction"
  assert_ui_absent "Open AI chat"
  assert_ui_absent "Generate export"
  assert_ui_absent "Open generated exports"
}

tap_first_edit_text() {
  local xml line bounds x1 y1 x2 y2 x y
  xml="$(dump_ui)"
  line="$(printf '%s\n' "$xml" | grep -F 'class="android.widget.EditText"' | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    dump_ui_to "$ARTIFACT_DIR/edit-text-missing-window.xml" || true
    fail "could not find OpenAI credential text field"
  fi
  bounds="$(printf '%s\n' "$line" | sed -n 's/.*bounds="\[\([0-9]\+\),\([0-9]\+\)\]\[\([0-9]\+\),\([0-9]\+\)\]".*/\1 \2 \3 \4/p')"
  if [[ -z "$bounds" ]]; then
    fail "found EditText but could not parse bounds"
  fi
  read -r x1 y1 x2 y2 <<<"$bounds"
  x=$(((x1 + x2) / 2))
  y=$(((y1 + y2) / 2))
  adb_cmd shell input tap "$x" "$y"
}

enter_secret_text() {
  local value="$1"
  # adb shell input text has a limited character set, but OpenAI keys/session
  # credentials used here are expected to be ASCII token material. The value is
  # passed directly to adb without shell tracing or logging. Send it in chunks
  # because long input text commands can drop characters on some emulator builds.
  local chunk_size=8
  local index=0
  local chunk
  while ((index < ${#value})); do
    chunk="${value:index:chunk_size}"
    adb_cmd shell input text "$chunk"
    index=$((index + chunk_size))
    sleep 0.1
  done
}

enter_adb_text() {
  local value="$1"
  local chunk_size=12
  local index=0
  local chunk
  while ((index < ${#value})); do
    chunk="${value:index:chunk_size}"
    adb_cmd shell input text "$chunk"
    index=$((index + chunk_size))
    sleep 0.1
  done
}

tap_permission_allow_if_present() {
  for label in \
    "While using the app" \
    "While using this app" \
    "Allow" \
    "Only this time"; do
    if dump_ui | grep -Fq "$label"; then
      tap_ui "$label"
      return
    fi
  done
}

cleanup_app_data() {
  if ((SHOULD_CLEANUP_APP_DATA)) && [[ -n "${ADB_SERIAL:-}" ]]; then
    adb_cmd shell pm clear "$PACKAGE_NAME" >/dev/null 2>&1 || true
  fi
}

trap cleanup_app_data EXIT

if ((AUDIO_PREFLIGHT_ONLY == 0)) && [[ ! -f "$APK_PATH" ]]; then
  fail "APK not found: $APK_PATH. Build it first with: flutter build apk --debug"
fi

if ((USE_LIVE_CREDENTIAL)); then
  if [[ ! -r "$SECRET_FILE" ]]; then
    fail "live credential requested, but secret file is not readable: $SECRET_FILE"
  fi
  OPENAI_CREDENTIAL="$(tr -d '\r\n' <"$SECRET_FILE")"
  if [[ -z "$OPENAI_CREDENTIAL" ]]; then
    fail "live credential requested, but secret file is empty"
  fi
else
  OPENAI_CREDENTIAL=""
fi

ensure_emulator

if ((REQUIRE_DEVICE_AUDIO)); then
  run_audio_preflight
fi

if ((AUDIO_PREFLIGHT_ONLY)); then
  log "Audio preflight complete. Artifacts: $ARTIFACT_DIR"
  exit 0
fi

log "Installing $APK_PATH"
adb_cmd install -r -t "$APK_PATH" >/dev/null
SHOULD_CLEANUP_APP_DATA=1
cleanup_app_data

log "Launching $PACKAGE_NAME"
adb_cmd shell am start -n "$PACKAGE_NAME/$MAIN_ACTIVITY" >/dev/null
wait_for_ui "Start interpreter" 60
wait_for_ui "Open meeting history" 10
screencap_to "$ARTIFACT_DIR/01-start.png"
dump_ui_to "$ARTIFACT_DIR/01-start.xml"

log "Verifying missing-credential gate"
tap_ui "Start interpreter"
wait_for_ui "OpenAI setup required" 30
screencap_to "$ARTIFACT_DIR/02-setup-required.png"
dump_ui_to "$ARTIFACT_DIR/02-setup-required.xml"

if ((VERIFY_CREDENTIAL_RESET)); then
  log "Verifying credential reset UX with a non-secret placeholder"
  tap_ui "Open OpenAI setup"
  wait_for_ui "OpenAI setup" 20
  tap_first_edit_text
  enter_adb_text "placeholderlocalcredential"
  sleep 1
  adb_cmd shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  wait_for_ui "Save encrypted credential" 10
  tap_ui "Save encrypted credential"
  wait_for_ui "OpenAI credential stored on this device" 30
  if dump_ui | grep -Fq "placeholderlocalcredential"; then
    fail "placeholder credential was visible after save"
  fi
  screencap_to "$ARTIFACT_DIR/03-credential-reset-saved.png"
  dump_ui_to "$ARTIFACT_DIR/03-credential-reset-saved.xml"
  tap_ui "Remove credential from this device"
  wait_for_ui "OpenAI setup required" 30
  if dump_ui | grep -Fq "Remove credential from this device"; then
    fail "credential removal button remained visible after reset"
  fi
  screencap_to "$ARTIFACT_DIR/04-credential-reset-removed.png"
  dump_ui_to "$ARTIFACT_DIR/04-credential-reset-removed.xml"
  tap_ui "Close OpenAI setup"
  wait_for_ui "OpenAI setup required" 10
  tap_ui "Back to start"
  wait_for_ui "Start interpreter" 15
  tap_ui "Start interpreter"
  wait_for_ui "OpenAI setup required" 30
  screencap_to "$ARTIFACT_DIR/05-credential-reset-gate.png"
  dump_ui_to "$ARTIFACT_DIR/05-credential-reset-gate.xml"
fi

if ((VERIFY_INVALID_CREDENTIAL_RECOVERY)); then
  log "Verifying invalid credential recovery with a non-secret placeholder"
  tap_ui "Open OpenAI setup"
  wait_for_ui "OpenAI setup" 20
  tap_first_edit_text
  enter_adb_text "invalidlocalcredential"
  sleep 1
  adb_cmd shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  wait_for_ui "Save encrypted credential" 10
  tap_ui "Save encrypted credential"
  wait_for_ui "OpenAI credential stored on this device" 30
  if dump_ui | grep -Fq "invalidlocalcredential"; then
    fail "invalid placeholder credential was visible after save"
  fi
  screencap_to "$ARTIFACT_DIR/03-invalid-credential-saved.png"
  dump_ui_to "$ARTIFACT_DIR/03-invalid-credential-saved.xml"
  tap_ui "Close OpenAI setup"
  wait_for_ui "OpenAI setup required" 10
  tap_ui "Back to start"
  wait_for_ui "Start interpreter" 15

  log "Starting live path with invalid placeholder credential"
  adb_cmd shell pm grant "$PACKAGE_NAME" android.permission.RECORD_AUDIO \
    >/dev/null 2>&1 || true
  tap_ui "Start interpreter"
  # Startup must reach a bounded recovery state instead of hanging on the
  # connecting screen. #37 bounds the initial realtime connect to ~12s, so this
  # is the no-secret proof (#39) that startup never stays on the
  # "Preparing live session" surface indefinitely.
  wait_for_ui "OpenAI credential expired or was rejected" 45
  wait_for_ui "OpenAI setup required" 5
  assert_ui_absent "Preparing live session"
  screencap_to "$ARTIFACT_DIR/04-invalid-credential-recovery.png"
  dump_ui_to "$ARTIFACT_DIR/04-invalid-credential-recovery.xml"
fi

if ((USE_LIVE_CREDENTIAL)); then
  log "Saving live credential through the app UI without printing it"
  tap_ui "Open OpenAI setup"
  wait_for_ui "OpenAI setup" 20
  tap_first_edit_text
  enter_secret_text "$OPENAI_CREDENTIAL"
  sleep 1
  adb_cmd shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  wait_for_ui "Save encrypted credential" 10
  tap_ui "Save encrypted credential"
  wait_for_ui "OpenAI credential stored on this device" 30
  screencap_to "$ARTIFACT_DIR/03-credential-saved.png"
  dump_ui_to "$ARTIFACT_DIR/03-credential-saved.xml"
  tap_ui "Close OpenAI setup"
  wait_for_ui "OpenAI setup required" 10
  tap_ui "Back to start"
  wait_for_ui "Start interpreter" 15

  log "Starting live surface with runtime microphone permission"
  tap_ui "Start interpreter"
  for _ in $(seq 1 90); do
    ui="$(dump_ui || true)"
    if printf '%s\n' "$ui" | grep -Fq "OpenAI credential expired or was rejected"; then
      fail "OpenAI rejected the credential during installed-app realtime startup"
    fi
    tap_permission_allow_if_present
    ui="$(dump_ui || true)"
    if printf '%s\n' "$ui" | grep -Fq "Listening"; then
      break
    fi
    sleep 1
  done
  wait_for_ui "Listening" 5
  wait_for_ui "Stop listening" 5
  assert_active_live_surface
  screencap_to "$ARTIFACT_DIR/04-live-listening.png"
  dump_ui_to "$ARTIFACT_DIR/04-live-listening.xml"

  log "Verifying live menu does not expose hidden live controls"
  tap_ui "Open menu"
  wait_for_ui "Meeting history" 10
  assert_ui_absent "Generate export"
  assert_ui_absent "Open generated exports"
  assert_ui_absent "Open AI chat"
  screencap_to "$ARTIFACT_DIR/05-live-menu-hidden-controls.png"
  dump_ui_to "$ARTIFACT_DIR/05-live-menu-hidden-controls.xml"
  adb_cmd shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  wait_for_ui "Listening" 10
  assert_active_live_surface

  if ((RUN_DEBUG_LIVE_EVENTS)); then
    log "Running opt-in debug generated-event proof"
    wait_for_ui "Run debug realtime proof" 10
    tap_ui "Run debug realtime proof"
    wait_for_ui "Debug realtime proof passed: 1 realtime row, 1 audio chunk" 30
    screencap_to "$ARTIFACT_DIR/05-debug-realtime-proof.png"
    dump_ui_to "$ARTIFACT_DIR/05-debug-realtime-proof.xml"

    log "Restarting app to verify persisted debug proof row"
    adb_cmd shell am force-stop "$PACKAGE_NAME" >/dev/null
    adb_cmd shell am start -n "$PACKAGE_NAME/$MAIN_ACTIVITY" >/dev/null
    wait_for_ui "Start interpreter" 30
    wait_for_ui "Open meeting history" 10
    tap_ui "Open meeting history"
    wait_for_ui "Project timeline review" 20
    wait_for_ui "4 transcript lines" 10
    screencap_to "$ARTIFACT_DIR/06-debug-realtime-proof-history-after-restart.png"
    dump_ui_to "$ARTIFACT_DIR/06-debug-realtime-proof-history-after-restart.xml"

    log "Reopening persisted meeting and verifying hidden controls stay hidden"
    tap_ui "Project timeline review"
    wait_for_ui "Listening" 30
    assert_active_live_surface
    screencap_to "$ARTIFACT_DIR/07-reopened-live-hidden-controls.png"
    dump_ui_to "$ARTIFACT_DIR/07-reopened-live-hidden-controls.xml"
  fi

  log "Opening scoped AI chat sheet from meeting history without sending a prompt"
  tap_ui "Open menu"
  wait_for_ui "Meeting history" 10
  tap_ui "Meeting history"
  wait_for_ui "Ask across meetings" 20
  tap_ui "Ask across meetings"
  wait_for_ui "AI Chat" 20
  wait_for_ui "All meetings" 10
  screencap_to "$ARTIFACT_DIR/06-ai-chat-all-meetings.png"
  dump_ui_to "$ARTIFACT_DIR/06-ai-chat-all-meetings.xml"
fi

cleanup_app_data
log "E2E complete. Artifacts: $ARTIFACT_DIR"
