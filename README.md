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
- Privacy-safe diagnostics: [docs/privacy-safe-diagnostics.md](docs/privacy-safe-diagnostics.md)
- Environment setup: [docs/environment.md](docs/environment.md)
- Testing strategy: [docs/testing-strategy.md](docs/testing-strategy.md)
- Decision log: [docs/decision-log.md](docs/decision-log.md)

## Decision Record

- Mobile app: Flutter, Android-first, iOS-compatible later
- MVP backend: none
- Routine network path: phone app connects directly to the OpenAI API only
- Preferred realtime voice/translation model: `gpt-realtime-2`, with `gpt-realtime-translate` kept as a dedicated translation fallback/profile
- AI chat: scoped explicitly to `This meeting` or `All meetings`
- Data storage: local encrypted device storage only
- Meeting management: local meetings with transcript/history/summary metadata stored on phone
- Email export: user-initiated device-native mail/share composer where practical; no outbound mail backend
- Deferred scope: AWS, Lambda, token broker, app backend, cloud identity, cloud sync, and server-side transcript handling are V2/future only

## Product Direction

The app should feel premium, clean, and executive-grade. The MVP is phone-only aside from direct OpenAI API calls. The first usable surface should help a user start or resume a live translation meeting, not sign into an app backend or configure cloud infrastructure.

## Current Status

Planning repo created. Supplied Android mockups have been received, copied into [assets/mockups](assets/mockups), and captured in [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md). The canonical build-ready spec is [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).

The Flutter scaffold now exists with Android and iOS project structure, app ID `com.tomdf47.realtime_translate_mobile`, Android signing placeholders, a mockup-derived UI shell, Android runtime microphone permission handling, a deterministic local session lifecycle controller, encrypted local meeting storage, local meeting management, a centralized language support/fallback table, phone-local OpenAI setup with encrypted credential storage/reset, privacy-safe local diagnostics/redaction controls, direct OpenAI realtime WebSocket request/event scaffolding and resilience policy scaffolding, Android PCM16 microphone capture, Android PCM16 translated-audio speaker output behind the fakeable playback gateway, scoped AI chat context/request scaffolding for the direct OpenAI Responses API path, local meeting summary generation scaffolding for export, transcript export composition with Android native share handoff, accessibility/responsive text coverage, a repeatable local supply-chain/security gate, a redacted live OpenAI smoke harness, and a repeatable installed-APK Android emulator E2E driver. The current app can render the phone-local welcome/start screen, OpenAI setup-required state, encrypted OpenAI setup sheet, microphone permission denied state, teal listening live translation surface after a local credential is configured, scoped AI chat bottom sheet for `This meeting`, `All meetings` AI chat from meeting history, amber speaking/read-aloud-paused surface, encrypted meeting history sheet with stored metadata, select-and-continue behavior that appends local transcript history, delete controls, local language target options, a fallback credential-required state for unsupported realtime targets, and local email export sheet with encrypted recipient preferences/add-remove controls. The realtime path can build/test a primary `gpt-realtime-2` profile plus a dedicated `gpt-realtime-translate` fallback/profile, connect through a fakeable WebSocket with credential material in the Authorization header only, stream Android `AudioRecord` 24 kHz mono PCM16 chunks through a fakeable capture gateway, parse translated audio/transcript deltas and completion events, decode translated-audio chunks into a fakeable PCM16 playback gateway, hand production playback chunks to Android `AudioTrack` through a bounded transient queue, coalesce realtime transcript deltas into one encrypted local meeting row per live segment, classify direct realtime failures, schedule bounded reconnect attempts after retryable failures, and close capture/realtime/playback resources during reconnecting/offline/credential-invalid/backgrounded/stopped states. For microphone streaming, the app currently uses the dedicated translation profile because the official OpenAI Realtime docs identify `/v1/realtime/translations` and `gpt-realtime-translate` as the live human-speech translation path; live synthetic PCM16 append is accepted for that path, a local generated-Spanish-speech smoke now receives transcript and translated-audio events from that path, a controlled generated-speech reconnect smoke proves a second dedicated translation session can recover transcript/audio evidence after an intentionally closed live socket, and the primary `gpt-realtime-2` profile accepts a non-speech synthetic PCM16 append after the session output audio format includes an explicit 24 kHz rate. The installed E2E driver has passed on `Pixel_9_API_36_Play`: it installs the debug APK, verifies the missing-credential gate, saves a live credential through the obscured OpenAI setup field, accepts runtime microphone permission, reaches the live listening surface, opens the `This meeting` AI chat sheet without sending a prompt, captures proof under `/tmp/realtime-translate-mobile-e2e`, and clears app data afterward. An opt-in debug-only installed-app proof can now be enabled only with a debug APK built using `--dart-define=LIVE_TRANSLATE_DEBUG_E2E=true`; it drives generated-speech-shaped realtime events through the coordinator, simulates playback teardown/restart, verifies exactly one new realtime transcript row, and reports only sanitized row/audio counts to UIAutomator. The primary append smoke does not prove spoken translation, and the generated-speech, debug-event, and installed-app smokes do not prove physical microphone capture or audible Android speaker output, so dedicated translation remains the MVP microphone-streaming route while real device/emulator microphone validation remains open. AI chat builds local transcript context, uses `store: false`, keeps scope explicit, and has a fakeable direct OpenAI Responses client; live Responses smoke passed for `This meeting` and `All meetings` on 2026-05-24. Transcript exports are prepared locally and handed to the Android share sheet. Summary and Both exports now build a direct phone-to-OpenAI Responses request with `gpt-5.5`, `reasoning.effort: xhigh`, and `store: false`, persist the generated summary text/metadata only in encrypted local storage, and then hand the selected local export payload to the Android share sheet. Live OpenAI smoke for summary generation passed on 2026-05-24 with the expected summary headings validated without printing generated text. The repo still contains no backend implementation, cloud identity, cloud sync, server mailer, analytics/crash reporting sink, or server-side transcript handling.

