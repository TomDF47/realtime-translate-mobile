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

## Live Realtime Wire Capture (Ground Truth)

Synthetic, hand-authored realtime events are NOT proof for the live `/v1/realtime/translations` path (see the Live-Path Evidence Rule in [development-workflow.md](development-workflow.md)). To capture the real wire shape on a physical device:

```bash
# Build a debug APK with the content-free event recorder enabled.
flutter build apk --debug --dart-define=LIVE_TRANSLATE_DEBUG_EVENTS=true
scripts/build_debug_apk_artifact.sh --wire-events
# Install the DEBUG apk on a physical phone (not the debug-signed release apk),
# start an interpreter session, speak English and Italian, then capture:
adb logcat | grep LIVE_TX_EVENT
```

Each `LIVE_TX_EVENT` line is content-free JSON: event `type`, the JSON key names present, payload lengths (never values), any language code (`en`/`it`), and item-id presence. No transcript text, translated text, or audio bytes are logged (`RealtimeEventDebugRecorder`; covered by `test/realtime_event_debug_recorder_test.dart`). Use the captured lines to confirm whether `session.input_transcript.*` source events actually arrive, whether any language field is present, and how turn boundaries land.

Reconcile the capture into `test/fixtures/realtime_translation_documented_turns.json` (currently seeded with documented event shapes) and let `test/realtime_event_fixture_test.dart` drive it through the production committer. Keep wire-shape assumptions in that one swappable fixture rather than scattered across inline test literals.

Issue #30 adds focused coverage for the revised two-party interpreter default: the start surface says `Start interpreter`, the active live screen shows source/target selectors for the manual pair, hides direction switching, the `Translate Text` toggle, live-header AI chat, live-screen export controls, and legacy read-aloud claims, seeds the selected pair into the runtime from session start, persists picker changes, transcript rows preserve original and translated text separately with pending/delayed/final statuses, fake text interpreter turns translate A-to-B and B-to-A through a direct OpenAI gateway with `store: false`, and diagnostics remain payload-safe. Issue #31 adds focused coverage for `Pause Listening` / `Resume Listening`, clear `Connecting to OpenAI` startup UI, and the active 2026-06-07 transcription-first batch path: transcription session config uses `gpt-realtime-whisper` with manual commits, the batcher commits after pause/hard-cap without suppressing chunk forwarding, Android room capture disables input effects, completed transcription batches create distinct transcript rows, Responses translation updates only the matching row, language-card voice buttons stay hidden, transcript-row playback speaks the selected row translation, and microphone capture pauses/resumes around manual TTS. Legacy `/v1/realtime/translations` parser/committer tests remain for compatibility/debug coverage, but installed-app validation for #6 should now prove the transcription-first path.

