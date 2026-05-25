# Testing Strategy

This is the MVP verification plan. Keep commands concrete as implementation lands.

## Current Local Gates

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter pub get
flutter analyze
flutter test
bash scripts/check-docs.sh
bash scripts/check-supply-chain.sh
scripts/final_qa_gate.sh
```

Use [regression-testing-checklist.md](regression-testing-checklist.md) for the concrete manual and installed-app regression pass before publishing APKs. It covers main screen controls, language selection, toggle behavior, realtime session smoke, transcript chunking, elapsed timer behavior, generated exports, and APK release sanity.

Optional live OpenAI smoke, only when a credential is supplied through the process environment from an uncommitted local source:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
OPENAI_API_KEY="<redacted local value>" dart run scripts/live_openai_smoke.dart --all
```

`scripts/check-docs.sh` checks local Markdown links and scans for likely committed OpenAI secret patterns. `scripts/check-supply-chain.sh` checks for obvious credential leaks, verifies Android permission additions against the current allowlist, and queries OSV for pinned hosted Pub and Gradle/Maven runtime package versions. `scripts/live_openai_smoke.dart` uses tiny synthetic transcript text, `store: false`, redacted output, no-microphone realtime session creation for both profiles, synthetic 200 ms non-speech PCM16 append checks for the dedicated translation profile, a primary Realtime 2 synthetic PCM16 append schema check, a local `espeak-ng` generated-Spanish-speech check, and a controlled generated-speech reconnect check for the dedicated translation profile to verify direct OpenAI Responses and realtime endpoint behavior without printing generated content, transcript text, audio bytes, or credential material. The primary Realtime 2 synthetic check does not commit the buffer or claim spoken translation. The generated-speech checks prove transcript and translated-audio event arrival from spoken PCM16 input; the controlled reconnect check proves a second live translation session can recover transcript/audio evidence after an intentionally closed generated-speech socket. They do not prove Android physical microphone capture, installed-app live speech persistence, credential-expiry recovery with real credential material, or audible speaker output. The installed-app E2E has an opt-in debug-only generated-event persistence proof, enabled only by `--dart-define=LIVE_TRANSLATE_DEBUG_E2E=true` in a debug APK, that verifies coordinator/storage/playback de-duplication, encrypted history persistence after app restart, and `This meeting` local AI context visibility inside the installed app without live OpenAI or microphone input, plus a non-secret invalid-placeholder auth recovery gate for setup-required recovery after OpenAI rejects realtime credentials. Current Flutter tests cover the phone-local start surface, OpenAI setup-required UI, encrypted OpenAI credential save/read/reset behavior without displaying the saved value, direct realtime WebSocket profile config/event parsing/header-and-body credential non-leakage, Android PCM16 capture config/platform-event parsing, realtime coordinator credential/permission gates, PCM16 chunk flow into the realtime gateway, translated-audio delta decoding into a fakeable PCM16 playback queue, Android MethodChannel playback start/enqueue/stop calls, capture/playback teardown on stop/background/reconnecting, direct realtime failure classification including WebSocket upgrade status codes and close reasons, bounded jittered reconnect planning, fake-gateway reconnect scheduling, transcript-row continuity across a retry, generated-speech-style dedicated translation reconnect event ordering through the coordinator storage path, stale playback clearing and recovered playback queueing after reconnect, playback restart after fake reconnect, debug generated-event proof row/audio counters, reconnect exhaustion interruption status, user-visible reconnecting/offline live recovery banners with retry/back controls, unsupported-language recovery that labels the language issue without showing a retry loop, rate-limit recovery labels that avoid raw OpenAI error details, credential-expiry/rejection recovery states that keep capture/realtime/playback closed, privacy-safe diagnostics redaction and payload omission, scoped AI chat context construction for `This meeting` and `All meetings`, privacy-preserving OpenAI Responses request bodies with `store: false`, direct summary Responses request bodies with `gpt-5.5`, `reasoning.effort: xhigh`, and `store: false`, local Transcript/Summary/Both export composition, mockup-derived listening/AI chat/amber/export surfaces, microphone permission denied UI, deterministic session lifecycle transitions that keep capture/realtime/playback resources closed until permission and local credential gates pass, realtime recovery state transitions that keep resources closed during reconnect/offline/credential-invalid/error states, encrypted local repository behavior for meetings, transcript/history entries, summary text/metadata, language routes, recipient preferences, sensitive preferences, credential/session material, meeting management for deleting or continuing a saved meeting with appended local history, the conservative realtime language support table, direct-OpenAI fallback credential routing for unsupported targets, semantic labels for core controls, and compact large-text rendering across setup, live, assistant, amber, export, and realtime recovery surfaces.