OpenAI Realtime verification for #6 found that `gpt-realtime-2` is documented as the standard voice-agent model on `/v1/realtime`, while `gpt-realtime-translate` is documented as the dedicated streaming speech-to-speech translation model on `/v1/realtime/translations`. Official client-safe Realtime client secrets are still minted by a developer-controlled server using a standard API key, so #23 closed with Tom's MVP decision: proceed phone-to-OpenAI directly with user-provided OpenAI credential/session material stored only in encrypted local device storage, do not commit or bundle any key, and ask Tom for an API key only at the first real OpenAI network smoke/integration test. Live endpoint smoke on 2026-05-24 accepted `gpt-realtime-2` on `/v1/realtime` and `gpt-realtime-translate` on `/v1/realtime/translations`; both returned `session.created` without recording or sending microphone audio. A prior primary append attempt returned sanitized `missing_required_parameter` with `param=session.audio.output.format.rate`; the primary session config now includes `rate: 24000` for output audio, and the redacted live smoke accepts a 200 ms non-speech synthetic PCM16 append after `session.updated`. The dedicated translation endpoint accepts a synthetic 200 ms PCM16 append and now passes a generated spoken-audio smoke that synthesizes a short Spanish phrase locally with `espeak-ng`, converts it in memory to 24 kHz mono PCM16, streams it in 200 ms chunks, and validates that transcript and translated-audio events arrive without printing transcript text, audio bytes, or credential material. The app therefore keeps the primary profile available but routes microphone streaming and realtime transcript commitment through the dedicated translation profile for the live-interpretation MVP until physical microphone translation is validated.

