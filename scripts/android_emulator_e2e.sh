#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="com.tomdf47.realtime_translate_mobile"
MAIN_ACTIVITY=".MainActivity"
DEFAULT_APK="build/app/outputs/flutter-apk/app-debug.apk"
DEFAULT_SECRET_FILE="/home/tom/.openclaw/secrets/realtime-translate-openai-api-key"
DEFAULT_ARTIFACT_DIR="/tmp/realtime-translate-mobile-e2e"
EMULATOR_LOG="/tmp/realtime-translate-emulator.log"

APK_PATH="${APK_PATH:-$DEFAULT_APK}"
SECRET_FILE="${OPENAI_SECRET_FILE:-$DEFAULT_SECRET_FILE}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$DEFAULT_ARTIFACT_DIR}"
USE_LIVE_CREDENTIAL=0
RUN_DEBUG_LIVE_EVENTS=0

usage() {
  cat <<'USAGE'
Usage: scripts/android_emulator_e2e.sh [--with-live-credential] [--debug-live-events] [--apk PATH]

Installs the debug APK on Pixel_9_API_36_Play or an already-connected Android
emulator, drives the phone-local setup flow with UIAutomator/adb, writes
screenshot and UI XML evidence under /tmp, and clears app data afterward.

Options:
  --with-live-credential  Read the OpenAI credential from the local secret file
                          and drive the setup -> permission -> live surface flow.
                          The credential is never printed. App data is cleared.
  --debug-live-events     After reaching the live surface, drive the opt-in
                          debug-only generated-event proof. Build the APK with
                          --dart-define=LIVE_TRANSLATE_DEBUG_E2E=true first.
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

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/share/jdks/temurin-21}"
export PATH="/home/tom/.local/share/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

mkdir -p "$ARTIFACT_DIR"

log() {
  printf '[android-e2e] %s\n' "$*"
}

fail() {
  printf '[android-e2e] ERROR: %s\n' "$*" >&2
  dump_ui_to "$ARTIFACT_DIR/failure-window.xml" || true
  screencap_to "$ARTIFACT_DIR/failure.png" || true
  exit 1
}

first_device() {
  adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }'
}

ADB_SERIAL=""

adb_cmd() {
  if [[ -n "$ADB_SERIAL" ]]; then
    adb -s "$ADB_SERIAL" "$@"
  else
    adb "$@"
  fi
}

ensure_emulator() {
  ADB_SERIAL="$(first_device)"
  if [[ -n "$ADB_SERIAL" ]]; then
    log "Reusing Android device $ADB_SERIAL"
    return
  fi

  log "Starting Pixel_9_API_36_Play in the background; emulator log: $EMULATOR_LOG"
  if command -v android-pixel9-headless >/dev/null 2>&1; then
    nohup android-pixel9-headless >"$EMULATOR_LOG" 2>&1 &
  else
    nohup "$ANDROID_HOME/emulator/emulator" \
      -avd Pixel_9_API_36_Play \
      -qt-hide-window \
      -no-audio \
      -gpu host \
      -no-snapshot \
      -no-metrics \
      >"$EMULATOR_LOG" 2>&1 &
  fi

  adb wait-for-device
  ADB_SERIAL="$(first_device)"
  if [[ -z "$ADB_SERIAL" ]]; then
    fail "adb reported no connected device after emulator startup"
  fi
}

wait_for_boot() {
  log "Waiting for Android boot_completed=1 on $ADB_SERIAL"
  for _ in $(seq 1 180); do
    if [[ "$(adb_cmd shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
      adb_cmd shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
      adb_cmd shell wm dismiss-keyguard >/dev/null 2>&1 || true
      return
    fi
    sleep 1
  done
  fail "emulator did not report boot_completed=1"
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
  if [[ -n "${ADB_SERIAL:-}" ]]; then
    adb_cmd shell pm clear "$PACKAGE_NAME" >/dev/null 2>&1 || true
  fi
}

trap cleanup_app_data EXIT

if [[ ! -f "$APK_PATH" ]]; then
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
wait_for_boot

log "Installing $APK_PATH"
adb_cmd install -r -t "$APK_PATH" >/dev/null
cleanup_app_data

log "Launching $PACKAGE_NAME"
adb_cmd shell am start -n "$PACKAGE_NAME/$MAIN_ACTIVITY" >/dev/null
wait_for_ui "Start new meeting" 60
wait_for_ui "Open meeting history" 10
screencap_to "$ARTIFACT_DIR/01-start.png"
dump_ui_to "$ARTIFACT_DIR/01-start.xml"

log "Verifying missing-credential gate"
tap_ui "Start new meeting"
wait_for_ui "OpenAI setup required" 30
screencap_to "$ARTIFACT_DIR/02-setup-required.png"
dump_ui_to "$ARTIFACT_DIR/02-setup-required.xml"

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
  wait_for_ui "Start new meeting" 15

  log "Starting live surface with runtime microphone permission"
  tap_ui "Start new meeting"
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
  wait_for_ui "Auto-detect Spanish" 5
  wait_for_ui "Stop listening" 5
  screencap_to "$ARTIFACT_DIR/04-live-listening.png"
  dump_ui_to "$ARTIFACT_DIR/04-live-listening.xml"

  if ((RUN_DEBUG_LIVE_EVENTS)); then
    log "Running opt-in debug generated-event proof"
    wait_for_ui "Run debug realtime proof" 10
    tap_ui "Run debug realtime proof"
    wait_for_ui "Debug realtime proof passed: 1 realtime row, 1 audio chunk" 30
    screencap_to "$ARTIFACT_DIR/05-debug-realtime-proof.png"
    dump_ui_to "$ARTIFACT_DIR/05-debug-realtime-proof.xml"
  fi

  log "Opening scoped AI chat sheet without sending a prompt"
  tap_ui "Open AI chat"
  wait_for_ui "AI Chat" 20
  wait_for_ui "This meeting" 10
  screencap_to "$ARTIFACT_DIR/06-ai-chat-this-meeting.png"
  dump_ui_to "$ARTIFACT_DIR/06-ai-chat-this-meeting.xml"
fi

cleanup_app_data
log "E2E complete. Artifacts: $ARTIFACT_DIR"
