# Environment

This repo now contains a Flutter scaffold, Android/iOS project shells, a package manifest, and a lockfile. Use this document as the setup contract and keep it current as commands change.

## Current Local Setup

Flutter SDK installed for this workspace:

```bash
/home/tom/.local/share/flutter
```

Current verified versions:

- Flutter 3.44.0 stable
- Dart 3.12.0
- Android SDK 37.0.0 at `/home/tom/Android/Sdk`
- Android Build Tools 36.0.0 installed during first debug build
- Android NDK 28.2.13676358 installed during first debug build
- CMake 3.22.1 installed during first debug build
- Java Temurin 21 at `/home/tom/.local/share/jdks/temurin-21`
- Android Gradle Plugin 9.0.1
- Kotlin Android Gradle plugin 2.3.20
- Gradle wrapper 9.1.0
- `espeak-ng` at `/usr/bin/espeak-ng` for the optional generated-spoken-audio live smoke

Set Flutter on `PATH` for local commands:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
```

Validation:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter pub get
flutter analyze
flutter test
bash scripts/check-docs.sh
bash scripts/check-supply-chain.sh
scripts/final_qa_gate.sh
```

Optional live OpenAI smoke, only when a credential is supplied through the process environment from an uncommitted local source:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
OPENAI_API_KEY="<redacted local value>" dart run scripts/live_openai_smoke.dart --all
```

`--all` includes direct Responses checks, no-microphone realtime session creation for both realtime profiles, a synthetic 200 ms non-speech PCM16 append check for the dedicated translation profile, a synthetic 200 ms non-speech PCM16 append schema check for the primary `gpt-realtime-2` profile, a local generated-Spanish-speech smoke for the dedicated translation profile when `espeak-ng` is installed, and a controlled generated-speech reconnect smoke for the dedicated translation profile. The primary check does not commit the buffer or claim spoken translation from synthetic audio. The generated-speech smokes validate transcript and translated-audio event arrival without printing payloads; the reconnect smoke intentionally closes a live socket after generated-speech chunks, opens a second session, and requires recovered transcript/audio evidence. These smokes do not prove Android physical microphone capture, installed-app transcript persistence, app-coordinator de-duplication, credential-expiry recovery, or audible Android speaker output. Real microphone translation smoke still requires a reliable emulator/device microphone source; if a credential is inserted into app storage for that smoke, clear app data afterward.

Installed APK emulator E2E, only when `/home/tom/.openclaw/secrets/realtime-translate-openai-api-key` is readable and app data can be cleared afterward:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter build apk --debug
scripts/build_debug_apk_artifact.sh
scripts/android_emulator_e2e.sh --apk /tmp/<debug-apk-name>.apk --verify-credential-reset
scripts/android_emulator_e2e.sh --apk /tmp/<debug-apk-name>.apk --verify-invalid-credential-recovery
scripts/android_pixel9_host_audio.sh
scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only
scripts/android_emulator_e2e.sh --with-live-credential
scripts/android_emulator_e2e.sh --require-device-audio --with-live-credential
flutter build apk --debug --dart-define=LIVE_TRANSLATE_DEBUG_E2E=true
scripts/build_debug_apk_artifact.sh --debug-live-events
scripts/android_emulator_e2e.sh --with-live-credential --debug-live-events
scripts/build_debug_apk_artifact.sh --release
scripts/final_qa_gate.sh --emulator-smoke
scripts/final_qa_gate.sh --require-store-signing
```

`scripts/build_debug_apk_artifact.sh` copies the requested APK to `/tmp` with a commit-and-timestamp filename and writes a `.sha256` sidecar. Debug is the default; `--debug-live-events` builds the debug-only E2E proof variant; `--release` builds a release APK. Release artifacts are named `release-local-signed` when `android/key.properties` exists and `release-debug-signed` when the project uses the debug-signing fallback. Debug-signed release artifacts are local handoff artifacts only, not store-ready builds. The script does not read the local OpenAI secret file and is suitable for local APK handoff when live OpenAI quota is blocked.

`scripts/final_qa_gate.sh` is the non-live final QA wrapper. It runs the standard Flutter/docs/supply-chain gates, shell syntax checks, `git diff --check`, and fresh debug plus release APK artifact builds. Add `--emulator-smoke` when an installed-app no-credential smoke is relevant; that mode installs the fresh release artifact, verifies the setup-required gate, writes proof under `/tmp/realtime-translate-mobile-e2e-final-qa`, clears app data, and still does not read the local OpenAI secret file.

`scripts/check_android_release_signing.sh` is the store-ready Android signing preflight. It requires local uncommitted `android/key.properties`, required signing fields, non-placeholder values, and an existing keystore file outside the repo or ignored by git. With `--apk`, it also verifies the APK signature and fails if the artifact is Android debug-signed. `scripts/final_qa_gate.sh --require-store-signing` runs that preflight before the release build and checks the fresh release APK afterward. It reports only pass/fail status and never prints signing passwords, aliases, or keystore material.