`scripts/android_emulator_e2e.sh --with-live-credential` is the repeatable installed-APK Android E2E path. It reads the live OpenAI credential only from `/home/tom/.openclaw/secrets/realtime-translate-openai-api-key`, starts or reuses `Pixel_9_API_36_Play` in the background, installs the debug APK, verifies the missing-credential gate, saves the credential through the obscured setup field, accepts runtime microphone permission, reaches the live listening surface, opens the `This meeting` AI chat sheet without sending a prompt, writes screenshots/UI XML under `/tmp/realtime-translate-mobile-e2e`, and clears app data afterward. `--verify-credential-reset` is a non-live installed-app gate that saves a non-secret placeholder through setup, verifies the saved value is not visible, removes it, and confirms starting a meeting returns to the setup-required gate. `--verify-invalid-credential-recovery` is a non-live-key negative auth gate that saves a non-secret invalid placeholder, grants microphone permission for the negative path, waits for OpenAI's realtime auth rejection, and verifies setup-required recovery. `--debug-live-events` can be added only when the APK was built with `--dart-define=LIVE_TRANSLATE_DEBUG_E2E=true`; it drives generated-speech-shaped events through the installed app coordinator, simulates playback teardown/restart, verifies one realtime transcript row plus one recovered audio chunk using sanitized UI text, restarts the app, verifies `4 transcript lines` in meeting history, reopens the meeting, and verifies `This meeting` AI context sees `5 local transcript lines` after the normal continue append. This proves installed-app setup, credential reset, invalid-credential recovery, permission, live-surface entry, local AI-chat UI routing, and debug-only coordinator/storage/playback persistence; it still does not prove physical microphone speech injection, committed transcript deltas from live speech, live OpenAI reconnect inside the app, credential expiry with real credential material, or audible translated-audio output.

## Flutter App Gates

Once the Flutter scaffold exists, app changes should run:

```bash
flutter analyze
flutter test
```

Expected coverage areas:

- Session state model transitions: local setup, meeting selection, connecting, listening, speaking, read-aloud paused, reconnecting, offline, credential invalid, and error.
- Microphone permission states: granted, denied, permanently denied, and revoked.
- Direct OpenAI integration seams for realtime translation, credential-invalid handling, AI chat, and summary generation.
- Language support table and unsupported-target fallback behavior.
- Local encrypted storage read/write/delete behavior for meetings, transcript/history, summary metadata, generated exports, preferences, remembered recipients, last selected recipients, and any credential/session material.
- Meeting management: start new meeting, select old meeting, continue from meeting, delete meeting.
- Scoped AI chat: `This meeting`, `All meetings`, empty transcript, no selected meeting, offline, credential-invalid, unsupported, and model/API error states.
- Generated exports: Transcript/Summary/Both selector, disabled active recipient UI, background generation from the UI perspective, direct OpenAI summary generation, encrypted local summary/export persistence, in-app generated export browser/detail views, explicit Copy action, and no outbound mail backend.
- Privacy-safe diagnostics: allowlisted state/config fields only, redaction of credentials/session tokens, and omission/redaction of transcript, prompt, summary, recipient, export, and audio payloads.
- Widget tests for the supplied mockup-derived surfaces and revised phone-only setup/meeting/export surfaces.
- Accessibility checks for icon-only controls, local setup actions, meeting selectors, language selectors, playback controls, AI chat controls, generated export controls, and transcript actions.

## Privacy, Secret, And Cybersecurity Gates

Every implementation change touching OpenAI, logging, storage, permissions, dependencies, export, or transcript handling should include negative tests or documented checks for:

