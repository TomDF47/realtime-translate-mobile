#!/usr/bin/env bash
set -euo pipefail

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/share/jdks/temurin-21}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

exec "$ANDROID_HOME/emulator/emulator" \
  -avd Pixel_9_API_36_Play \
  -qt-hide-window \
  -allow-host-audio \
  -gpu host \
  -no-snapshot \
  -no-metrics \
  "$@"
