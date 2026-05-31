#!/usr/bin/env bash
# Resilient Android emulator boot helper for the realtime-translate-mobile
# Android release smoke flow. This file is meant to be sourced, not executed.
#
# The historical failure (#39) was a single-shot cold boot of
# Pixel_9_API_36_Play followed by an unbounded `adb wait-for-device`: when the
# emulator died during cold boot the smoke either hung or failed with no clean,
# repeatable outcome. This helper replaces that with:
#   - reuse of an already-online device when present,
#   - bounded cold-boot attempts with a process watchdog and adb state checks,
#   - clean, fast failure plus an emulator log tail when every attempt fails.
#
# Public API (functions):
#   emu_resilient_boot   Ensure ADB_SERIAL points at a booted device or exit 1.
#
# On success it sets the caller-visible global ADB_SERIAL to the booted serial.
#
# Configuration (environment variables, all optional):
#   EMU_AVD_NAME             AVD to launch (default Pixel_9_API_36_Play).
#   EMU_BOOT_ATTEMPTS        Cold-boot attempts before giving up (default 3).
#   EMU_BOOT_TIMEOUT         Seconds allowed per attempt to reach boot
#                            completion (default 120).
#   EMU_LOG                  Emulator stdout/stderr log path
#                            (default /tmp/realtime-translate-emulator.log).
#   EMU_ARTIFACT_DIR         Directory for per-attempt boot log tails
#                            (default $ARTIFACT_DIR or
#                            /tmp/realtime-translate-mobile-e2e).
#   EMU_REQUIRE_DEVICE_AUDIO 1 to prefer the repo-local host-audio launcher.
#   EMU_AUDIO_LAUNCHER       Path to android_pixel9_host_audio.sh.
#   EMU_HEADLESS_LAUNCHER    Command name for the global headless launcher
#                            (default android-pixel9-headless).
#
# This helper never reads OpenAI credentials, never prints app payloads, and
# only ever kills emulator/qemu processes whose arguments name EMU_AVD_NAME.

EMU_AVD_NAME="${EMU_AVD_NAME:-Pixel_9_API_36_Play}"
EMU_BOOT_ATTEMPTS="${EMU_BOOT_ATTEMPTS:-3}"
EMU_BOOT_TIMEOUT="${EMU_BOOT_TIMEOUT:-120}"
EMU_LOG="${EMU_LOG:-/tmp/realtime-translate-emulator.log}"
EMU_ARTIFACT_DIR="${EMU_ARTIFACT_DIR:-${ARTIFACT_DIR:-/tmp/realtime-translate-mobile-e2e}}"
EMU_REQUIRE_DEVICE_AUDIO="${EMU_REQUIRE_DEVICE_AUDIO:-0}"
EMU_HEADLESS_LAUNCHER="${EMU_HEADLESS_LAUNCHER:-android-pixel9-headless}"

emu_log() {
  printf '[emu-boot] %s\n' "$*"
}

emu_warn() {
  printf '[emu-boot] WARN: %s\n' "$*" >&2
}

emu_die() {
  printf '[emu-boot] ERROR: %s\n' "$*" >&2
  exit 1
}

# Print the serial of the first device adb reports as fully online ("device").
# Offline, unauthorized, and booting transports are intentionally skipped.
emu_first_online_device() {
  adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1; exit }'
}

emu_device_state() {
  local serial="$1"
  adb -s "$serial" get-state 2>/dev/null | tr -d '\r'
}