- No standard OpenAI API key in mobile code/config/assets/tests/screenshots/build outputs.
- No transcript/audio/prompt/summary/export payload routed through app-owned backend infrastructure.
- No app backend, AWS, Lambda, token broker, cloud sync, or server mailer added to MVP code.
- No transcript/audio/prompt/summary/recipient payload in logs, analytics, diagnostics, crash reports, screenshots, or test output.
- Diagnostics use `PrivacySafeDiagnostics` or an equivalent allowlist/redaction path before reaching any sink.
- AI chat uses the explicit `This meeting` or `All meetings` scope and direct OpenAI path.
- Generated export bodies remain in encrypted local storage until the user opens the in-app detail view and explicitly presses Copy.
- Mobile permissions are limited to what the feature requires and are documented.
- Dependency versions are pinned through lockfiles and checked against credible advisory sources once dependencies exist.

## Dependency And Supply-Chain Checks

Before closing dependency-bearing implementation work:

- Run `bash scripts/check-supply-chain.sh`.
- Record package/version checks in [docs/cybersecurity-report.md](cybersecurity-report.md) or a linked artifact.
- Check Dart/pub advisories, GitHub Advisory Database, OSV, NVD where applicable, and package changelogs/security notes for pinned versions.
- Run any available ecosystem command that surfaces advisories, such as `dart pub get` advisory output once a Flutter scaffold exists.
- Document accepted risks with owner, mitigation, and next review trigger.

## Android Emulator Smoke

Use Tom's boot-tested emulator command:

```bash
android-pixel9-headless
```

Do not use `emulator -no-window`.

Once Flutter exists, smoke checks should cover:

- Welcome/local setup surface.
- Meeting history or meeting selector entry point.
- Teal live listening surface.
- Scoped AI chat bottom sheet over dimmed live screen.
- Amber speaking/read-aloud-paused surface.
- Generated export type selector, generated export browser, and generated export detail/copy views.
- Large text and small device handling without clipped labels or overlapping bottom controls.
- Safe-area behavior around Android status and navigation bars.

Record emulator command output, screenshot notes, or exact blockers in the issue before closing UI or Android verification work.

Current command sequence:

```bash
android-pixel9-headless
export PATH=/home/tom/.local/share/flutter/bin:$PATH
adb devices
flutter devices
flutter run -d <android-emulator-id>
```

Repeatable installed-app E2E sequence:

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

For physical microphone or audible speaker validation, run `scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only` first. Physical devices pass the target preflight. Emulators pass only when the selected process includes `-allow-host-audio` and does not include `-no-audio`; if no device is connected, the E2E script starts the repo-local [../scripts/android_pixel9_host_audio.sh](../scripts/android_pixel9_host_audio.sh) launcher for `Pixel_9_API_36_Play`. The check writes `audio-preflight.txt` under the artifact directory and does not install the APK, read the local OpenAI secret, launch the app, or clear app data. Add `--require-device-audio` to any later installed-app live-audio run so a no-audio emulator cannot silently produce a misleading pass. Passing preflight is target readiness only; it is not proof of physical microphone translation or audible speaker output.

For APK handoff without live OpenAI quota, `scripts/build_debug_apk_artifact.sh` produces `/tmp/realtime-translate-mobile-<mode>-<commit>-<timestamp>.apk` plus a `.sha256` sidecar. Debug is the default, `--debug-live-events` produces the matching debug-only E2E proof build artifact, and `--release` produces a release-mode APK. Release artifacts are named `release-local-signed` when `android/key.properties` exists and `release-debug-signed` when the project uses the debug-signing fallback; debug-signed release artifacts are not store-ready. The script does not read the local OpenAI secret file.

For a one-command non-live pre-handoff gate, `scripts/final_qa_gate.sh` runs Flutter analysis/tests, docs and supply-chain checks, shell syntax checks, `git diff --check`, and fresh debug plus release APK artifact builds. `scripts/final_qa_gate.sh --emulator-smoke` also installs the fresh release artifact and verifies the missing-credential setup gate without reading the live OpenAI secret or making a live OpenAI request. `scripts/final_qa_gate.sh --require-store-signing` requires local uncommitted release signing config before release build and verifies the fresh release APK is not Android debug-signed afterward.