Optional live OpenAI smoke, only when a credential is supplied through the process environment from an uncommitted local source:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
OPENAI_API_KEY="<redacted local value>" dart run scripts/live_openai_smoke.dart --all
OPENAI_API_KEY="<redacted local value>" dart run scripts/live_openai_smoke.dart --realtime-transcription
```

`scripts/check-docs.sh` checks local Markdown links and scans for likely committed OpenAI secret patterns. `scripts/check-supply-chain.sh` checks for obvious credential leaks, verifies the source main-manifest Android permissions against the current allowlist, requires the product-critical `RECORD_AUDIO` and `INTERNET` permissions to be declared there, and queries OSV for pinned hosted Pub and Gradle/Maven runtime package versions. `scripts/live_openai_smoke.dart --realtime-transcription` now covers the active realtime transcription endpoint with generated PCM16 speech, manual commit, and sanitized committed/transcript event counts; installed-app physical microphone/audio behavior still requires the Android E2E/device path. Current Flutter coverage should include the phone-local start surface, OpenAI setup-required UI, encrypted OpenAI credential save/read/reset behavior without displaying the saved value, Realtime transcription config/event parsing/header-and-body credential non-leakage, Android PCM16 room capture config/platform-event parsing, transcription batcher pause/hard-cap decisions, coordinator credential/permission gates, forwarding every PCM16 chunk into the transcription session, manual input-buffer commits, distinct transcript rows per completed batch, direct Responses translation updates with `store: false`, row-level TTS playback with mic pause/resume, legacy realtime translation compatibility tests, realtime recovery state transitions, privacy-safe diagnostics redaction and payload omission, scoped AI chat, summary/export construction, encrypted local repository behavior, manual source/target selectors, hidden live direction switching, semantic labels for core controls, and compact large-text rendering across setup, live, assistant, amber, export, and recovery surfaces.

`scripts/android_emulator_e2e.sh --with-live-credential` is the repeatable installed-APK Android E2E path. It reads the live OpenAI credential only from `/home/tom/.openclaw/secrets/realtime-translate-openai-api-key`, starts or reuses `Pixel_9_API_36_Play` in the background, installs the debug APK, verifies the missing-credential gate, saves the credential through the obscured setup field, reaches the active live listening surface, verifies manual pair selectors plus hidden secondary controls before and after opening the live menu, verifies the microphone-permission path, opens the `All meetings` AI chat sheet from meeting history without sending a prompt, writes screenshots/UI XML under `/tmp/realtime-translate-mobile-e2e`, and clears app data afterward. `--verify-credential-reset` is a non-live installed-app gate that saves a non-secret placeholder through setup, verifies the saved value is not visible, removes it, and confirms starting a meeting returns to the setup-required gate. `--verify-invalid-credential-recovery` is a non-live-key negative auth gate that saves a non-secret invalid placeholder, grants microphone permission for the negative path, waits for OpenAI's realtime auth rejection, and verifies setup-required recovery. `--debug-live-events` can be added only when the APK was built with `--dart-define=LIVE_TRANSLATE_DEBUG_E2E=true`; it drives generated-speech-shaped events through the installed app coordinator, simulates playback teardown/restart, verifies one realtime transcript row plus one recovered audio chunk using sanitized UI text, restarts the app, verifies `4 transcript lines` in meeting history, reopens the meeting, and verifies the reopened active live surface still keeps manual pair selectors while hiding legacy route, AI-chat-header, export, and legacy read-aloud controls. This proves installed-app setup, credential reset, invalid-credential recovery, live-surface entry, microphone permission/capture gating, All-meetings AI-chat UI routing, manual-pair/hidden-secondary-control regression coverage, and debug-only coordinator/storage/playback persistence; it still does not prove physical microphone speech injection, committed transcript deltas from live speech, live OpenAI reconnect inside the app, credential expiry with real credential material, or audible Android TTS spoken output from a real turn.

The focused realtime prompt/transcript regression tests cover the default dedicated translation profile, the compatibility `gpt-realtime-2` session config, no assistant-style `input_audio_buffer.commit` or `response.create` behavior on the dedicated/default path, source-language omission from dedicated translation session updates, the "yellow what's going on" utterance as source text rather than a prompt to answer, input transcription item ID and segment parsing, source transcript deltas creating visible original text before completion, completed input transcripts finalizing a block, translation deltas landing in the separate translation field, read-aloud off suppressing audio without suppressing translated text, read-aloud off skipping playback queue startup, stable source-delta direct fallback before source completion, suppression of same-language no-item realtime output for fallback-owned rows, and graceful close waiting briefly for `session.closed` before immediate fallback. They also cover the live reconnect trigger on the real session path (#14): a real loopback WebSocket that drops mid-session after `session.updated`, and a controllable transport that drops with only a numeric close code, must each surface the `OpenAiRealtimeSessionClosed` / sanitized `socket.close_<code>` `OpenAiRealtimeError` that the coordinator's `events.listen` (no `onDone`) relies on, and the mapped `OpenAiRealtimeReconnectPolicy` decision must be `reconnectAfterBackoff` (retryable), not a fatal stop or credential reset.

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
scripts/build_debug_apk_artifact.sh --wire-events
scripts/android_emulator_e2e.sh --with-live-credential --debug-live-events
scripts/build_debug_apk_artifact.sh --release
scripts/final_qa_gate.sh --emulator-smoke
scripts/final_qa_gate.sh --require-store-signing
```

