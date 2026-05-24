# Realtime Translate Mobile

Android-first Flutter app for live speech translation, designed to stay iOS-compatible.

## Source Of Truth

- Canonical build spec: [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md)
- Mockup UX spec: [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md)
- Supplied mockups: [assets/mockups](assets/mockups)
- Codex agent instructions: [AGENTS.md](AGENTS.md)
- Development workflow: [docs/development-workflow.md](docs/development-workflow.md)
- Architecture handoff: [docs/architecture.md](docs/architecture.md)
- V2/future scope: [docs/v2-future-scope.md](docs/v2-future-scope.md)
- Cybersecurity report: [docs/cybersecurity-report.md](docs/cybersecurity-report.md)
- Environment setup: [docs/environment.md](docs/environment.md)
- Testing strategy: [docs/testing-strategy.md](docs/testing-strategy.md)
- Decision log: [docs/decision-log.md](docs/decision-log.md)

## Decision Record

- Mobile app: Flutter, Android-first, iOS-compatible later
- MVP backend: none
- Routine network path: phone app connects directly to the OpenAI API only
- Main translation model: `gpt-realtime-translate`
- AI chat: scoped explicitly to `This meeting` or `All meetings`
- Data storage: local encrypted device storage only
- Meeting management: local meetings with transcript/history/summary metadata stored on phone
- Email export: user-initiated device-native mail/share composer where practical; no outbound mail backend
- Deferred scope: AWS, Lambda, token broker, app backend, cloud identity, cloud sync, and server-side transcript handling are V2/future only

## Product Direction

The app should feel premium, clean, and executive-grade. The MVP is phone-only aside from direct OpenAI API calls. The first usable surface should help a user start or resume a live translation meeting, not sign into an app backend or configure cloud infrastructure.

## Current Status

Planning repo created. Supplied Android mockups have been received, copied into [assets/mockups](assets/mockups), and captured in [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md). The canonical build-ready spec is [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).

The Flutter scaffold now exists with Android and iOS project structure, app ID `com.tomdf47.realtime_translate_mobile`, Android signing placeholders, and a mockup-derived UI shell. The current app can render the phone-local welcome/start screen, teal listening live translation surface, scoped AI chat bottom sheet, amber speaking/read-aloud-paused surface, meeting history sheet, and local email export sheet. The repo still contains no backend implementation, cloud identity, cloud sync, server mailer, OpenAI integration, microphone capture, or server-side transcript handling.

Keep future work aligned to the GitHub issue acceptance criteria and preserve the phone-only MVP privacy boundary.

## Repository Map

- [AGENTS.md](AGENTS.md): required operating contract for future Codex jobs.
- [CONTRIBUTING.md](CONTRIBUTING.md): contribution and PR expectations.
- [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md): canonical product, architecture, privacy, and implementation spec.
- [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md): visual and interaction source of truth for the first Flutter UI pass.
- [docs/architecture.md](docs/architecture.md): mobile, OpenAI, storage, email export, and prohibited data-flow boundaries.
- [docs/v2-future-scope.md](docs/v2-future-scope.md): deferred cloud/backend/auth scope.
- [docs/cybersecurity-report.md](docs/cybersecurity-report.md): cybersecurity baseline and dependency-advisory methodology.
- [docs/development-workflow.md](docs/development-workflow.md): issue workflow, doc update matrix, and handoff checklist.
- [docs/environment.md](docs/environment.md): local setup, emulator notes, env placeholders, and secret handling.
- [docs/testing-strategy.md](docs/testing-strategy.md): docs, Flutter, privacy, cybersecurity, and emulator verification plan.
- [docs/decision-log.md](docs/decision-log.md): durable decisions future agents should preserve.
- [docs/codex-starter-prompt.md](docs/codex-starter-prompt.md): starter prompt for the first Flutter implementation pass.
- [.env.example](.env.example): placeholder-only environment contract.
- [scripts/check-docs.sh](scripts/check-docs.sh): docs link and secret-pattern sanity check.
- [pubspec.yaml](pubspec.yaml) and [pubspec.lock](pubspec.lock): Flutter package manifest and pinned dependency lockfile.
- [lib/main.dart](lib/main.dart): current phone-local Flutter start surface.
- [lib/src/theme/live_translate_theme.dart](lib/src/theme/live_translate_theme.dart): shared colors, spacing, radii, text styles, elevation, and app theme.
- [lib/src/ui/live_translate_models.dart](lib/src/ui/live_translate_models.dart): structured UI state for sessions, transcripts, AI chat scope, export type, and controls.
- [lib/src/ui/live_translate_components.dart](lib/src/ui/live_translate_components.dart): reusable mockup-aligned Flutter components.
- [lib/src/mock/mock_live_translate_data.dart](lib/src/mock/mock_live_translate_data.dart): local-only sample session data for UI and widget tests.
- [test/widget_test.dart](test/widget_test.dart): current Flutter widget smoke test.
- [test/design_system_test.dart](test/design_system_test.dart): design-system unit/widget coverage.
- [android](android): Android Flutter project, app namespace, debug build config, and local signing placeholder.
- [ios](ios): iOS-compatible Flutter project shell.

## Design System Conventions

Future UI work should use the shared Flutter foundation instead of hard-coded one-off values:

- Use `LiveTranslateTheme.dark()`, `AppColors`, `AppSpacing`, `AppRadii`, `AppElevation`, and `AppTextStyles` for visual decisions.
- Drive session labels and state accents through `LiveSessionViewData`, `LiveSessionMode`, `LiveAccent`, and related model types.
- Keep AI chat scope explicit through `AiChatScope.thisMeeting` or `AiChatScope.allMeetings`.
- Build mockup-derived surfaces from `live_translate_components.dart` components such as `LiveTranslateShell`, `SessionStatusCard`, `LanguageSelectorCard`, `FeatureChip`, `TranscriptCard`, `TranscriptList`, `QueueBanner`, `JumpToLiveChip`, `BottomControlBar`, `PromptActionChip`, and `ExportTypeSelector`.
- Transcript lists that sit behind fixed bottom controls should reserve at least `AppSpacing.bottomControlsHeight` plus safe-area padding.
- Keep sample transcript/session content local to `MockLiveTranslateData` until realtime, encrypted storage, and meeting management issues replace it with product data.

## Local Setup

Use the local Flutter SDK installed for this workspace:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter pub get
flutter analyze
flutter test
bash scripts/check-docs.sh
```

For Android debug build and smoke checks:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter build apk --debug
android-pixel9-headless
flutter devices
flutter run -d <android-emulator-id>
```

Do not add real credentials to `.env.example` or any committed file. Use uncommitted local env files only for local development placeholders. Mobile credential/session material must not be bundled into the app; the implementation must verify the current OpenAI-supported direct mobile approach before coding.

For local Android release-signing experiments, copy [android/key.properties.example](android/key.properties.example) to `android/key.properties` and use local placeholder values only. `android/key.properties` is ignored and must not be committed.

## GitHub Issue Map

Closed planning and implementation intake:

- #1 Finalize product spec and mockup intake
- #2 Scaffold Flutter mobile app
- #3 Implement Flutter UI from supplied mockups for phone-only MVP
- #11 Document Android emulator workflow for Codex
- #18 Define Flutter design tokens and reusable mockup components

Open MVP/planning work:

- #6 Integrate direct OpenAI Realtime Translation
- #7 Implement language support and fallback routing
- #8 Add scoped AI chat over local meetings
- #9 Implement local encrypted meeting storage
- #10 Maintain cybersecurity threat model and report
- #12 Create phone-only MVP test strategy
- #13 Implement microphone permissions and live session lifecycle
- #14 Harden direct OpenAI realtime resilience
- #15 Implement privacy-safe local logging and diagnostics controls
- #16 Add CI quality gates for docs, Flutter, and secret safety
- #17 Add accessibility and responsive text verification
- #19 Maintain README and agent handoff docs during implementation
- #20 Implement local meeting management
- #21 Add email export for transcripts and summaries
- #22 Implement dependency and supply-chain cybersecurity controls

Deferred V2/future work:

- #4 V2: Implement Google and Microsoft sign-in
- #5 V2: Build AWS Lambda token broker

## Supplied Mockups

All supplied mockups are 720x1280 Android portrait JPGs:

- [01-welcome-sign-in.jpg](assets/mockups/01-welcome-sign-in.jpg)
- [02-live-listening-teal.jpg](assets/mockups/02-live-listening-teal.jpg)
- [03-transcript-assistant.jpg](assets/mockups/03-transcript-assistant.jpg)
- [04-speaking-paused-amber.jpg](assets/mockups/04-speaking-paused-amber.jpg)

The mockups remain the visual source of truth. MVP behavior has changed to phone-only operation, so provider sign-in buttons in the welcome mockup are V2/future unless a later decision restores cloud identity to MVP.

## Implementation Guardrails

- Never embed a standard OpenAI API key in mobile source, committed config, assets, tests, screenshots, or build outputs.
- Preserve the phone-only MVP architecture: no app backend, AWS, Lambda, token broker, cloud sync, server mailer, or server-side transcript handling.
- Direct OpenAI API calls are the only routine network path for product behavior.
- Keep AI chat on a direct OpenAI path scoped explicitly to `This meeting` or `All meetings`.
- Store meeting history, transcripts, summaries, recipient preferences, and sensitive local data only in encrypted device storage for the MVP.
- Use device-native mail/share composer semantics where practical for export; do not add an outbound mail backend.
- Keep logs, crash reports, analytics, diagnostics, screenshots, and test output free of speech, transcript payloads, prompts, translations, summaries, recipient lists, OpenAI credentials/session material, and API keys.
- Verify current OpenAI Realtime Translation target language support, direct mobile credential/session support, and summary model/reasoning support during implementation.
- Treat cybersecurity as a first-class acceptance criterion: dependency hygiene, supply-chain checks, mobile permission minimization, secret scanning, and no transcript leakage are required.

## Verification

Current local gates:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter pub get
flutter analyze
flutter test
bash scripts/check-docs.sh
```

Additional checks for app changes:

- Secret scan or equivalent check for standard OpenAI API key leakage
- Dependency/advisory checks for pinned Flutter/Dart/native package versions
- Android emulator smoke check using `android-pixel9-headless`
- UI smoke coverage for supplied mockup-derived surfaces, meeting management, scoped AI chat, and email export
- Privacy routing test showing transcript/audio/prompt/summary/export content does not call an app backend
- Logging/diagnostics test showing sensitive payloads and credentials are absent or redacted

## Documentation Maintenance

Every future change should update this README when setup, architecture, product behavior, issue status, verification steps, or known risks change. Product or architecture decision changes should also update [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).

## Development Notes

Tom's Fedora machine has an Android SDK and boot-tested emulator available:

```bash
android-pixel9-headless
```

Use that instead of `emulator -no-window`, which segfaults on this machine.