Realtime resilience behavior for #14 is locally scaffolded, and the live endpoint smoke now proves the configured realtime models can create sessions. Credential expiry or rejection moves the session to `credentialInvalid`; unsupported realtime language failures move to `error` with a language-specific recovery banner that does not offer a retry loop; retryable network drops, socket closes, rate limits, transient OpenAI errors, and lifecycle interruption schedule bounded exponential backoff with jitter and enter `reconnecting` with microphone capture, realtime, and playback resources closed during backoff; exhausted network or lifecycle retries move to `offline`; fatal errors move to `error`. The home screen now listens to asynchronous session-state changes after live start, so `reconnecting`, `offline`, and `error` states show a user-visible recovery banner on the live surface with retry/back controls where appropriate; `credentialInvalid` continues to show the OpenAI setup-required recovery screen without displaying credential material. Diagnostics record only operation/result labels, sanitized error codes, retry attempt, and backoff milliseconds. Unit tests now prove realtime transcript deltas are upserted into encrypted local meeting storage without duplicate rows for a live segment, translated audio deltas are decoded into a fakeable PCM16 playback queue, Android playback MethodChannel calls carry PCM16 bytes to native output without logging or persistence, a fake retryable socket close reconnects without duplicating the active transcript row while restarting playback/capture resources, a generated-speech-style dedicated translation reconnect keeps one committed transcript row while clearing stale playback chunks and queueing recovered audio, stopped/reconnecting/offline/unsupported-language recovery banners render with the expected user-visible labels, and a failed reconnect marks the partial row interrupted when retries exhaust. The generated-speech smoke proves the dedicated translation endpoint can emit live transcript and translated-audio events from spoken PCM16 input; the controlled reconnect smoke opens a live dedicated translation session, streams generated speech chunks, intentionally closes that socket, reconnects, and verifies recovered transcript/audio events from the second session. Transcript de-duplication under a real live app-coordinator reconnect, audible translated-audio recovery under live streaming, credential-expiry recovery, and a real physical microphone translation smoke still require later #14/#6 work.

Language support verification for #7 on 2026-05-24 used the official OpenAI Realtime Translation guide, `gpt-realtime-translate` model page, and translation client-secret API reference. Those docs confirm the dedicated `/v1/realtime/translations` endpoint and `audio.output.language` target parameter, but they do not expose an authoritative target-language enum. The app therefore uses a conservative realtime target table for English, Spanish, and French, treats broader targets such as Japanese as direct-OpenAI fallback-pending, and keeps fallback phone-only with no AWS, backend, cloud sync, or server-side transcript handling.

Keep future work aligned to the GitHub issue acceptance criteria and preserve the phone-only MVP privacy boundary.

## Repository Map