For physical microphone or audible speaker validation, run `scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only` first. Physical devices pass the target preflight. Emulators pass only when the selected process includes `-allow-host-audio` and does not include `-no-audio`; if no device is connected, the E2E script starts the repo-local [../scripts/android_pixel9_host_audio.sh](../scripts/android_pixel9_host_audio.sh) launcher for `Pixel_9_API_36_Play`. The check writes `audio-preflight.txt` under the artifact directory and does not install the APK, read the local OpenAI secret, launch the app, or clear app data. Add `--require-device-audio` to any later installed-app live-audio run so a no-audio emulator cannot silently produce a misleading pass. Passing preflight is target readiness only; it is not proof of physical microphone translation or audible speaker output.

For APK handoff without live OpenAI quota, `scripts/build_debug_apk_artifact.sh` produces `/tmp/realtime-translate-mobile-<mode>-<commit>-<timestamp>.apk` plus a `.sha256` sidecar. Debug is the default, `--wire-events` enables the privacy-safe `LIVE_TX_EVENT` realtime wire recorder for physical-device logcat capture, `--debug-live-events` produces the matching debug-only E2E proof build artifact, and `--release` produces a release-mode APK. Release artifacts are named `release-local-signed` when `android/key.properties` exists and `release-debug-signed` when the project uses the debug-signing fallback; debug-signed release artifacts are not store-ready. The script does not read the local OpenAI secret file.

For a one-command non-live pre-handoff gate, `scripts/final_qa_gate.sh` runs Flutter analysis/tests, docs and supply-chain checks, shell syntax checks, `git diff --check`, and fresh debug plus release APK artifact builds. `scripts/final_qa_gate.sh --emulator-smoke` also installs the fresh release artifact and verifies the missing-credential setup gate without reading the live OpenAI secret or making a live OpenAI request. `scripts/final_qa_gate.sh --release-smoke` runs the repeatable release smoke against the fresh release artifact. `scripts/final_qa_gate.sh --require-store-signing` requires local uncommitted release signing config before release build and verifies the fresh release APK is not Android debug-signed afterward.

### Android Release Smoke Validation (#39)

`scripts/android_release_smoke.sh` is the repeatable, offline-by-default release smoke. It exists because publishing a release should not depend on a hand-driven emulator session that can die during cold boot before stable `adb`.

The default flow is:

