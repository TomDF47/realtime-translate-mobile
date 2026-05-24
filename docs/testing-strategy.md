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

`scripts/check-docs.sh` checks local Markdown links and scans for likely committed OpenAI secret patterns. `scripts/check-supply-chain.sh` checks for obvious credential leaks, verifies Android permission additions against the current allowlist, and queries OSV for pinned hosted Pub and Gradle/Maven runtime package versions. Current Flutter tests cover the phone-local start surface, OpenAI setup-required UI, encrypted OpenAI credential save/read/reset behavior without displaying the saved value, direct realtime WebSocket profile config/event parsing/header-and-body credential non-leakage, privacy-safe diagnostics redaction and payload omission, scoped AI chat context construction for `This meeting` and `All meetings`, privacy-preserving OpenAI Responses request bodies with `store: false`, direct summary Responses request bodies with `gpt-5.5`, `reasoning.effort: xhigh`, and `store: false`, local Transcript/Summary/Both export composition, mockup-derived listening/AI chat/amber/export surfaces, microphone permission denied UI, deterministic session lifecycle transitions that keep capture/realtime/playback resources closed until permission and local credential gates pass, encrypted local repository behavior for meetings, transcript/history entries, summary text/metadata, language routes, recipient preferences, sensitive preferences, credential/session material, meeting management for deleting or continuing a saved meeting with appended local history, the conservative realtime language support table, direct-OpenAI fallback credential routing for unsupported targets, semantic labels for core controls, and compact large-text rendering across setup, live, assistant, amber, and export surfaces.

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

Optional screenshot capture should write outside the repo by default:

```bash
adb exec-out screencap -p > /tmp/live-translate-mobile-smoke.png
```

The current app can verify the phone-local start surface, OpenAI setup-required and encrypted credential setup/reset states, Android microphone runtime permission dialog/denied state, teal listening screen after a local credential is configured, realtime target language options, scoped AI chat bottom sheet for `This meeting`, `All meetings` AI chat from meeting history, amber paused read-aloud screen with unsupported-target fallback credential state, encrypted meeting history sheet with continue/delete controls, appended local meeting history after reopening a saved meeting, email export sheet with remembered recipient preferences/add-remove controls, transcript native share handoff, summary generation UI state, encrypted local summary persistence, Summary/Both local export composition, and large-text/compact-viewport behavior for those core surfaces. Direct realtime WebSocket profile/event behavior and direct summary Responses request behavior are currently covered by local fake gateways, not live OpenAI API-key smoke. Real microphone capture, direct OpenAI realtime streaming against OpenAI, decoded translated-audio playback, live OpenAI API-key smoke for AI chat/realtime/summary generation, iOS share handoff, production-volume storage behavior, and privacy routing assertions become required as their implementation issues land.

## CI Gates

Current GitHub Actions run on pull requests and pushes to `main`:

- `Docs`: `bash scripts/check-docs.sh`.
- `Flutter`: `flutter pub get`, `flutter analyze`, `flutter test`, and `bash scripts/check-supply-chain.sh`.

Android emulator smoke is intentionally local/manual because the project uses Tom's `android-pixel9-headless` machine workflow.