- [AGENTS.md](AGENTS.md): required operating contract for future Codex jobs.
- [CONTRIBUTING.md](CONTRIBUTING.md): contribution and PR expectations.
- [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md): canonical product, architecture, privacy, and implementation spec.
- [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md): visual and interaction source of truth for the first Flutter UI pass.
- [docs/architecture.md](docs/architecture.md): mobile, OpenAI, storage, email export, and prohibited data-flow boundaries.
- [docs/v2-future-scope.md](docs/v2-future-scope.md): deferred cloud/backend/auth scope.
- [docs/cybersecurity-report.md](docs/cybersecurity-report.md): cybersecurity baseline and dependency-advisory methodology.
- [docs/privacy-safe-diagnostics.md](docs/privacy-safe-diagnostics.md): local diagnostics allowlist, redaction rules, and forbidden payload categories.
- [docs/development-workflow.md](docs/development-workflow.md): issue workflow, doc update matrix, and handoff checklist.
- [docs/environment.md](docs/environment.md): local setup, emulator notes, env placeholders, and secret handling.
- [docs/testing-strategy.md](docs/testing-strategy.md): docs, Flutter, privacy, cybersecurity, and emulator verification plan.
- [docs/decision-log.md](docs/decision-log.md): durable decisions future agents should preserve.
- [docs/codex-starter-prompt.md](docs/codex-starter-prompt.md): starter prompt for the first Flutter implementation pass.
- [.env.example](.env.example): placeholder-only environment contract.
- [.github/workflows/docs.yml](.github/workflows/docs.yml): CI docs link and secret-pattern gate.
- [.github/workflows/flutter.yml](.github/workflows/flutter.yml): CI Flutter analysis, tests, and supply-chain gate.
- [scripts/check-docs.sh](scripts/check-docs.sh): docs link and secret-pattern sanity check.
- [scripts/check-supply-chain.sh](scripts/check-supply-chain.sh): local dependency advisory, secret-pattern, and Android permission gate.
- [scripts/build_debug_apk_artifact.sh](scripts/build_debug_apk_artifact.sh): repeatable Android APK builder/copier for debug, debug E2E, and local release artifacts; writes a clearly named APK plus SHA-256 sidecar under `/tmp` without reading OpenAI credentials and labels debug-signed release artifacts as not store-ready.
- [scripts/live_openai_smoke.dart](scripts/live_openai_smoke.dart): redacted live OpenAI smoke harness for Responses summary/AI chat, realtime endpoint availability, synthetic PCM16 append checks, local generated-speech realtime translation validation, and controlled generated-speech reconnect validation.
- [scripts/android_emulator_e2e.sh](scripts/android_emulator_e2e.sh): installed-APK Android emulator E2E driver for the start/setup/permission/live-surface/AI-chat path, non-live credential reset UX validation, plus an opt-in debug-only generated-event proof when the APK is built with `LIVE_TRANSLATE_DEBUG_E2E=true`; artifacts are written under `/tmp` and app data is cleared afterward.
- [pubspec.yaml](pubspec.yaml) and [pubspec.lock](pubspec.lock): Flutter package manifest and pinned dependency lockfile.
- [lib/main.dart](lib/main.dart): current phone-local Flutter start surface.
- [lib/src/diagnostics](lib/src/diagnostics): no-op-by-default privacy-safe diagnostics helper with allowlisted fields, redaction, omission, and in-memory test sink.
- [lib/src/export](lib/src/export): local meeting export composer and native share gateway abstraction.
- [lib/src/language/language_support.dart](lib/src/language/language_support.dart): typed language support table and realtime/fallback route planner.
- [lib/src/openai](lib/src/openai): OpenAI model/endpoint defaults, realtime WebSocket profile/event helpers, realtime resilience classification/backoff helpers, scoped AI chat Responses client/context helpers, and encrypted local credential status/read/reset helpers.
- [lib/src/theme/live_translate_theme.dart](lib/src/theme/live_translate_theme.dart): shared colors, spacing, radii, text styles, elevation, and app theme.
- [lib/src/session/live_session_controller.dart](lib/src/session/live_session_controller.dart): deterministic phone-local live-session lifecycle, reconnect attempt/backoff, and resource state model.
- [lib/src/session/microphone_permission.dart](lib/src/session/microphone_permission.dart): Flutter microphone permission abstraction backed by the Android MethodChannel implementation.
- [lib/src/session/microphone_capture.dart](lib/src/session/microphone_capture.dart): fakeable PCM16 microphone capture abstraction backed by the Android `AudioRecord` EventChannel implementation.
- [lib/src/session/realtime_translation_coordinator.dart](lib/src/session/realtime_translation_coordinator.dart): credential/permission/capture/realtime coordinator that streams PCM16 chunks directly to OpenAI and tears down resources on unsafe states.
- [lib/src/session/realtime_transcript_committer.dart](lib/src/session/realtime_transcript_committer.dart): coalesces realtime transcript delta/done events into encrypted local meeting transcript rows without duplicating each delta.
- [lib/src/session/translated_audio_playback.dart](lib/src/session/translated_audio_playback.dart): fakeable local translated-audio PCM16 playback gateway seam and Android MethodChannel gateway for decoded realtime audio deltas.
- [lib/src/storage](lib/src/storage): encrypted local storage adapter, meeting/transcript/summary/recipient models, and repository.
- [lib/src/ui/live_translate_models.dart](lib/src/ui/live_translate_models.dart): structured UI state for sessions, transcripts, AI chat scope, export type, and controls.
- [lib/src/ui/live_translate_components.dart](lib/src/ui/live_translate_components.dart): reusable mockup-aligned Flutter components.
- [lib/src/mock/mock_live_translate_data.dart](lib/src/mock/mock_live_translate_data.dart): local-only sample session data for UI and widget tests.
- [test/widget_test.dart](test/widget_test.dart): current Flutter widget smoke test.
- [test/design_system_test.dart](test/design_system_test.dart): design-system unit/widget coverage.
- [test/language_support_test.dart](test/language_support_test.dart): language support table and fallback route coverage.
- [test/openai_realtime_translation_test.dart](test/openai_realtime_translation_test.dart): direct realtime profile config, event parsing, WebSocket header/body, and credential non-leakage coverage.
- [test/microphone_capture_test.dart](test/microphone_capture_test.dart): PCM16 capture config and platform-event parsing coverage.
- [test/realtime_translation_coordinator_test.dart](test/realtime_translation_coordinator_test.dart): capture lifecycle, credential/permission gates, PCM16 event flow, decoded translated-audio queueing, realtime transcript commitment, background teardown, bounded fake reconnect scheduling, reconnect transcript continuity, playback restart/teardown, and reconnect exhaustion coverage.
- [test/translated_audio_playback_test.dart](test/translated_audio_playback_test.dart): MethodChannel translated-audio playback start/enqueue/stop argument coverage and missing-plugin fallback behavior.
- [test/openai_realtime_resilience_test.dart](test/openai_realtime_resilience_test.dart): direct realtime failure classification and bounded backoff policy coverage.
- [test/openai_ai_chat_test.dart](test/openai_ai_chat_test.dart): scoped AI chat context, Responses request body, response parsing, and direct HTTP seam coverage.
- [test/local_meeting_exporter_test.dart](test/local_meeting_exporter_test.dart): local transcript, summary, and both export composition coverage.
- [test/openai_meeting_summary_test.dart](test/openai_meeting_summary_test.dart): direct OpenAI Responses summary request construction, `store: false`, `gpt-5.5` xhigh reasoning intent, response parsing, and credential non-leakage coverage.
- [test/accessibility_responsive_test.dart](test/accessibility_responsive_test.dart): semantic-label and compact large-text coverage.
- [test/privacy_safe_diagnostics_test.dart](test/privacy_safe_diagnostics_test.dart): diagnostics redaction and payload-exclusion coverage.
- [android](android): Android Flutter project, app namespace, native microphone/playback/share channels, debug build config, and local signing placeholder.
- [ios](ios): iOS-compatible Flutter project shell.

