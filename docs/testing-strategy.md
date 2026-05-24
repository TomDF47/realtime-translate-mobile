# Testing Strategy

This is the MVP verification plan. Keep commands concrete as implementation lands.

## Current Local Gates

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter pub get
flutter analyze
flutter test
bash scripts/check-docs.sh
```

`scripts/check-docs.sh` checks local Markdown links and scans for likely committed OpenAI secret patterns. Current Flutter tests cover the phone-local start surface, mockup-derived listening/AI chat/amber/export surfaces, microphone permission denied UI, and deterministic session lifecycle transitions that keep capture/realtime/playback resources closed until permission is granted.

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

The current app can verify the phone-local start surface, Android microphone runtime permission dialog/denied state, teal listening screen, scoped AI chat bottom sheet, amber paused read-aloud screen, meeting management entry point, and email export sheet. Real microphone capture, direct OpenAI streaming, encrypted storage persistence, native share handoff, and privacy routing assertions become required as their implementation issues land.

## CI Direction

The first committed CI gate should run docs validation without requiring Flutter. After implementation lands, expand CI to include Flutter analysis/tests, secret-safety checks, dependency/advisory checks, and privacy/logging assertions.