For focused store-signing validation, run `scripts/check_android_release_signing.sh` before building and `scripts/check_android_release_signing.sh --apk /tmp/<release-apk>.apk` after building. In a checkout without local signing material, `scripts/check_android_release_signing.sh` must fail clearly while the normal non-live final QA gate can still pass.

Optional screenshot capture should write outside the repo by default:

```bash
adb exec-out screencap -p > /tmp/live-translate-mobile-smoke.png
```

The current app can verify the phone-local start surface, OpenAI setup-required and encrypted credential setup/reset states, Android microphone runtime permission dialog/denied state, teal listening screen after a local credential is configured, realtime target language options, scoped AI chat bottom sheet for `This meeting`, `All meetings` AI chat from meeting history, amber paused read-aloud screen with unsupported-target fallback credential state, encrypted meeting history sheet with continue/delete controls, appended local meeting history after reopening a saved meeting, generated export sheet with disabled active recipient UI, background summary/export generation, encrypted local generated-export persistence, in-app generated export browser/detail views, explicit Copy action, and large-text/compact-viewport behavior for those core surfaces. The installed E2E driver passed on 2026-05-24 by driving the missing-credential gate, encrypted credential save, runtime microphone permission, live listening surface, and `This meeting` AI chat sheet on `Pixel_9_API_36_Play`, with artifacts under `/tmp/realtime-translate-mobile-e2e` and app data cleared afterward. The debug-only generated-event E2E mode is now documented for installed-app coordinator/storage/playback de-duplication plus encrypted history persistence after app restart and `This meeting` context visibility when a debug APK is built with `LIVE_TRANSLATE_DEBUG_E2E=true`. Direct realtime WebSocket profile/event behavior, PCM16 capture lifecycle, translated-audio playback queue decode/recovery behavior, Android playback MethodChannel behavior, realtime coordinator behavior including generated-speech-style reconnect storage continuity, debug generated-event proof counters, realtime resilience classification/backoff behavior, direct summary Responses request behavior, generated spoken-audio transcript/translated-audio event arrival, and controlled generated-speech reconnect recovery are covered by local fake gateways, controller/coordinator tests, focused playback tests, and the redacted live OpenAI smoke harness. Direct OpenAI realtime audio streaming with a physical microphone source, audible Android speaker recovery under live streaming, committed real transcript deltas from the installed app, credential-expiry recovery, transcript de-duplication under real live OpenAI app-coordinator reconnect streaming, iOS share handoff, production-volume storage behavior, and privacy routing assertions become required as their implementation issues land.

Latest debug APK handoff validation on 2026-05-24 20:09 AWST passed with `bash -n scripts/build_debug_apk_artifact.sh`, `git diff --check`, `bash scripts/check-docs.sh`, `flutter analyze`, `flutter test` (76 tests), `bash scripts/check-supply-chain.sh`, `scripts/build_debug_apk_artifact.sh`, and an installed no-credential emulator smoke using `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-ff4096c-20260524T120913Z.apk`. The emulator smoke did not read the live OpenAI secret and verified only install, launch, and the missing-credential gate.

Latest credential reset E2E validation on 2026-05-24 20:20 AWST passed with `bash -n scripts/android_emulator_e2e.sh`, `flutter test test/widget_test.dart`, `flutter analyze`, `flutter test` (76 tests), `bash scripts/check-docs.sh`, `git diff --check`, `bash scripts/check-supply-chain.sh` with the documented Flutter `PATH`, `scripts/build_debug_apk_artifact.sh`, and `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-ac2e265-20260524T121915Z.apk --verify-credential-reset`. The emulator run used only a non-secret placeholder credential, verified the saved value was not visible after save, removed the credential, confirmed the removal action disappeared, and confirmed starting a meeting returned to the setup-required gate. It did not read the live OpenAI secret, call live OpenAI, validate microphone injection, or validate audible speaker output.