## Design System Conventions

Future UI work should use the shared Flutter foundation instead of hard-coded one-off values:

- Use `LiveTranslateTheme.dark()`, `AppColors`, `AppSpacing`, `AppRadii`, `AppElevation`, and `AppTextStyles` for visual decisions.
- Drive session labels and state accents through `LiveSessionViewData`, `LiveSessionMode`, `LiveAccent`, and related model types.
- Keep AI chat scope explicit through `AiChatScope.thisMeeting` or `AiChatScope.allMeetings`.
- Build mockup-derived surfaces from `live_translate_components.dart` components such as `LiveTranslateShell`, `SessionStatusCard`, `LanguageSelectorCard`, `FeatureChip`, `TranscriptCard`, `TranscriptList`, `QueueBanner`, `JumpToLiveChip`, `BottomControlBar`, `PromptActionChip`, and `ExportTypeSelector`.
- Transcript lists that sit behind fixed bottom controls should reserve at least `AppSpacing.bottomControlsHeight` plus safe-area padding.
- Keep sample transcript/session content local to `MockLiveTranslateData` until realtime and direct OpenAI integration replace it with product data.

## Local Setup

Use the local Flutter SDK installed for this workspace:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter pub get
flutter analyze
flutter test
bash scripts/check-docs.sh
bash scripts/check-supply-chain.sh
```

For Android debug build and smoke checks:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter build apk --debug
scripts/build_debug_apk_artifact.sh
scripts/android_emulator_e2e.sh --apk /tmp/<debug-apk-name>.apk --verify-credential-reset
android-pixel9-headless
flutter devices
flutter run -d <android-emulator-id>
scripts/android_emulator_e2e.sh --with-live-credential
flutter build apk --debug --dart-define=LIVE_TRANSLATE_DEBUG_E2E=true
scripts/build_debug_apk_artifact.sh --debug-live-events
scripts/android_emulator_e2e.sh --with-live-credential --debug-live-events
scripts/build_debug_apk_artifact.sh --release
```

Do not add real credentials to `.env.example` or any committed file. Use uncommitted local env files only for local development placeholders. Mobile credential/session material must not be bundled into the app. #23 accepted a phone-local user-provided credential/session flow; the app now saves/removes that material only through encrypted local device storage. Starting a live meeting without a saved credential shows `OpenAI setup required` before microphone permission or live resources open.

For local Android release-signing experiments, copy [android/key.properties.example](android/key.properties.example) to `android/key.properties` and use local placeholder values only. `android/key.properties` is ignored and must not be committed. Without that local file, release artifacts intentionally use the existing debug-signing fallback and are named `release-debug-signed` so they are not confused with store-ready builds.

## GitHub Issue Map

Closed planning and implementation intake:

- #1 Finalize product spec and mockup intake
- #2 Scaffold Flutter mobile app
- #3 Implement Flutter UI from supplied mockups for phone-only MVP
- #7 Implement language support and fallback routing
- #8 Add scoped AI chat over local meetings
- #9 Implement local encrypted meeting storage
- #10 Maintain cybersecurity threat model and report
- #11 Document Android emulator workflow for Codex
- #12 Create phone-only MVP test strategy
- #13 Implement microphone permissions and live session lifecycle
- #15 Implement privacy-safe local logging and diagnostics controls
- #16 Add CI quality gates for docs, Flutter, and secret safety
- #17 Add accessibility and responsive text verification
- #18 Define Flutter design tokens and reusable mockup components
- #20 Implement local meeting management
- #21 Add email export for transcripts and summaries
- #22 Implement dependency and supply-chain cybersecurity controls
- #23 Decide safe direct OpenAI mobile credential approach

Open MVP/planning work:

- #6 Integrate direct OpenAI Realtime Translation
- #14 Harden direct OpenAI realtime resilience
- #19 Maintain README and agent handoff docs during implementation

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
- User-provided OpenAI credential/session material may be stored only in encrypted local device storage and must have a clear reset/removal path.
- Preserve the phone-only MVP architecture: no app backend, AWS, Lambda, token broker, cloud sync, server mailer, or server-side transcript handling.
- Direct OpenAI API calls are the only routine network path for product behavior.
- Keep AI chat on a direct OpenAI path scoped explicitly to `This meeting` or `All meetings`.
- Store meeting history, transcripts, summaries, recipient preferences, and sensitive local data only in encrypted device storage for the MVP.
- Use device-native mail/share composer semantics where practical for export; do not add an outbound mail backend.
- Keep logs, crash reports, analytics, diagnostics, screenshots, and test output free of speech, transcript payloads, prompts, translations, summaries, recipient lists, OpenAI credentials/session material, and API keys.
- Route app diagnostics through `PrivacySafeDiagnostics`; add only allowlisted state/configuration labels and never raw payloads or credential material.
- Verify current OpenAI Realtime model/endpoint behavior, Realtime Translation target language support, and summary model/reasoning support during implementation.
- Treat cybersecurity as a first-class acceptance criterion: dependency hygiene, supply-chain checks, mobile permission minimization, secret scanning, and no transcript leakage are required.

## Verification

Current local gates:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter pub get
flutter analyze
flutter test
bash scripts/check-docs.sh
bash scripts/check-supply-chain.sh
```

Optional live OpenAI smoke, only when a local credential is supplied through the process environment from an uncommitted source:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
OPENAI_API_KEY="<redacted local value>" dart run scripts/live_openai_smoke.dart --all
```

For the #6/#14 realtime increments, `--all` includes no-microphone realtime session creation for both profiles, a synthetic 200 ms non-speech PCM16 append to the dedicated translation profile, a synthetic 200 ms non-speech PCM16 append schema check for the primary `gpt-realtime-2` profile, a local generated-Spanish-speech smoke for the dedicated translation profile when `espeak-ng` is available, and a controlled generated-speech reconnect smoke for the dedicated translation profile. The generated-speech smokes validate transcript and translated-audio event arrival without printing transcript/audio payloads; the reconnect smoke intentionally closes one live socket after generated-speech chunks, opens a second session, and requires recovered transcript/audio evidence. They do not prove physical microphone capture, installed-app live speech persistence, credential-expiry recovery, or audible Android speaker output. The debug installed-app generated-event proof covers coordinator/storage/playback de-duplication inside the installed app, but it is not live OpenAI or microphone evidence. Real microphone translation smoke still needs a reliable emulator/device microphone source and should not insert a live credential into emulator storage unless app data is cleared afterward.