The script starts or reuses `Pixel_9_API_36_Play` in the background, writes emulator logs to `/tmp/realtime-translate-emulator.log`, drives the start/setup/permission/live-listening path through UIAutomator when a live credential is requested, verifies hidden live controls are absent before and after opening the live menu, opens `All meetings` AI chat from meeting history without sending a prompt, can run a non-live credential save/remove/reset gate with `--verify-credential-reset`, can run a non-secret invalid-placeholder auth recovery gate with `--verify-invalid-credential-recovery`, stores screenshots and UI XML under `/tmp/realtime-translate-mobile-e2e`, and clears `com.tomdf47.realtime_translate_mobile` data on exit. Use `--require-device-audio` before any physical microphone or audible speaker validation claim. Physical devices pass the target preflight. Emulators pass only when their process arguments include `-allow-host-audio` and do not include `-no-audio`; if no device is connected, `--require-device-audio` starts [../scripts/android_pixel9_host_audio.sh](../scripts/android_pixel9_host_audio.sh), a repo-local `Pixel_9_API_36_Play` launcher with `-allow-host-audio`. The preflight writes `audio-preflight.txt` to the artifact directory. `--audio-preflight-only` performs only that check and does not install the APK, read the local OpenAI secret, launch the app, or clear app data.

The `--debug-live-events` mode requires the debug Dart define shown above. It is an installed-app coordinator/storage/playback persistence proof that reports only sanitized row/audio/context counts: after the generated-event proof, the E2E driver restarts the app, verifies the generated row remains visible in encrypted meeting history, reopens the meeting, and verifies the reopened active live surface still hides legacy route, AI-chat-header, export, and read-aloud controls. It does not use a production hook, live OpenAI speech, emulator microphone input, or audible speaker validation.

Android emulator available on Tom's Fedora machine:

```bash
android-pixel9-headless
```

Do not use:

```bash
emulator -no-window
```

It is known to segfault on this Fedora/KDE/Wayland setup.

Microphone injection status as of 2026-05-24 22:19 AWST: the global `android-pixel9-headless` launcher passes `-no-audio`, so emulator microphone capture receives zeroed input on that path. The repo now includes `scripts/android_pixel9_host_audio.sh`, which launches `Pixel_9_API_36_Play` with `-allow-host-audio` and without `-no-audio`; `scripts/android_emulator_e2e.sh --require-device-audio` uses it when it must start an emulator itself. This creates a concrete host-audio emulator target for live #6/#14 attempts, but it still depends on the host microphone/speaker route and does not provide repeatable generated WAV/PCM microphone injection. `scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only` is the required first check before claiming physical microphone or audible speaker proof. Use the debug generated-event proof for installed-app coordinator/storage/playback validation until a live physical device, the host-audio emulator target, or a controllable virtual audio device has produced real microphone/speaker evidence.

Android environment variables verified by `flutter doctor -v`:

```bash
ANDROID_HOME=/home/tom/Android/Sdk
ANDROID_SDK_ROOT=/home/tom/Android/Sdk
JAVA_HOME=/home/tom/.local/share/jdks/temurin-21
```

Flutter doctor still reports missing Chrome and Linux desktop dependencies. Those do not block the Android-first MVP workflow.

## Android Smoke Sequence

Use Tom's emulator launcher:

```bash
android-pixel9-headless
```

Then, in a second shell:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
adb devices
flutter devices
flutter run -d <android-emulator-id>
```

Repeatable installed-app E2E sequence:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter build apk --debug
scripts/android_emulator_e2e.sh --with-live-credential
```

Non-live installed credential reset validation:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter build apk --debug
scripts/android_emulator_e2e.sh --verify-credential-reset
```

Non-live installed invalid credential recovery validation:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter build apk --debug
scripts/android_emulator_e2e.sh --verify-invalid-credential-recovery
```