Latest release APK handoff hardening on 2026-05-24 AWST added explicit `--release` artifact support. The script reports whether release mode used local `android/key.properties` signing or the debug-signing fallback, and filenames include `release-local-signed` or `release-debug-signed` accordingly. Validation passed with `bash -n scripts/build_debug_apk_artifact.sh`, `scripts/build_debug_apk_artifact.sh --help`, `flutter analyze`, `flutter test` (77 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, `git diff --check`, default debug artifact build, release artifact build, and a no-live installed emulator smoke against `/tmp/realtime-translate-mobile-release-debug-signed-8732d48-20260524T124418Z.apk`. That APK has SHA-256 `d55cf2e5f79bb0b0fa79e0fa217a7df18bf3d81196de680cd809345552f8d005`, uses the debug-signing fallback, and is only a local handoff/smoke artifact, not a store-ready release.

## CI Gates

Current GitHub Actions run on pull requests and pushes to `main`:

- `Docs`: `bash scripts/check-docs.sh`.
- `Flutter`: `flutter pub get`, `flutter analyze`, `flutter test`, and `bash scripts/check-supply-chain.sh`.

Android emulator smoke is intentionally local/manual because the project uses Tom's `android-pixel9-headless` machine workflow.

Latest focused validation for the unsupported-language recovery UI slice was 2026-05-24 AWST. `flutter test test/widget_test.dart test/live_session_controller_test.dart` and `git diff --check` passed. The slice carries the realtime recovery action into session state, labels unsupported-language errors as `Language not supported`, and hides the retry action for that non-retryable configuration failure. It adds no dependencies, Android permissions, backend routes, OpenAI request-format changes, production debug hooks, live OpenAI calls, or credential logging.

Latest host validation for the device-audio preflight slice was 2026-05-24 22:14 AWST. `bash -n scripts/android_emulator_e2e.sh` passed. `scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only` failed as expected because the current `Pixel_9_API_36_Play` process was launched with `-no-audio`; proof was written to `/tmp/realtime-translate-mobile-e2e-audio-preflight-precommit/audio-preflight.txt`. The preflight did not install an APK, read the local OpenAI secret, launch the app, or clear app data. `scripts/final_qa_gate.sh` passed with `flutter pub get`, `flutter analyze`, `flutter test` (82 tests), docs check, supply-chain check, shell syntax checks, `git diff --check`, and fresh debug/release APK builds. This slice adds no dependency, Android permission, backend route, OpenAI request change, live credential handling, audio recording, or physical microphone/audible speaker claim.

Latest host validation for the host-audio emulator target was 2026-05-24 22:19 AWST. `bash -n scripts/android_emulator_e2e.sh`, `bash -n scripts/android_pixel9_host_audio.sh`, `bash scripts/check-docs.sh`, `git diff --check`, and `PATH=/home/tom/.local/share/flutter/bin:$PATH bash scripts/check-supply-chain.sh` passed. `ARTIFACT_DIR=/tmp/realtime-translate-mobile-e2e-host-audio-preflight-2 scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only` passed by starting `Pixel_9_API_36_Play` through `scripts/android_pixel9_host_audio.sh`; proof at `/tmp/realtime-translate-mobile-e2e-host-audio-preflight-2/audio-preflight.txt` records `-allow-host-audio` and no `-no-audio`. The preflight did not install an APK, read the local OpenAI secret, launch the app, clear app data, record audio, call OpenAI, or claim physical microphone/speaker behavior.

Latest focused validation for the direct realtime recovery-label slice was 2026-05-24 20:52 AWST. `flutter test test/live_session_controller_test.dart test/widget_test.dart test/realtime_translation_coordinator_test.dart` passed. The slice preserves only sanitized failure categories in session state, renders rate-limit recovery without raw OpenAI error details, and proves credential-expiry/rejection decisions close capture/realtime/playback resources. It made no live OpenAI request, read no live credential, and made no microphone or audible speaker-output claim.

Latest host validation for installed invalid-credential recovery was 2026-05-24 21:17 AWST. `bash -n scripts/android_emulator_e2e.sh`, `flutter test test/openai_realtime_translation_test.dart test/openai_realtime_resilience_test.dart test/realtime_translation_coordinator_test.dart`, `flutter analyze`, `flutter test` (83 tests), `scripts/build_debug_apk_artifact.sh`, and `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-61b9239-20260524T131539Z.apk --verify-invalid-credential-recovery` passed. The emulator run used only a non-secret invalid placeholder credential, pre-granted microphone permission for the negative auth path, observed the realtime auth rejection, verified setup-required recovery, wrote proof under `/tmp/realtime-translate-mobile-e2e-invalid-credential-precommit`, and cleared app data afterward.

Latest host validation for debug installed-app persistence proof was 2026-05-24 21:40 AWST. `bash -n scripts/android_emulator_e2e.sh`, `git diff --check`, `bash scripts/check-docs.sh`, `flutter analyze`, `flutter test` (83 tests), `bash scripts/check-supply-chain.sh`, `scripts/build_debug_apk_artifact.sh --debug-live-events`, and `scripts/android_emulator_e2e.sh --with-live-credential --debug-live-events --apk /tmp/realtime-translate-mobile-debug-live-events-2287189-20260524T133629Z.apk` passed. The APK SHA-256 was `da4ed0de8aeb1c355c5e6c4e1ed1369d8f9167a2f616b5aabd9ab0c4e0c227c1`. The emulator run saved the live credential through the app UI without printing it, accepted microphone permission, ran the debug generated-event proof, restarted the app, verified `4 transcript lines` in encrypted meeting history, reopened the meeting, verified `This meeting` AI context saw `5 local transcript lines`, wrote proof under `/tmp/realtime-translate-mobile-e2e-persistence-precommit`, and cleared app data afterward. Exact key scan counts after cleanup were repo `0`, `/tmp` `0`, `/home/tom/.openclaw/logs` `0`, process environments `0`, and `~/.codex/auth.json` `0`. This did not prove physical microphone input, live transcript persistence from real speech, live OpenAI reconnect in the app, credential-expiry recovery, or audible speaker output.

Latest non-live final QA gate validation was 2026-05-24 21:49 AWST. `scripts/final_qa_gate.sh --emulator-smoke` passed with `flutter pub get`, `flutter analyze`, `flutter test` (82 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, shell syntax checks for repo scripts, `git diff --check`, fresh debug and release APK artifact builds, and a no-live installed-app smoke against `/tmp/realtime-translate-mobile-release-debug-signed-bdd6dcb-20260524T134822Z.apk`. The debug APK SHA-256 was `fe446ad7670619dae3b401d850af4b36b9cce4205428b8c52f73479092030706`; the release APK SHA-256 was `9f51c22befa8f96091108aff2def2e64d898e1b18d1909cae8f6e804ed40e07d`. The release artifact used the debug-signing fallback because local `android/key.properties` was absent, so it is not store-ready. The emulator smoke wrote proof under `/tmp/realtime-translate-mobile-e2e-final-qa`, cleared app data afterward, did not read the local OpenAI secret, did not call live OpenAI, and made no microphone-injection or audible-speaker claim.

Latest store-ready signing preflight validation was 2026-05-24 21:59 AWST. `bash -n scripts/check_android_release_signing.sh`, `scripts/check_android_release_signing.sh`, and `scripts/final_qa_gate.sh --require-store-signing` passed the expected absent-material behavior: store-ready mode failed clearly because `android/key.properties` is missing. Normal `scripts/final_qa_gate.sh` still passed with `flutter pub get`, `flutter analyze`, `flutter test` (82 tests), docs check, supply-chain check, shell syntax checks, `git diff --check`, and fresh APK builds. Debug APK: `/tmp/realtime-translate-mobile-debug-b5e0d2a-20260524T135914Z.apk`, SHA-256 `fe446ad7670619dae3b401d850af4b36b9cce4205428b8c52f73479092030706`. Release APK: `/tmp/realtime-translate-mobile-release-debug-signed-b5e0d2a-20260524T135921Z.apk`, SHA-256 `9f51c22befa8f96091108aff2def2e64d898e1b18d1909cae8f6e804ed40e07d`; it remains debug-signed and not store-ready.