Installed APK emulator E2E, only when the local secret file is available and app data can be cleared afterward:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter build apk --debug
scripts/android_emulator_e2e.sh --with-live-credential
```

The E2E script starts or reuses `Pixel_9_API_36_Play` in the background, installs the debug APK, can validate non-live credential save/remove/reset behavior with `--verify-credential-reset`, drives the OpenAI setup and microphone-permission path when `--with-live-credential` is used, captures proof under `/tmp/realtime-translate-mobile-e2e`, and clears `com.tomdf47.realtime_translate_mobile` data on exit. `--debug-live-events` requires a debug APK built with `--dart-define=LIVE_TRANSLATE_DEBUG_E2E=true`; it drives a debug-only generated-event coordinator/storage/playback proof and does not prove physical microphone injection, live OpenAI streaming, or audible speaker output.

CI gates run on pull requests and pushes to `main`:

- `Docs`: `bash scripts/check-docs.sh`
- `Flutter`: `flutter pub get`, `flutter analyze`, `flutter test`, and `bash scripts/check-supply-chain.sh`

Additional checks for app changes:

- Latest host validation for the realtime recovery UI slice was 2026-05-24 19:54 AWST. `flutter pub get`, `flutter analyze`, `flutter test` (76 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, `git diff --check`, `flutter build apk --debug`, and `scripts/android_emulator_e2e.sh --with-live-credential` passed. Redacted live OpenAI smoke `--all` could not produce valid live results because the local secret returned `insufficient_quota` for Responses and Realtime requests. Key scan counts after live/emulator cleanup were repo `0`, `/tmp` `0`, `/home/tom/.openclaw/logs` `0`, process environments `0`, and `~/.codex/auth.json` `0`. This slice adds no dependencies, Android permissions, backend routes, production debug hooks, OpenAI request-format changes, or credential logging. The current `android-pixel9-headless` workflow still launches with `-no-audio`, so no physical microphone or audible speaker-output claim is made.
- Latest host validation for the unsupported-language recovery UI slice was 2026-05-24 AWST. `flutter analyze`, `flutter test` (77 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, `git diff --check`, `scripts/build_debug_apk_artifact.sh`, and `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-44fe20a-20260524T123408Z.apk` passed. The installed emulator run used no live credential and verified install/launch/missing-credential gate only. This slice adds no dependencies, Android permissions, backend routes, production debug hooks, OpenAI request-format changes, live OpenAI calls, or credential logging.
- Latest host validation for APK handoff hardening was 2026-05-24 AWST. The artifact script supports debug, debug-live-events, and `--release`; release artifacts are named `release-local-signed` when `android/key.properties` is present and `release-debug-signed` otherwise. Validation passed with `bash -n scripts/build_debug_apk_artifact.sh`, `scripts/build_debug_apk_artifact.sh --help`, `flutter analyze`, `flutter test` (77 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, `git diff --check`, `scripts/build_debug_apk_artifact.sh`, `scripts/build_debug_apk_artifact.sh --release`, and a no-live installed emulator smoke using `/tmp/realtime-translate-mobile-release-debug-signed-8732d48-20260524T124418Z.apk`. The release-mode artifact SHA-256 is `d55cf2e5f79bb0b0fa79e0fa217a7df18bf3d81196de680cd809345552f8d005`; it is debug-signed for local handoff only, not store-ready. The validation did not read a live credential, call OpenAI, inject microphone audio, or prove audible speaker output.
- Latest host validation for the credential reset E2E slice was 2026-05-24 20:20 AWST. `bash -n scripts/android_emulator_e2e.sh`, `flutter test test/widget_test.dart`, `flutter analyze`, `flutter test` (76 tests), `bash scripts/check-docs.sh`, `git diff --check`, `bash scripts/check-supply-chain.sh` with the documented Flutter `PATH`, `scripts/build_debug_apk_artifact.sh`, and `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-ac2e265-20260524T121915Z.apk --verify-credential-reset` passed. The emulator run used only a non-secret placeholder credential, verified the saved value was not visible after save, removed it, confirmed the removal action disappeared, and confirmed starting a meeting returned to the setup-required gate. No live credential, OpenAI quota, microphone injection, or speaker-output claim was involved.

- Secret scan or equivalent check for standard OpenAI API key leakage.
- Dependency/advisory checks for pinned Flutter/Dart/native package versions.
- Android emulator smoke check using `android-pixel9-headless`
- UI smoke coverage for supplied mockup-derived surfaces, meeting management, scoped AI chat, and email export
- Privacy routing test showing transcript/audio/prompt/summary/export content does not call an app backend
- Logging/diagnostics test showing sensitive payloads and credentials are absent or redacted
- `flutter test test/privacy_safe_diagnostics_test.dart` for the focused local diagnostics redaction gate

## Documentation Maintenance

Every future change should update this README when setup, architecture, product behavior, issue status, verification steps, or known risks change. Product or architecture decision changes should also update [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).

## Development Notes

Tom's Fedora machine has an Android SDK and boot-tested emulator available:

```bash
android-pixel9-headless
```

Use that instead of `emulator -no-window`, which segfaults on this machine.
