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
```

Optional live OpenAI smoke, only when a credential is supplied through the process environment from an uncommitted local source:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
OPENAI_API_KEY="<redacted local value>" dart run scripts/live_openai_smoke.dart --all
```

`scripts/check-docs.sh` checks local Markdown links and scans for likely committed OpenAI secret patterns. `scripts/check-supply-chain.sh` checks for obvious credential leaks, verifies Android permission additions against the current allowlist, and queries OSV for pinned hosted Pub and Gradle/Maven runtime package versions. `scripts/live_openai_smoke.dart` uses tiny synthetic transcript text, `store: false`, redacted output, no-microphone realtime session creation for both profiles, synthetic 200 ms non-speech PCM16 append checks for the dedicated translation profile, a primary Realtime 2 synthetic PCM16 append schema check, a local `espeak-ng` generated-Spanish-speech check, and a controlled generated-speech reconnect check for the dedicated translation profile to verify direct OpenAI Responses and realtime endpoint behavior without printing generated content, transcript text, audio bytes, or credential material. The primary Realtime 2 synthetic check does not commit the buffer or claim spoken translation. The generated-speech checks prove transcript and translated-audio event arrival from spoken PCM16 input; the controlled reconnect check proves a second live translation session can recover transcript/audio evidence after an intentionally closed generated-speech socket. They do not prove Android physical microphone capture, installed-app live speech persistence, credential-expiry recovery, or audible speaker output. The installed-app E2E has an opt-in debug-only generated-event proof, enabled only by `--dart-define=LIVE_TRANSLATE_DEBUG_E2E=true` in a debug APK, that verifies coordinator/storage/playback de-duplication inside the installed app without live OpenAI or microphone input. Current Flutter tests cover the phone-local start surface, OpenAI setup-required UI, encrypted OpenAI credential save/read/reset behavior without displaying the saved value, direct realtime WebSocket profile config/event parsing/header-and-body credential non-leakage, Android PCM16 capture config/platform-event parsing, realtime coordinator credential/permission gates, PCM16 chunk flow into the realtime gateway, translated-audio delta decoding into a fakeable PCM16 playback queue, Android MethodChannel playback start/enqueue/stop calls, capture/playback teardown on stop/background/reconnecting, direct realtime failure classification, bounded jittered reconnect planning, fake-gateway reconnect scheduling, transcript-row continuity across a retry, generated-speech-style dedicated translation reconnect event ordering through the coordinator storage path, stale playback clearing and recovered playback queueing after reconnect, playback restart after fake reconnect, debug generated-event proof row/audio counters, reconnect exhaustion interruption status, user-visible reconnecting/offline live recovery banners with retry/back controls, privacy-safe diagnostics redaction and payload omission, scoped AI chat context construction for `This meeting` and `All meetings`, privacy-preserving OpenAI Responses request bodies with `store: false`, direct summary Responses request bodies with `gpt-5.5`, `reasoning.effort: xhigh`, and `store: false`, local Transcript/Summary/Both export composition, mockup-derived listening/AI chat/amber/export surfaces, microphone permission denied UI, deterministic session lifecycle transitions that keep capture/realtime/playback resources closed until permission and local credential gates pass, realtime recovery state transitions that keep resources closed during reconnect/offline/credential-invalid/error states, encrypted local repository behavior for meetings, transcript/history entries, summary text/metadata, language routes, recipient preferences, sensitive preferences, credential/session material, meeting management for deleting or continuing a saved meeting with appended local history, the conservative realtime language support table, direct-OpenAI fallback credential routing for unsupported targets, semantic labels for core controls, and compact large-text rendering across setup, live, assistant, amber, export, and realtime recovery surfaces.

`scripts/android_emulator_e2e.sh --with-live-credential` is the repeatable installed-APK Android E2E path. It reads the live OpenAI credential only from `/home/tom/.openclaw/secrets/realtime-translate-openai-api-key`, starts or reuses `Pixel_9_API_36_Play` in the background, installs the debug APK, verifies the missing-credential gate, saves the credential through the obscured setup field, accepts runtime microphone permission, reaches the live listening surface, opens the `This meeting` AI chat sheet without sending a prompt, writes screenshots/UI XML under `/tmp/realtime-translate-mobile-e2e`, and clears app data afterward. `--debug-live-events` can be added only when the APK was built with `--dart-define=LIVE_TRANSLATE_DEBUG_E2E=true`; it drives generated-speech-shaped events through the installed app coordinator, simulates playback teardown/restart, and verifies one realtime transcript row plus one recovered audio chunk using sanitized UI text. This proves installed-app setup, permission, live-surface entry, local AI-chat UI routing, and debug-only coordinator/storage/playback de-duplication; it still does not prove physical microphone speech injection, committed transcript deltas from live speech, live OpenAI reconnect inside the app, or audible translated-audio output.

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
- Local encrypted storage read/write/delete behavior for meetings, transcript/history, summary metadata, preferences, remembered recipients, last selected recipients, and any credential/session material.
- Meeting management: start new meeting, select old meeting, continue from meeting, delete meeting.
- Scoped AI chat: `This meeting`, `All meetings`, empty transcript, no selected meeting, offline, credential-invalid, unsupported, and model/API error states.
- Email export: Transcript/Summary/Both selector, recipient checklist, add/remove recipients, remembered last selections, direct OpenAI summary generation, encrypted local summary persistence, native mail/share handoff, and no outbound mail backend.
- Privacy-safe diagnostics: allowlisted state/config fields only, redaction of credentials/session tokens, and omission/redaction of transcript, prompt, summary, recipient, export, and audio payloads.
- Widget tests for the supplied mockup-derived surfaces and revised phone-only setup/meeting/export surfaces.
- Accessibility checks for icon-only controls, local setup actions, meeting selectors, language selectors, playback controls, AI chat controls, export controls, recipient checklist, and transcript actions.