# Print PIDs of emulator/qemu processes whose arguments name the target AVD.
# Matching on the executable basename avoids matching launcher shells, this
# script, awk, or grep, so the watchdog and kill paths stay narrowly scoped.
emu_avd_process_pids() {
  ps -eo pid=,args= 2>/dev/null | awk -v avd="$EMU_AVD_NAME" '
    index($0, avd) == 0 { next }
    {
      exe = $2
      sub(/.*\//, "", exe)
      if (exe ~ /^(emulator|emulator64|qemu-system|crosvm)/) {
        print $1
      }
    }
  '
}

emu_avd_process_alive() {
  [[ -n "$(emu_avd_process_pids)" ]]
}

emu_kill_avd_processes() {
  local pids
  pids="$(emu_avd_process_pids)"
  if [[ -z "$pids" ]]; then
    return 0
  fi
  emu_log "Stopping stale $EMU_AVD_NAME emulator process(es): $(tr '\n' ' ' <<<"$pids")"
  # shellcheck disable=SC2086
  kill $pids >/dev/null 2>&1 || true
  for _ in $(seq 1 10); do
    emu_avd_process_alive || return 0
    sleep 1
  done
  pids="$(emu_avd_process_pids)"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids >/dev/null 2>&1 || true
    sleep 1
  fi
}

# Remove stale AVD lock files only when no emulator process owns the AVD. A
# dead cold boot can leave *.lock files behind that block the next launch.
emu_clear_stale_locks() {
  local avd_dir="${ANDROID_AVD_HOME:-$HOME/.android/avd}/${EMU_AVD_NAME}.avd"
  if [[ ! -d "$avd_dir" ]]; then
    return 0
  fi
  if emu_avd_process_alive; then
    return 0
  fi
  local lock
  shopt -s nullglob
  for lock in "$avd_dir"/*.lock; do
    rm -f "$lock" >/dev/null 2>&1 || true
  done
  shopt -u nullglob
}

emu_reset_adb() {
  adb kill-server >/dev/null 2>&1 || true
  adb start-server >/dev/null 2>&1 || true
}

emu_launch() {
  local audio_launcher="${EMU_AUDIO_LAUNCHER:-}"
  if ((EMU_REQUIRE_DEVICE_AUDIO)) && [[ -n "$audio_launcher" && -x "$audio_launcher" ]]; then
    emu_log "Launching $EMU_AVD_NAME with the repo-local host-audio launcher"
    nohup "$audio_launcher" >"$EMU_LOG" 2>&1 &
  elif command -v "$EMU_HEADLESS_LAUNCHER" >/dev/null 2>&1; then
    emu_log "Launching $EMU_AVD_NAME with $EMU_HEADLESS_LAUNCHER"
    nohup "$EMU_HEADLESS_LAUNCHER" >"$EMU_LOG" 2>&1 &
  else
    emu_log "Launching $EMU_AVD_NAME with the direct emulator command"
    nohup "${ANDROID_HOME:-$HOME/Android/Sdk}/emulator/emulator" \
      -avd "$EMU_AVD_NAME" \
      -qt-hide-window \
      -no-audio \
      -gpu host \
      -no-snapshot \
      -no-metrics \
      >"$EMU_LOG" 2>&1 &
  fi
  disown >/dev/null 2>&1 || true
}

emu_capture_boot_log() {
  local attempt="$1"
  mkdir -p "$EMU_ARTIFACT_DIR" >/dev/null 2>&1 || true
  if [[ -f "$EMU_LOG" ]]; then
    tail -n 80 "$EMU_LOG" >"$EMU_ARTIFACT_DIR/emulator-boot-attempt-${attempt}.log" 2>/dev/null || true
  fi
}

emu_wake_device() {
  local serial="$1"
  adb -s "$serial" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb -s "$serial" shell wm dismiss-keyguard >/dev/null 2>&1 || true
}

emu_boot_completed() {
  local serial="$1"
  [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]
}

# Wait up to EMU_BOOT_TIMEOUT seconds for a freshly launched emulator to come
# online and finish booting. Returns 1 if the emulator process dies after being
# observed, if no device comes online, or if boot does not complete in time.
emu_wait_online_and_boot() {
  local deadline=$((SECONDS + EMU_BOOT_TIMEOUT))
  local seen_alive=0
  local serial=""

  while ((SECONDS < deadline)); do
    if emu_avd_process_alive; then
      seen_alive=1
    elif ((seen_alive)); then
      emu_warn "emulator process for $EMU_AVD_NAME exited during boot"
      return 1
    fi
    serial="$(emu_first_online_device)"
    if [[ -n "$serial" ]]; then
      break
    fi
    sleep 2
  done

  if [[ -z "$serial" ]]; then
    emu_warn "no device reached the online state within ${EMU_BOOT_TIMEOUT}s"
    return 1
  fi

  ADB_SERIAL="$serial"
  while ((SECONDS < deadline)); do
    if ! emu_avd_process_alive; then
      emu_warn "emulator process for $EMU_AVD_NAME exited before boot completion"
      return 1
    fi
    if [[ "$(emu_device_state "$serial")" != "device" ]]; then
      sleep 1
      continue
    fi
    if emu_boot_completed "$serial"; then
      return 0
    fi
    sleep 2
  done

  emu_warn "device $serial did not report boot_completed=1 within ${EMU_BOOT_TIMEOUT}s"
  return 1
}

# Ensure ADB_SERIAL points at a booted device. Reuses an already-online device,
# otherwise cold-boots the AVD with bounded retries. Exits 1 (never hangs) if no
# booted device can be obtained.
emu_resilient_boot() {
  mkdir -p "$EMU_ARTIFACT_DIR" >/dev/null 2>&1 || true

  local existing
  existing="$(emu_first_online_device)"
  if [[ -n "$existing" ]]; then
    emu_log "Reusing online Android device $existing"
    ADB_SERIAL="$existing"
    if emu_boot_completed "$existing" || emu_wait_online_and_boot; then
      emu_wake_device "$ADB_SERIAL"
      emu_log "Android device $ADB_SERIAL is booted and ready"
      return 0
    fi
    emu_warn "attached device $existing did not finish booting; will cold boot $EMU_AVD_NAME"
  fi

  local attempt
  for ((attempt = 1; attempt <= EMU_BOOT_ATTEMPTS; attempt++)); do
    emu_log "Cold boot attempt $attempt/$EMU_BOOT_ATTEMPTS for $EMU_AVD_NAME (emulator log: $EMU_LOG)"
    emu_reset_adb
    emu_kill_avd_processes
    emu_clear_stale_locks
    emu_launch
    if emu_wait_online_and_boot; then
      emu_wake_device "$ADB_SERIAL"
      emu_log "Android device $ADB_SERIAL booted on attempt $attempt"
      return 0
    fi
    emu_capture_boot_log "$attempt"
    emu_warn "cold boot attempt $attempt failed; captured log tail under $EMU_ARTIFACT_DIR"
    emu_kill_avd_processes
    ADB_SERIAL=""
  done

  emu_die "$EMU_AVD_NAME did not reach a booted state after $EMU_BOOT_ATTEMPTS attempt(s). See $EMU_ARTIFACT_DIR/emulator-boot-attempt-*.log and $EMU_LOG"
}
