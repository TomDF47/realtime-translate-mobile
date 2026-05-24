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

`scripts/check-docs.sh` checks local Markdown links and scans for likely committed OpenAI secret patterns. `scripts/check-supply-chain.sh` checks for obvious credential leaks, verifies Android permission additions against the current allowlist, and queries OSV for pinned hosted Pub and Gradle/Maven runtime package versions. Current Flutter tests cover the phone-local start surface, mockup-derived listening/AI chat/amber/export surfaces, microphone permission denied UI, deterministic session lifecycle transitions that keep capture/realtime/playback resources closed until permission is granted, encrypted local repository behavior for meetings, transcript/history entries, summary metadata, language routes, recipient preferences, sensitive preferences, credential/session material, meeting management for deleting or continuing a saved meeting with appended local history, semantic labels for core controls, and compact large-text rendering across setup, live, assistant, amber, and export surfaces.

## Flutter App Gates

Once the Flutter scaffold exists, app changes should run:

```bash
flutter analyze
flutter test
```

Expected coverage areas:

- Session state model transitions: local setup, meeting selection, connecting, listening, speaking, read-aloud paused, reconnecting, offline, credential invalid, and error.
- Microphone permission states: granted, denied, permanently denied, and revoked.
- Direct OpenAI integration seams for realtime translation, AI chat, and summary generation.
- Language support table and unsupported-target fallback behavior.
- Local encrypted storage read/write/delete behavior for meetings, transcript/history, summary metadata, preferences, remembered recipients, last selected recipients, and any credential/session material.
- Meeting management: start new meeting, select old meeting, continue from meeting, delete meeting.
- Scoped AI chat: `This meeting`, `All meetings`, empty transcript, no selected meeting, offline, credential-invalid, unsupported, and model/API error states.
- Email export: Transcript/Summary/Both selector, recipient checklist, add/remove recipients, remembered last selections, native mail/share handoff, and no outbound mail backend.
- Widget tests for the supplied mockup-derived surfaces and revised phone-only setup/meeting/export surfaces.
- Accessibility checks for icon-only controls, local setup actions, meeting selectors, language selectors, playback controls, AI chat controls, export controls, recipient checklist, and transcript actions.

## Privacy, Secret, And Cybersecurity Gates

Every implementation change touching OpenAI, logging, storage, permissions, dependencies, export, or transcript handling should include negative tests or documented checks for:

- No standard OpenAI API key in mobile code/config/assets/tests/screenshots/build outputs.
- No transcript/audio/prompt/summary/export payload routed through app-owned backend infrastructure.
- No app backend, AWS, Lambda, token broker, cloud sync, or server mailer added to MVP code.
- No transcript/audio/prompt/summary/recipient payload in logs, analytics, diagnostics, crash reports, screenshots, or test output.
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

The current app can verify the phone-local start surface, Android microphone runtime permission dialog/denied state, teal listening screen, scoped AI chat bottom sheet, amber paused read-aloud screen, encrypted meeting history sheet with continue/delete controls, appended local meeting history after reopening a saved meeting, email export sheet with remembered recipient preferences, and large-text/compact-viewport behavior for those core surfaces. Real microphone capture, direct OpenAI streaming, native share handoff, production-volume storage behavior, and privacy routing assertions become required as their implementation issues land.

## CI Gates

Current GitHub Actions run on pull requests and pushes to `main`:

- `Docs`: `bash scripts/check-docs.sh`.
- `Flutter`: `flutter pub get`, `flutter analyze`, `flutter test`, and `bash scripts/check-supply-chain.sh`.

Android emulator smoke is intentionally local/manual because the project uses Tom's `android-pixel9-headless` machine workflow.