## Privacy, Secret, And Cybersecurity Gates

Every implementation change touching OpenAI, logging, storage, permissions, dependencies, export, or transcript handling should include negative tests or documented checks for:

- No standard OpenAI API key in mobile code/config/assets/tests/screenshots/build outputs.
- No transcript/audio/prompt/summary/export payload routed through app-owned backend infrastructure.
- No app backend, AWS, Lambda, token broker, cloud sync, or server mailer added to MVP code.
- No transcript/audio/prompt/summary/recipient payload in logs, analytics, diagnostics, crash reports, screenshots, or test output.
- Diagnostics use `PrivacySafeDiagnostics` or an equivalent allowlist/redaction path before reaching any sink.
- AI chat uses the explicit `This meeting` or `All meetings` scope and direct OpenAI path.
- Email export uses local preparation and user-initiated device-native mail/share composer semantics where practical.
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
- Email export type selector and recipient checklist.
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
scripts/android_emulator_e2e.sh --with-live-credential
flutter build apk --debug --dart-define=LIVE_TRANSLATE_DEBUG_E2E=true
scripts/android_emulator_e2e.sh --with-live-credential --debug-live-events
```

Optional screenshot capture should write outside the repo by default:

```bash
adb exec-out screencap -p > /tmp/live-translate-mobile-smoke.png
```

The current app can verify the phone-local start surface, OpenAI setup-required and encrypted credential setup/reset states, Android microphone runtime permission dialog/denied state, teal listening screen after a local credential is configured, realtime target language options, scoped AI chat bottom sheet for `This meeting`, `All meetings` AI chat from meeting history, amber paused read-aloud screen with unsupported-target fallback credential state, encrypted meeting history sheet with continue/delete controls, appended local meeting history after reopening a saved meeting, email export sheet with remembered recipient preferences/add-remove controls, transcript native share handoff, summary generation UI state, encrypted local summary persistence, Summary/Both local export composition, and large-text/compact-viewport behavior for those core surfaces. The installed E2E driver passed on 2026-05-24 by driving the missing-credential gate, encrypted credential save, runtime microphone permission, live listening surface, and `This meeting` AI chat sheet on `Pixel_9_API_36_Play`, with artifacts under `/tmp/realtime-translate-mobile-e2e` and app data cleared afterward. The debug-only generated-event E2E mode is now documented for installed-app coordinator/storage/playback de-duplication when a debug APK is built with `LIVE_TRANSLATE_DEBUG_E2E=true`. Direct realtime WebSocket profile/event behavior, PCM16 capture lifecycle, translated-audio playback queue decode/recovery behavior, Android playback MethodChannel behavior, realtime coordinator behavior including generated-speech-style reconnect storage continuity, debug generated-event proof counters, realtime resilience classification/backoff behavior, direct summary Responses request behavior, generated spoken-audio transcript/translated-audio event arrival, and controlled generated-speech reconnect recovery are covered by local fake gateways, controller/coordinator tests, focused playback tests, and the redacted live OpenAI smoke harness. Direct OpenAI realtime audio streaming with a physical microphone source, audible Android speaker recovery under live streaming, committed real transcript deltas from the installed app, credential-expiry recovery, transcript de-duplication under real live OpenAI app-coordinator reconnect streaming, iOS share handoff, production-volume storage behavior, and privacy routing assertions become required as their implementation issues land.

## CI Gates

Current GitHub Actions run on pull requests and pushes to `main`:

- `Docs`: `bash scripts/check-docs.sh`.
- `Flutter`: `flutter pub get`, `flutter analyze`, `flutter test`, and `bash scripts/check-supply-chain.sh`.

Android emulator smoke is intentionally local/manual because the project uses Tom's `android-pixel9-headless` machine workflow.

Latest validation for the realtime recovery UI slice was 2026-05-24 19:54 AWST. `flutter pub get`, `flutter analyze`, `flutter test` (76 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, `git diff --check`, `flutter build apk --debug`, and `scripts/android_emulator_e2e.sh --with-live-credential` passed. Redacted live OpenAI smoke `--all` could not produce valid live results because the local secret returned `insufficient_quota` for Responses and Realtime requests. The slice adds a live-surface listener for asynchronous session-state changes and widget coverage for `reconnecting` and `offline` recovery banners. It adds no dependencies, Android permissions, backend routes, OpenAI request-format changes, production debug hooks, or credential logging. Physical microphone injection remains blocked by the current emulator workflow; no physical microphone or audible speaker-output claim is made.