Non-live final QA and optional installed smoke:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
scripts/final_qa_gate.sh
scripts/final_qa_gate.sh --emulator-smoke
```

For a screenshot artifact during issue closure, write it outside the repo unless the issue explicitly asks for committed evidence:

```bash
adb exec-out screencap -p > /tmp/live-translate-mobile-smoke.png
```

Expected current smoke result: the `Live Translate` phone-local start surface renders with `Start interpreter`, `Open meeting history`, `OpenAI setup`, the on-device privacy note, and the Xenovis footer. Starting an interpreter without a saved credential shows `OpenAI setup required` before microphone permission, realtime, or capture resources open. The OpenAI setup sheet accepts a user-provided credential, stores it through encrypted local storage, does not redisplay the saved value, and supports removal. After a local credential is configured, starting an interpreter requests Android microphone permission before opening realtime and native PCM16 microphone capture; denied permission shows the `Microphone access needed` state and no live session opens. After permission is granted, the active live surface shows `Listening for languages...`, hides source/target pickers, direction switching, live-header AI chat, live-screen export controls, and read-aloud controls, and stores transcript rows locally as language discovery and translation events arrive. The meeting is written through the encrypted local repository, appears in meeting history with stored metadata, can be reopened to update local activity, can be deleted locally, can open AI chat for `All meetings` from meeting history, can generate Transcript/Summary/Both exports in the background from the UI perspective, can browse generated exports in app, and can copy a generated export only after explicit user action. The installed E2E driver now verifies the missing-credential gate, encrypted credential save/reset paths, live listening surface, hidden live-control absence through UI XML when the live credential path is used, and meeting-history `All meetings` AI chat without sending a prompt. The repo-local live smoke harness passed on 2026-05-24 for Summary export, both AI chat scopes, realtime endpoint availability, dedicated-translation synthetic PCM16 append, primary Realtime 2 synthetic PCM16 append schema acceptance after adding the required output audio rate, dedicated-translation generated spoken audio with transcript plus translated-audio events, and controlled reconnect recovery to transcript plus translated-audio events after an intentionally closed generated-speech socket. The primary Realtime 2 append smoke uses non-speech synthetic audio and does not prove live spoken translation; the generated-speech and installed-app smokes do not prove physical microphone capture or audible Android output.

UI smoke checks should additionally cover the teal listening screen after local credential setup, scoped AI chat sheet for both scopes, amber read-aloud-paused screen, meeting history continue/delete controls, generated export sheet with no active recipient controls, generated export completion snackbar, generated export browser/detail view, and explicit Copy action when safe to do without capturing sensitive export payload screenshots. Direct realtime WebSocket profile/event behavior, PCM16 capture lifecycle, translated-audio playback queue decode/recovery behavior, Android MethodChannel playback argument flow, controlled generated-speech reconnect at the live endpoint, and direct summary Responses request behavior are covered by local fake gateways, controller/coordinator tests, focused playback tests, and the redacted live OpenAI smoke harness; realtime capture and native `AudioTrack` output have no distinct visible emulator surface beyond the existing live-session shell. Direct OpenAI realtime audio streaming with a physical microphone source, audible Android speaker recovery under live streaming, app-coordinator transcript de-duplication under real reconnect, production-volume storage behavior, and iOS share handoff remain future implementation checks.

## Environment Placeholders

Use [.env.example](../.env.example) as a placeholder contract only. It must never contain real credentials.

Mobile-safe values may include app environment names, package names, model intent names, and local feature flags. Do not add standard OpenAI API keys, cloud identity secrets, cookies, signing keys, keystores, or tokens to committed config.

Important placeholders:

- `OPENAI_REALTIME_MODEL`: compatibility/experimental voice-agent profile is `gpt-realtime-2`.
- `OPENAI_REALTIME_TRANSCRIPTION_MODEL`: expected default is `gpt-realtime-whisper`.
- `OPENAI_TRANSLATION_FALLBACK_MODEL`: MVP live interpretation profile is `gpt-realtime-translate` on `/v1/realtime/translations`.
- `OPENAI_SUMMARY_MODEL_INTENT`: product intent is GPT-5.5 for meeting summaries.
- `OPENAI_SUMMARY_REASONING_INTENT`: product intent is `xhigh` reasoning for meeting summaries.
- `ANDROID_PACKAGE_NAME`: current scaffold value is `com.tomdf47.realtime_translate_mobile`.

Implementation must verify current OpenAI API model, reasoning parameter, and realtime endpoint behavior before coding against these intent values. #23 accepted user-provided OpenAI credential/session material stored only in encrypted local device storage; no key may be committed, bundled, logged, or captured in screenshots.

## Android Signing Placeholders

Debug builds use the standard local Android debug signing flow.

For local release-signing experiments only, copy:

```bash
cp android/key.properties.example android/key.properties
```

Then fill `android/key.properties` with local, uncommitted values. Prefer an absolute `storeFile` path outside this repository. Do not commit `android/key.properties`, keystores, signing passwords, key aliases, or certificates.

If `android/key.properties` is absent, the Gradle release build uses the debug signing config as a local fallback. This keeps release-mode smoke builds possible, but those APKs must be treated as debug-signed handoff artifacts. Use `scripts/build_debug_apk_artifact.sh --release` to make that signing status explicit in the artifact filename and console output. Use `scripts/check_android_release_signing.sh` or `scripts/final_qa_gate.sh --require-store-signing` before any store/device handoff that must be release-signed.

## Deferred V2 Configuration

The MVP does not use AWS, Lambda, token broker endpoints, Google/Microsoft sign-in, cloud sync, or backend OpenAI key storage. Do not add active MVP setup requirements for those systems. If future work reintroduces them, update [docs/v2-future-scope.md](v2-future-scope.md), [docs/decision-log.md](decision-log.md), this file, and the GitHub issue map first.

## Secret Handling Rules

- Do not commit `.env`, `.env.*`, OpenAI credentials, local AWS credentials, keystores, signing certificates, tokens, cookies, real account IDs that grant access, or real API keys.
- Do not include a standard OpenAI API key in Flutter source, assets, tests, screenshots, build outputs, or mobile config.
- If implementation uses user-provided OpenAI credential material, store it only in encrypted local storage and provide a clear remove/reset path.
- Redact OpenAI credential/session material, tokens, recipient lists, transcript content, prompts, summaries, and translated text from logs, screenshots, analytics, crash reports, and test output.