1. Locate `--apk PATH` or build an APK artifact (debug by default, `--release` for a release-mode artifact), each with a SHA-256 sidecar.
2. `scripts/check_apk_metadata.sh` verifies the SHA-256 sidecar (when present), the package id `com.tomdf47.realtime_translate_mobile`, version metadata, and that requested permissions stay within the least-privilege allowlist (`RECORD_AUDIO`, `INTERNET`, and the AndroidX `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`). It also requires the product-critical permissions `RECORD_AUDIO` and `INTERNET` to be present so a release build that drops the direct phone-to-OpenAI network path fails the gate (#41), then reports debug vs release signing without failing a debug release.
3. `scripts/lib/android_emulator_boot.sh` cold-boots `Pixel_9_API_36_Play` with bounded retries, a process watchdog, and `adb` device-state checks, replacing the previous single-shot launch and unbounded `adb wait-for-device`. A dying cold boot now fails fast with a captured log tail instead of hanging. The booted serial is captured and reused by the installed-app proof so result attribution stays tight.
4. `scripts/android_emulator_e2e.sh --verify-offline-startup` installs the APK, clears app state, launches it, and proves the offline bounded state: with no credential saved the live coordinator returns `missingCredential` before any network call, microphone-permission request, or OpenAI request, so the app reaches the `OpenAI setup required` gate and the proof asserts it never remains on `Preparing live session`. No credential is read or saved and no OpenAI request is made.
5. The script prints a sanitized result block (including the run mode) and writes it to `/tmp/realtime-translate-mobile-release-smoke/release-smoke-result.md`. `--record-to-release <tag>` and `--record-to-issue <number>` post that block via `gh` after a secret-pattern guard (default print-only).

The default path reads no OpenAI credential and makes no OpenAI network request. Two network paths are explicit, separate opt-ins:

- `--verify-invalid-credential-recovery` saves a non-secret invalid placeholder credential, grants microphone permission, and **makes a live OpenAI auth-rejection network request** to prove the app fails closed to `OpenAI setup required` without staying on `Preparing live session`. It reads no real secret, but it is a live OpenAI request and is therefore not part of the default offline path.
- `--with-live-credential` reads the local secret file and drives the live realtime path with real credentials.

Boot resilience is local-only by design; Android emulator smoke stays out of CI (see CI Gates below).

For focused store-signing validation, run `scripts/check_android_release_signing.sh` before building and `scripts/check_android_release_signing.sh --apk /tmp/<release-apk>.apk` after building. In a checkout without local signing material, `scripts/check_android_release_signing.sh` must fail clearly while the normal non-live final QA gate can still pass.

Optional screenshot capture should write outside the repo by default:

```bash
adb exec-out screencap -p > /tmp/live-translate-mobile-smoke.png
```

The current app can verify the phone-local start surface, OpenAI setup-required and encrypted credential setup/reset states, Android microphone runtime permission dialog/denied state, teal listening screen after a local credential is configured, manual live source/target language selectors, absence of `Auto-detect` from source choices, hidden live direction switching, scoped AI chat, encrypted meeting history, generated export surfaces, and large-text/compact-viewport behavior. Widget/coordinator regressions now cover hidden `Output voice` checkboxes, hidden language-card voice buttons, visible per-row playback buttons after translation, phone-local TTS utterance routing, transcription-first chunk forwarding and commit timing, distinct transcript rows per completed batch, direct Responses translation into the matching row, and microphone pause/resume around manual row playback. Installed-app validation still must prove physical room microphone pickup from both speakers, committed real transcript batches, per-row audible Android TTS, credential-expiry recovery, transcript de-duplication under real live OpenAI app-coordinator reconnect streaming, iOS share handoff, production-volume storage behavior, and privacy routing assertions.

Latest host validation for the #14 wired live-drop reconnect-trigger proof was 2026-06-01 AWST. `test/openai_realtime_translation_test.dart` adds two tests that exercise the real `OpenAiRealtimeTranslationSession` socket-done path, which all prior reconnect tests bypassed by injecting `OpenAiRealtimeSessionClosed` through a fake session. The first drives a real loopback WebSocket to `session.updated`, drops it mid-session without an application `session.close`, and asserts the session surfaces an `OpenAiRealtimeSessionClosed` event whose coordinator-equivalent failure mapping plans `reconnectAfterBackoff`. The second uses a controllable transport that drops with only a numeric close code and asserts the session emits a sanitized `socket.close_<code>` `OpenAiRealtimeError` that classifies as `retryableNetwork`. Both tests were confirmed to fail when the session's close translation was temporarily removed, then pass after revert, proving they are load-bearing on the real product path. `flutter analyze` (no issues), `flutter test` (134 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh` (107 pinned versions, no advisories), and `git diff --check` passed. This slice is test plus docs only: no dependency, permission, backend route, network path, OpenAI request format, live credential read, microphone recording, or logging surface changed, and no live OpenAI secret was read. The installed-app live reconnect/recovery proof stays with #6 (no emulator audio source).

Latest host validation for the #31 wired live-header local-detection proof was 2026-05-31 AWST and has been superseded by the 2026-06-02 manual-pair UI direction. The same `test/widget_test.dart` path still drives the real `LiveTranslateApp`/coordinator/committer/storage path (faking only the external seams: OpenAI realtime + text-interpreter gateways and the device microphone permission/capture/playback seams) with Italian/English realtime transcripts carrying no `languageCode`, but the active header now starts from the selected `Italian <-> English` pair instead of a first-language waiting state. Local source-language detection remains required for transcript row labels and block splitting when OpenAI metadata is absent. The installed-app live-UI proof stays with #6 because the local emulator has no audio source. No dependency, permission, backend route, network path, OpenAI request format, live credential read, microphone recording, or logging surface changed.

Latest host validation for the #31 round-3 follow-up after the solution-architect review of PR #51 was 2026-06-01 AWST. The architect blocked merge on two residual gaps in the round-3 fix. First, the readable-block roll could still create a sourceless card when source completion arrived while the same turn's translation was still streaming; `test/realtime_translation_coordinator_test.dart` adds the committer case `source completion mid-translation keeps the continued translation on the same card`, which drives the exact failing ordering (source delta, translation delta on a sentence boundary, source done, then later translation delta/done for the same turn) and was confirmed to fail before the fix (2 cards, second sourceless) and pass after (1 card retaining original + full translation). The committer now never rolls a readable block on a translation event on this wire. Second, the all-output/no-source `translationArrivedWithoutSource` flag could not catch Tom's actual round-3 shape once an earlier source had arrived; `test/realtime_translation_coordinator_test.dart` adds `first source-backed turn then a later sourceless final exposes a release-checkable failure state`, proving a first source-backed turn followed by a later sourceless final trips the new `transcriptSignalSnapshot.hasSourcelessFinal` (and `translationArrivedWithoutSource`, now derived from `sourcelessFinalCount > 0`) and emits the content-free `live_realtime.translation_without_source` warning with `hasSourceSignal=true` and `sourcelessFinalCount=1`. `flutter analyze` (no issues), focused `flutter test test/realtime_translation_coordinator_test.dart test/privacy_safe_diagnostics_test.dart` (52 tests), full `flutter test` (148 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh` (107 pinned versions, no advisories), and `git diff --check` all passed. No live API credits were spent; all new coverage is deterministic. No dependency, Android permission, backend route, network path, OpenAI request format, live credential read, or microphone recording changed.

Latest host validation for the #31 round-3 live-source-detection fix was 2026-06-01 AWST. After PR #50, Tom's physical-device retest showed first-turn original speech arriving but later cards reverting to `Original speech pending` (`--` chip) while still translating, with the second language undetected. The residual cause was translation-side readable-block rolling firing while the same source utterance was still streaming, orphaning the continued translation onto a sourceless card. `test/realtime_translation_coordinator_test.dart` adds a committer case (`continuous source utterance is not fragmented into a sourceless card by translation-side rolling`) confirmed to fail before the fix (2 cards, second sourceless) and pass after (1 card retaining original + full translation), a guard (`next source utterance after completion still starts a new card`), and a `realtime source-signal evidence` group proving a translation-only completion raises a content-free `live_realtime.translation_without_source` warning and sets `transcriptSignalSnapshot.translationArrivedWithoutSource`, and that a later source turn updates the snapshot and locks `English <-> Italian` while both cards keep original text. `scripts/live_openai_smoke.dart` now counts source (`session.input_transcript`) and output (`session.output_transcript`) transcript events separately and fails generated-speech/reconnect smokes on translation-only output. `test/privacy_safe_diagnostics_test.dart` adds a case proving the new presence-only signal keys are allowlisted (not redacted) while transcript-bearing keys stay redacted. `flutter analyze` (no issues) and `flutter test` passed; no live API credits were spent. No dependency, Android permission, backend route, network path, OpenAI request format, live credential read, or microphone recording changed.

Latest host validation for the #6 dedicated-translation live smoke harness fix was 2026-05-31 AWST. After `OpenAiRealtimeTranslationSession.events` became single-subscription, the dedicated-translation generated-speech and controlled-reconnect smokes attached a second listener and crashed with `Bad state: Stream has already been listened to`, so they had silently stopped producing live results. The harness now subscribes to each session event stream exactly once (relying on `connect()` blocking until `session.updated` or throwing `OpenAiRealtimeStartupException`), flushes each sanitized result line as it completes, and awaits generated-speech evidence before closing the session. With the local credential supplied through the process environment, `dart run scripts/live_openai_smoke.dart --realtime-translation --realtime-synthetic-audio --realtime-generated-speech --realtime-generated-speech-reconnect` passed 4/4: `realtime-translation-fallback`, `realtime-translation-synthetic-audio` (`syntheticPcm16ToneAppend=200ms nonSpeech`), `realtime-translation-generated-speech` (`transcriptEvents=1 translatedAudioEvents=1`), and `realtime-translation-generated-speech-reconnect` (`controlledReconnect=1 interruptedChunks=2 recoveredTranscriptEvents=1 recoveredTranslatedAudioEvents=3`). A fresh current-main debug APK (SHA-256 `7c19e9e32ec0658a8a6b561a6c105c65ab93eb8dfc04c52fc302fa1b99107bf2`) passed `scripts/check_apk_metadata.sh` with `INTERNET` + `RECORD_AUDIO` present, and `scripts/android_emulator_e2e.sh --verify-offline-startup` reached the bounded `OpenAI setup required` gate without ever sitting on `Preparing live session`; app data was cleared afterward. `flutter analyze` (no issues), `flutter test` (129 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, and `git diff --check` passed. Exact-key leak scan after the live run was repo `0`, `/tmp` artifacts `0`, and process environments `0`. This slice proves only the OpenAI-facing realtime translation gateway path (the same `OpenAiRealtimeTranslationGateway` the live coordinator uses) plus the installed offline bounded-state path; it does not prove physical microphone capture, installed valid-credential `Listening`, the English/Italian two-turn UI flow, or audible Android speaker output, which still require a physical Android device or a host-audio emulator with a real capture source.

Latest debug APK handoff validation on 2026-05-24 20:09 AWST passed with `bash -n scripts/build_debug_apk_artifact.sh`, `git diff --check`, `bash scripts/check-docs.sh`, `flutter analyze`, `flutter test` (76 tests), `bash scripts/check-supply-chain.sh`, `scripts/build_debug_apk_artifact.sh`, and an installed no-credential emulator smoke using `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-ff4096c-20260524T120913Z.apk`. The emulator smoke did not read the live OpenAI secret and verified only install, launch, and the missing-credential gate.

Latest credential reset E2E validation on 2026-05-24 20:20 AWST passed with `bash -n scripts/android_emulator_e2e.sh`, `flutter test test/widget_test.dart`, `flutter analyze`, `flutter test` (76 tests), `bash scripts/check-docs.sh`, `git diff --check`, `bash scripts/check-supply-chain.sh` with the documented Flutter `PATH`, `scripts/build_debug_apk_artifact.sh`, and `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-ac2e265-20260524T121915Z.apk --verify-credential-reset`. The emulator run used only a non-secret placeholder credential, verified the saved value was not visible after save, removed the credential, confirmed the removal action disappeared, and confirmed starting a meeting returned to the setup-required gate. It did not read the live OpenAI secret, call live OpenAI, validate microphone injection, or validate audible speaker output.

Latest release APK handoff hardening on 2026-05-24 AWST added explicit `--release` artifact support. The script reports whether release mode used local `android/key.properties` signing or the debug-signing fallback, and filenames include `release-local-signed` or `release-debug-signed` accordingly. Validation passed with `bash -n scripts/build_debug_apk_artifact.sh`, `scripts/build_debug_apk_artifact.sh --help`, `flutter analyze`, `flutter test` (77 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, `git diff --check`, default debug artifact build, release artifact build, and a no-live installed emulator smoke against `/tmp/realtime-translate-mobile-release-debug-signed-8732d48-20260524T124418Z.apk`. That APK has SHA-256 `d55cf2e5f79bb0b0fa79e0fa217a7df18bf3d81196de680cd809345552f8d005`, uses the debug-signing fallback, and is only a local handoff/smoke artifact, not a store-ready release.

## CI Gates

Current GitHub Actions run on pull requests and pushes to `main`:

- `Docs`: `bash scripts/check-docs.sh`.
- `Flutter`: `flutter pub get`, `flutter analyze`, `flutter test`, and `bash scripts/check-supply-chain.sh`.
- `Android Debug APK`: manual `workflow_dispatch` only; builds a debug APK with `scripts/build_debug_apk_artifact.sh`, runs `scripts/check_apk_metadata.sh`, and uploads the APK plus SHA-256 sidecar for GitHub prerelease attachment.

Android emulator smoke is intentionally local/manual because the project uses Tom's `android-pixel9-headless` machine workflow.

Latest focused validation for the #6/#14 startup and resilience hardening slice was 2026-05-25 AWST. `flutter analyze` passed using a writable Flutter SDK shim under `/tmp/flutter-lite` because the canonical SDK cache is read-only in this sandbox; `/home/tom/.local/share/flutter/bin/cache/dart-sdk/bin/dart analyze lib test`, `bash scripts/check-docs.sh`, and `git diff --check` passed. `flutter test test/realtime_translation_coordinator_test.dart test/widget_test.dart` could not run because the sandbox rejects Flutter test runner localhost server sockets with `Failed to create server socket (OS Error: Operation not permitted, errno = 1), address = 127.0.0.1, port = 0`. `bash scripts/check-supply-chain.sh` could not complete because Gradle cannot open a writable lock under `/home/tom/.gradle` in the sandbox; a writable `GRADLE_USER_HOME` with the existing Gradle distribution symlinked then failed because Gradle's file-lock service could not determine a usable wildcard IP. `flutter build apk --debug` could not complete for the same Gradle lock/IP restrictions, so no APK artifact was produced in this sandbox. The slice adds no dependencies, Android permissions, backend routes, live OpenAI calls, live credential reads, microphone recording, physical voice/frontend E2E, or audible speaker-output claim.

Latest focused validation for the unsupported-language recovery UI slice was 2026-05-24 AWST. `flutter test test/widget_test.dart test/live_session_controller_test.dart` and `git diff --check` passed. The slice carries the realtime recovery action into session state, labels unsupported-language errors as `Language not supported`, and hides the retry action for that non-retryable configuration failure. It adds no dependencies, Android permissions, backend routes, OpenAI request-format changes, production debug hooks, live OpenAI calls, or credential logging.

Latest host validation for the device-audio preflight slice was 2026-05-24 22:14 AWST. `bash -n scripts/android_emulator_e2e.sh` passed. `scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only` failed as expected because the current `Pixel_9_API_36_Play` process was launched with `-no-audio`; proof was written to `/tmp/realtime-translate-mobile-e2e-audio-preflight-precommit/audio-preflight.txt`. The preflight did not install an APK, read the local OpenAI secret, launch the app, or clear app data. `scripts/final_qa_gate.sh` passed with `flutter pub get`, `flutter analyze`, `flutter test` (82 tests), docs check, supply-chain check, shell syntax checks, `git diff --check`, and fresh debug/release APK builds. This slice adds no dependency, Android permission, backend route, OpenAI request change, live credential handling, audio recording, or physical microphone/audible speaker claim.

Latest host validation for the host-audio emulator target was 2026-05-24 22:19 AWST. `bash -n scripts/android_emulator_e2e.sh`, `bash -n scripts/android_pixel9_host_audio.sh`, `bash scripts/check-docs.sh`, `git diff --check`, and `PATH=/home/tom/.local/share/flutter/bin:$PATH bash scripts/check-supply-chain.sh` passed. `ARTIFACT_DIR=/tmp/realtime-translate-mobile-e2e-host-audio-preflight-2 scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only` passed by starting `Pixel_9_API_36_Play` through `scripts/android_pixel9_host_audio.sh`; proof at `/tmp/realtime-translate-mobile-e2e-host-audio-preflight-2/audio-preflight.txt` records `-allow-host-audio` and no `-no-audio`. The preflight did not install an APK, read the local OpenAI secret, launch the app, clear app data, record audio, call OpenAI, or claim physical microphone/speaker behavior.

Latest focused validation for the direct realtime recovery-label slice was 2026-05-24 20:52 AWST. `flutter test test/live_session_controller_test.dart test/widget_test.dart test/realtime_translation_coordinator_test.dart` passed. The slice preserves only sanitized failure categories in session state, renders rate-limit recovery without raw OpenAI error details, and proves credential-expiry/rejection decisions close capture/realtime/playback resources. It made no live OpenAI request, read no live credential, and made no microphone or audible speaker-output claim.

Latest host validation for installed invalid-credential recovery was 2026-05-24 21:17 AWST. `bash -n scripts/android_emulator_e2e.sh`, `flutter test test/openai_realtime_translation_test.dart test/openai_realtime_resilience_test.dart test/realtime_translation_coordinator_test.dart`, `flutter analyze`, `flutter test` (83 tests), `scripts/build_debug_apk_artifact.sh`, and `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-61b9239-20260524T131539Z.apk --verify-invalid-credential-recovery` passed. The emulator run used only a non-secret invalid placeholder credential, pre-granted microphone permission for the negative auth path, observed the realtime auth rejection, verified setup-required recovery, wrote proof under `/tmp/realtime-translate-mobile-e2e-invalid-credential-precommit`, and cleared app data afterward.

Latest host validation for debug installed-app persistence proof was 2026-05-24 21:40 AWST. `bash -n scripts/android_emulator_e2e.sh`, `git diff --check`, `bash scripts/check-docs.sh`, `flutter analyze`, `flutter test` (83 tests), `bash scripts/check-supply-chain.sh`, `scripts/build_debug_apk_artifact.sh --debug-live-events`, and `scripts/android_emulator_e2e.sh --with-live-credential --debug-live-events --apk /tmp/realtime-translate-mobile-debug-live-events-2287189-20260524T133629Z.apk` passed. The APK SHA-256 was `da4ed0de8aeb1c355c5e6c4e1ed1369d8f9167a2f616b5aabd9ab0c4e0c227c1`. The emulator run saved the live credential through the app UI without printing it, accepted microphone permission, ran the debug generated-event proof, restarted the app, verified `4 transcript lines` in encrypted meeting history, reopened the meeting, verified `This meeting` AI context saw `5 local transcript lines`, wrote proof under `/tmp/realtime-translate-mobile-e2e-persistence-precommit`, and cleared app data afterward. Exact key scan counts after cleanup were repo `0`, `/tmp` `0`, `/home/tom/.openclaw/logs` `0`, process environments `0`, and `~/.codex/auth.json` `0`. This did not prove physical microphone input, live transcript persistence from real speech, live OpenAI reconnect in the app, credential-expiry recovery, or audible speaker output.

Latest non-live final QA gate validation was 2026-05-24 21:49 AWST. `scripts/final_qa_gate.sh --emulator-smoke` passed with `flutter pub get`, `flutter analyze`, `flutter test` (82 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, shell syntax checks for repo scripts, `git diff --check`, fresh debug and release APK artifact builds, and a no-live installed-app smoke against `/tmp/realtime-translate-mobile-release-debug-signed-bdd6dcb-20260524T134822Z.apk`. The debug APK SHA-256 was `fe446ad7670619dae3b401d850af4b36b9cce4205428b8c52f73479092030706`; the release APK SHA-256 was `9f51c22befa8f96091108aff2def2e64d898e1b18d1909cae8f6e804ed40e07d`. The release artifact used the debug-signing fallback because local `android/key.properties` was absent, so it is not store-ready. The emulator smoke wrote proof under `/tmp/realtime-translate-mobile-e2e-final-qa`, cleared app data afterward, did not read the local OpenAI secret, did not call live OpenAI, and made no microphone-injection or audible-speaker claim.

Latest store-ready signing preflight validation was 2026-05-24 21:59 AWST. `bash -n scripts/check_android_release_signing.sh`, `scripts/check_android_release_signing.sh`, and `scripts/final_qa_gate.sh --require-store-signing` passed the expected absent-material behavior: store-ready mode failed clearly because `android/key.properties` is missing. Normal `scripts/final_qa_gate.sh` still passed with `flutter pub get`, `flutter analyze`, `flutter test` (82 tests), docs check, supply-chain check, shell syntax checks, `git diff --check`, and fresh APK builds. Debug APK: `/tmp/realtime-translate-mobile-debug-b5e0d2a-20260524T135914Z.apk`, SHA-256 `fe446ad7670619dae3b401d850af4b36b9cce4205428b8c52f73479092030706`. Release APK: `/tmp/realtime-translate-mobile-release-debug-signed-b5e0d2a-20260524T135921Z.apk`, SHA-256 `9f51c22befa8f96091108aff2def2e64d898e1b18d1909cae8f6e804ed40e07d`; it remains debug-signed and not store-ready.
