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
- Regression checklist: [docs/regression-testing-checklist.md](docs/regression-testing-checklist.md)
- Decision log: [docs/decision-log.md](docs/decision-log.md)

## Decision Record

- Mobile app: Flutter, Android-first, iOS-compatible later
- MVP backend: none
- Routine network path: phone app connects directly to the OpenAI API only
- Default MVP: text-first two-party live interpreter with automatic language discovery and bidirectional translated text
- Existing live audio interpretation seam: `gpt-realtime-translate` on `/v1/realtime/translations`; `gpt-realtime-2` remains an explicit compatibility/experimental voice-agent profile
- AI chat: scoped explicitly to `This meeting` or `All meetings`
- Data storage: local encrypted device storage only
- Meeting management: local meetings with transcript/history/summary metadata stored on phone
- Generated exports: encrypted in-app Transcript/Summary/Both generation with explicit Copy action; no outbound mail backend
- Deferred scope: AWS, Lambda, token broker, app backend, cloud identity, cloud sync, and server-side transcript handling are V2/future only

## Product Direction

The app should feel premium, clean, and executive-grade. The MVP is phone-only aside from direct OpenAI API calls. The first usable surface should help a user start or resume a two-party live interpreter, not sign into an app backend or configure cloud infrastructure.

## Current Status

Planning repo created. Supplied Android mockups have been received, copied into [assets/mockups](assets/mockups), and captured in [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md). The canonical build-ready spec is [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).

The Flutter scaffold now exists with Android and iOS project structure, app ID `com.tomdf47.realtime_translate_mobile`, Android signing placeholders, a mockup-derived UI shell, Android runtime microphone permission handling, deterministic local session lifecycle control, encrypted local meeting storage, local meeting management, phone-local OpenAI setup with encrypted credential storage/reset, privacy-safe diagnostics, direct OpenAI realtime seams, a fakeable direct OpenAI text interpreter gateway using `store: false`, scoped AI chat, generated exports, and repeatable local validation scripts. Issue #30 changes the default MVP surface to a two-party live interpreter: the start screen shows `Start interpreter`, the live screen starts as `Listening for languages...`, one detected language shows `Heard <language>. Waiting for the other language...`, two distinct detected languages lock as `<A> <-> <B>`, delayed first-turn translation is backfilled once the second language is known, and transcript rows preserve original and translated text separately with pending/detected/delayed/final statuses. Issue #31 adds a privacy-preserving `Pause Listening` / `Resume Listening` control that stops microphone capture, realtime streaming, and translated-audio playback without deleting the active local meeting or transcript state; startup now shows an explicit `Connecting to OpenAI` indicator before recording begins. Realtime transcript commitment now rolls blocks on source item/language changes or a new source after a completed source+translation pair, backfills translation-first rows when original speech arrives, avoids final rows with missing original speech, parses common nested language metadata, and uses a deterministic local English/Italian/Spanish/French fallback for source-language UI labels. The active live UI hides source/target pickers, direction switching, the `Translate Text` toggle, live-header AI chat, live-screen export controls, read-aloud controls, and speaker/headphone chips so it does not claim fully automatic bidirectional spoken audio or crowd the interpreter loop with secondary workflows. The existing realtime, microphone, playback, encrypted storage, AI chat, generated export, and diagnostics seams remain in place, and the repo still contains no backend implementation, cloud identity, cloud sync, server mailer, analytics/crash reporting sink, or server-side transcript handling.

OpenAI Realtime verification for #6 found that `gpt-realtime-2` is documented as the standard voice-agent model on `/v1/realtime`, while `gpt-realtime-translate` is documented as the dedicated streaming speech-to-speech translation model on `/v1/realtime/translations`. Official client-safe Realtime client secrets are still minted by a developer-controlled server using a standard API key, so #23 closed with Tom's MVP decision: proceed phone-to-OpenAI directly with user-provided OpenAI credential/session material stored only in encrypted local device storage, do not commit or bundle any key, and ask Tom for an API key only at the first real OpenAI network smoke/integration test. Live endpoint smoke on 2026-05-24 accepted `gpt-realtime-2` on `/v1/realtime` and `gpt-realtime-translate` on `/v1/realtime/translations`; both returned `session.created` without recording or sending microphone audio. A prior primary append attempt returned sanitized `missing_required_parameter` with `param=session.audio.output.format.rate`; the primary session config now includes `rate: 24000` for output audio, and the redacted live smoke accepts a 200 ms non-speech synthetic PCM16 append after `session.updated`. The dedicated translation endpoint accepts a synthetic 200 ms PCM16 append and now passes a generated spoken-audio smoke that synthesizes a short Spanish phrase locally with `espeak-ng`, converts it in memory to 24 kHz mono PCM16, streams it in 200 ms chunks, and validates that transcript and translated-audio events arrive without printing transcript text, audio bytes, or credential material. The app therefore keeps the primary profile available only for explicit compatibility/experimental checks while microphone streaming and realtime transcript commitment use the dedicated translation profile for the live-interpretation MVP.

Tom's installed-APK report on 2026-05-25 showed assistant-like behavior for the phrase "yellow what's going on" and original speech staying pending. The live app route now defaults normal realtime-capable meetings back to `gpt-realtime-translate` on `/v1/realtime/translations`, matching current official continuous-translation guidance, and keeps `gpt-realtime-2` as an explicit compatibility/experimental voice-agent profile. Realtime input transcription delta/completed/segment events now carry item IDs through the parser so original speech replaces `Original speech pending` on the correct transcript block, while translated output deltas update the separate translation field.

Realtime resilience behavior for #14 is locally scaffolded, and the live endpoint smoke now proves the configured realtime models can create sessions. Credential expiry or rejection moves the session to `credentialInvalid`; unsupported realtime language failures move to `error` with a language-specific recovery banner that does not offer a retry loop; retryable network drops, socket closes, rate limits, transient OpenAI errors, initial realtime connect timeouts, and lifecycle interruption schedule bounded exponential backoff with jitter and enter `reconnecting` with microphone capture, realtime, and playback resources closed during backoff; exhausted network or lifecycle retries move to `offline`; fatal errors move to `error`. Initial realtime connect is bounded by a 12 second app-side timeout so slow startup becomes a visible recovery state instead of leaving the user on an indefinite connecting screen, and startup failures keep the active live surface visible with sanitized recovery labels instead of discarding the meeting shell. Foreground resume after lifecycle pause now schedules the direct realtime reconnect path instead of only changing the UI state. WebSocket upgrade errors and close reasons are classified so OpenAI auth failures such as `401` or `invalid_api_key` fail closed to credential setup instead of retrying as generic network drops. The home screen now listens to asynchronous session-state changes after live start, so `reconnecting`, `offline`, and `error` states show a user-visible recovery banner on the live surface with retry/back controls where appropriate. The session state preserves only sanitized failure categories for user-facing recovery labels, so rate-limit and transient-OpenAI failures can be distinguished without showing raw server error details; `credentialInvalid` continues to show the OpenAI setup-required recovery screen without displaying credential material. Diagnostics record only operation/result labels, sanitized error codes, retry attempt, and backoff milliseconds. Unit tests now prove realtime transcript deltas are upserted into encrypted local meeting storage without duplicate rows for a live segment, duplicate completed transcript events after reconnect do not create extra rows, translated audio deltas are decoded into a fakeable PCM16 playback queue, Android playback MethodChannel calls carry PCM16 bytes to native output without logging or persistence, a fake retryable socket close reconnects without duplicating the active transcript row while restarting playback/capture resources, a generated-speech-style dedicated translation reconnect keeps one committed transcript row while clearing stale playback chunks and queueing recovered audio, credential-rejection realtime events close live resources, stopped/reconnecting/offline/rate-limit/unsupported-language recovery banners render with sanitized labels, credential-expiry decisions keep resources closed, and a failed reconnect marks the partial row interrupted when retries exhaust. The installed E2E driver now also has a non-secret invalid-credential mode that saves a placeholder, grants microphone permission, observes OpenAI's realtime auth rejection, and verifies the setup-required recovery screen. The generated-speech smoke proves the dedicated translation endpoint can emit live transcript and translated-audio events from spoken PCM16 input; the controlled reconnect smoke opens a live dedicated translation session, streams generated speech chunks, intentionally closes that socket, reconnects, and verifies recovered transcript/audio events from the second session. Transcript de-duplication under a real live app-coordinator reconnect, live credential-expiry validation with real credential material, network-drop/rate-limit validation under live streaming, audible translated-audio recovery under live streaming, and a real physical microphone translation smoke still require later #14/#6 work.

Language support verification for #7 on 2026-05-24 used the official OpenAI Realtime Translation guide, `gpt-realtime-translate` model page, and translation client-secret API reference. Those docs confirm the dedicated `/v1/realtime/translations` endpoint and `audio.output.language` target parameter, but they do not expose an authoritative target-language enum. The app therefore uses a conservative realtime target table for English, Spanish, and French while showing all app target languages in the picker; broader targets such as Japanese are labeled as direct-OpenAI fallback targets and keep fallback phone-only with no AWS, backend, cloud sync, or server-side transcript handling.

Keep future work aligned to the GitHub issue acceptance criteria and preserve the phone-only MVP privacy boundary.

## Repository Map

- [AGENTS.md](AGENTS.md): required operating contract for future Codex jobs.
- [CONTRIBUTING.md](CONTRIBUTING.md): contribution and PR expectations.
- [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md): canonical product, architecture, privacy, and implementation spec.
- [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md): visual and interaction source of truth for the first Flutter UI pass.
- [docs/architecture.md](docs/architecture.md): mobile, OpenAI, storage, generated export, and prohibited data-flow boundaries.
- [docs/v2-future-scope.md](docs/v2-future-scope.md): deferred cloud/backend/auth scope.
- [docs/cybersecurity-report.md](docs/cybersecurity-report.md): cybersecurity baseline and dependency-advisory methodology.
- [docs/privacy-safe-diagnostics.md](docs/privacy-safe-diagnostics.md): local diagnostics allowlist, redaction rules, and forbidden payload categories.
- [docs/development-workflow.md](docs/development-workflow.md): issue workflow, doc update matrix, and handoff checklist.
- [docs/environment.md](docs/environment.md): local setup, emulator notes, env placeholders, and secret handling.
- [docs/testing-strategy.md](docs/testing-strategy.md): docs, Flutter, privacy, cybersecurity, and emulator verification plan.
- [docs/regression-testing-checklist.md](docs/regression-testing-checklist.md): concrete pre-release checklist for main screen controls, language selection, toggles, realtime smoke, transcript chunking, timer behavior, generated exports, and APK release sanity.
- [docs/decision-log.md](docs/decision-log.md): durable decisions future agents should preserve.
- [docs/codex-starter-prompt.md](docs/codex-starter-prompt.md): starter prompt for the first Flutter implementation pass.
- [.env.example](.env.example): placeholder-only environment contract.
- [.github/workflows/docs.yml](.github/workflows/docs.yml): CI docs link and secret-pattern gate.
- [.github/workflows/flutter.yml](.github/workflows/flutter.yml): CI Flutter analysis, tests, and supply-chain gate.
- [scripts/check-docs.sh](scripts/check-docs.sh): docs link and secret-pattern sanity check.
- [scripts/check-supply-chain.sh](scripts/check-supply-chain.sh): local dependency advisory, secret-pattern, and Android permission gate.
- [scripts/build_debug_apk_artifact.sh](scripts/build_debug_apk_artifact.sh): repeatable Android APK builder/copier for debug, debug E2E, and local release artifacts; writes a clearly named APK plus SHA-256 sidecar under `/tmp` without reading OpenAI credentials and labels debug-signed release artifacts as not store-ready.
- [scripts/check_android_release_signing.sh](scripts/check_android_release_signing.sh): store-ready Android release-signing preflight; validates local uncommitted signing config and, when supplied an APK, verifies it is not Android debug-signed without printing signing material.
- [scripts/android_pixel9_host_audio.sh](scripts/android_pixel9_host_audio.sh): repo-local Pixel 9 emulator launcher for #6/#14 audio validation attempts; starts `Pixel_9_API_36_Play` with `-allow-host-audio` and without `-no-audio`.
- [scripts/final_qa_gate.sh](scripts/final_qa_gate.sh): one-command non-live final QA gate for Flutter analysis/tests, docs/security checks, shell syntax checks, diff whitespace checks, and fresh debug/release APK handoff artifacts; optional `--emulator-smoke` verifies the no-credential installed-app gate without reading the local OpenAI secret.
- [scripts/live_openai_smoke.dart](scripts/live_openai_smoke.dart): redacted live OpenAI smoke harness for Responses summary/AI chat, realtime endpoint availability, synthetic PCM16 append checks, local generated-speech realtime translation validation, and controlled generated-speech reconnect validation.
- [scripts/android_emulator_e2e.sh](scripts/android_emulator_e2e.sh): installed-APK Android emulator E2E driver for the start/setup/permission/live-surface/AI-chat path, non-live credential reset and invalid-credential recovery validation, plus an opt-in debug-only generated-event persistence proof when the APK is built with `LIVE_TRANSLATE_DEBUG_E2E=true`; artifacts are written under `/tmp` and app data is cleared afterward.
- [pubspec.yaml](pubspec.yaml) and [pubspec.lock](pubspec.lock): Flutter package manifest and pinned dependency lockfile.
- [lib/main.dart](lib/main.dart): current phone-local Flutter start surface.
- [lib/src/diagnostics](lib/src/diagnostics): no-op-by-default privacy-safe diagnostics helper with allowlisted fields, redaction, omission, and in-memory test sink.
- [lib/src/export](lib/src/export): local meeting export composer and native share gateway abstraction retained for later explicit share handoff.
- [lib/src/language/language_support.dart](lib/src/language/language_support.dart): typed language support table and realtime/fallback route planner.
- [lib/src/openai](lib/src/openai): OpenAI model/endpoint defaults, realtime WebSocket profile/event helpers, direct text interpreter Responses gateway, realtime resilience classification/backoff helpers, scoped AI chat Responses client/context helpers, and encrypted local credential status/read/reset helpers.
- [lib/src/theme/live_translate_theme.dart](lib/src/theme/live_translate_theme.dart): shared colors, spacing, radii, text styles, elevation, and app theme.
- [lib/src/session/live_session_controller.dart](lib/src/session/live_session_controller.dart): deterministic phone-local live-session lifecycle, reconnect attempt/backoff, and resource state model.
- [lib/src/session/microphone_permission.dart](lib/src/session/microphone_permission.dart): Flutter microphone permission abstraction backed by the Android MethodChannel implementation.
- [lib/src/session/microphone_capture.dart](lib/src/session/microphone_capture.dart): fakeable PCM16 microphone capture abstraction backed by the Android `AudioRecord` EventChannel implementation.
- [lib/src/session/live_text_interpreter.dart](lib/src/session/live_text_interpreter.dart): text-first two-party interpreter state machine that discovers languages, locks pairs, and stores encrypted transcript rows through a fakeable direct OpenAI gateway.
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
scripts/final_qa_gate.sh
```

For Android debug build and smoke checks:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter build apk --debug
scripts/build_debug_apk_artifact.sh
scripts/android_emulator_e2e.sh --apk /tmp/<debug-apk-name>.apk --verify-credential-reset
scripts/android_emulator_e2e.sh --apk /tmp/<debug-apk-name>.apk --verify-invalid-credential-recovery
android-pixel9-headless
flutter devices
flutter run -d <android-emulator-id>
scripts/android_emulator_e2e.sh --with-live-credential
flutter build apk --debug --dart-define=LIVE_TRANSLATE_DEBUG_E2E=true
scripts/build_debug_apk_artifact.sh --debug-live-events
scripts/android_emulator_e2e.sh --with-live-credential --debug-live-events
scripts/build_debug_apk_artifact.sh --release
scripts/final_qa_gate.sh --emulator-smoke
scripts/final_qa_gate.sh --require-store-signing
```

Do not add real credentials to `.env.example` or any committed file. Use uncommitted local env files only for local development placeholders. Mobile credential/session material must not be bundled into the app. #23 accepted a phone-local user-provided credential/session flow; the app now saves/removes that material only through encrypted local device storage. Starting a live meeting without a saved credential shows `OpenAI setup required` before microphone permission or live resources open.

For local Android release-signing experiments, copy [android/key.properties.example](android/key.properties.example) to `android/key.properties` and use local values only. Prefer a `storeFile` path outside the repo. `android/key.properties` is ignored and must not be committed. Without that local file, release artifacts intentionally use the existing debug-signing fallback and are named `release-debug-signed` so they are not confused with store-ready builds. Store-ready checks must use `scripts/check_android_release_signing.sh` or `scripts/final_qa_gate.sh --require-store-signing`.

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
- #29 Normalize auto-detect source labels in live UI and meeting history

Open MVP/planning work:

- #6 Integrate direct OpenAI Realtime Translation
- #14 Harden direct OpenAI realtime resilience
- #19 Maintain README and agent handoff docs during implementation
- #24 Track store-ready Android release signing
- #27 Restore dedicated live translation behavior and transcript streaming
- #30 Redesign MVP into a two-party live interpreter (implemented locally in this working tree; issue state not updated because GitHub was unreachable from the sandbox)
- #31 Fix live interpreter block splitting and startup controls (implemented locally in this working tree; issue state update depends on GitHub reachability)

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
- Store meeting history, transcripts, summaries, generated exports, recipient preferences, and sensitive local data only in encrypted device storage for the MVP.
- Keep the primary export flow in app: generate in the background, browse encrypted generated exports, and copy only after an explicit user action. Do not add an outbound mail backend.
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
scripts/final_qa_gate.sh
```

Optional live OpenAI smoke, only when a local credential is supplied through the process environment from an uncommitted source:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
OPENAI_API_KEY="<redacted local value>" dart run scripts/live_openai_smoke.dart --all
```

For the #6/#14 realtime increments, `--all` includes no-microphone realtime session creation for both profiles, a synthetic 200 ms non-speech PCM16 append to the dedicated translation profile, a synthetic 200 ms non-speech PCM16 append schema check for the primary `gpt-realtime-2` profile, a local generated-Spanish-speech smoke for the dedicated translation profile when `espeak-ng` is available, and a controlled generated-speech reconnect smoke for the dedicated translation profile. The generated-speech smokes validate transcript and translated-audio event arrival without printing transcript/audio payloads; the reconnect smoke intentionally closes one live socket after generated-speech chunks, opens a second session, and requires recovered transcript/audio evidence. They do not prove physical microphone capture, installed-app live speech persistence, credential-expiry recovery, or audible Android speaker output. The debug installed-app generated-event proof covers coordinator/storage/playback de-duplication inside the installed app, encrypted history persistence after app restart, and `This meeting` local AI context visibility for the persisted row, but it is not live OpenAI or microphone evidence. Real microphone translation smoke still needs a reliable emulator/device microphone source and should not insert a live credential into emulator storage unless app data is cleared afterward.

For a non-live pre-handoff gate that also creates fresh debug and release APK artifacts, run `scripts/final_qa_gate.sh`. Add `--emulator-smoke` to install the fresh release artifact and verify the setup-required no-credential gate without reading the local OpenAI secret file. Release artifacts remain clearly labeled `release-local-signed` or `release-debug-signed`; debug-signed release artifacts are local QA/handoff artifacts only, not store-ready submissions. Add `--require-store-signing` when the goal is a store-ready build; that mode fails before release artifact creation if local signing config is absent or incomplete, and fails after build if the release APK is debug-signed.

For a store-ready signing preflight, create only local uncommitted signing files, then run:

```bash
scripts/check_android_release_signing.sh
scripts/final_qa_gate.sh --require-store-signing
```

`scripts/check_android_release_signing.sh` fails if `android/key.properties` is absent, required fields are missing or still placeholders, the referenced keystore does not exist, the keystore is tracked by git, or a checked APK is signed with the Android debug certificate. The script reports pass/fail status only and does not print signing passwords, aliases, or keystore material.

Installed APK emulator E2E, only when the local secret file is available and app data can be cleared afterward:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter build apk --debug
scripts/android_pixel9_host_audio.sh
scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only
scripts/android_emulator_e2e.sh --with-live-credential
scripts/android_emulator_e2e.sh --require-device-audio --with-live-credential
```

The E2E script starts or reuses `Pixel_9_API_36_Play` in the background, installs the debug APK, can validate non-live credential save/remove/reset behavior with `--verify-credential-reset`, can validate non-secret invalid-placeholder auth recovery with `--verify-invalid-credential-recovery`, drives the OpenAI setup and microphone-permission path when `--with-live-credential` is used, captures proof under `/tmp/realtime-translate-mobile-e2e`, and clears `com.tomdf47.realtime_translate_mobile` data on exit. Add `--require-device-audio` before any run that intends to claim physical microphone or audible speaker behavior; physical devices are accepted, while emulators must be launched with `-allow-host-audio` and must not include `-no-audio`. If no device is connected and `--require-device-audio` is set, the E2E script uses [scripts/android_pixel9_host_audio.sh](scripts/android_pixel9_host_audio.sh) to start the repo-local host-audio emulator launcher. The preflight writes `audio-preflight.txt` under the artifact directory. `--audio-preflight-only` runs only that check without installing the APK, reading the local OpenAI secret, launching the app, or clearing app data. This preflight proves only that the selected target is not the known no-audio emulator path; physical microphone translation and audible speaker behavior still require a live validation run. `--debug-live-events` requires a debug APK built with `--dart-define=LIVE_TRANSLATE_DEBUG_E2E=true`; it drives a debug-only generated-event coordinator/storage/playback proof, restarts the app, verifies the persisted transcript count in meeting history, reopens the meeting, and verifies `This meeting` AI context sees the local transcript count. It does not prove physical microphone injection, live OpenAI streaming, or audible speaker output.

CI gates run on pull requests and pushes to `main`:

- `Docs`: `bash scripts/check-docs.sh`
- `Flutter`: `flutter pub get`, `flutter analyze`, `flutter test`, and `bash scripts/check-supply-chain.sh`

Additional checks for app changes:

- Latest focused validation for the #6/#14 startup and resilience hardening slice was 2026-05-25 AWST. `flutter analyze` passed using a writable Flutter SDK shim under `/tmp/flutter-lite` because the canonical SDK cache is read-only in this sandbox; `/home/tom/.local/share/flutter/bin/cache/dart-sdk/bin/dart analyze lib test`, `bash scripts/check-docs.sh`, and `git diff --check` passed. `flutter test test/realtime_translation_coordinator_test.dart test/widget_test.dart` could not run because the sandbox rejects Flutter test runner localhost server sockets with `Failed to create server socket (OS Error: Operation not permitted, errno = 1), address = 127.0.0.1, port = 0`. `bash scripts/check-supply-chain.sh` could not complete because Gradle cannot open a writable lock under `/home/tom/.gradle` in the sandbox; a writable `GRADLE_USER_HOME` with the existing Gradle distribution symlinked then failed because Gradle's file-lock service could not determine a usable wildcard IP. `flutter build apk --debug` could not complete for the same Gradle lock/IP restrictions, so no APK artifact was produced in this sandbox. This slice adds no dependencies, Android permissions, backend routes, live OpenAI calls, live credential reads, microphone recording, physical voice/frontend E2E, or audible speaker-output claim.
- Latest host validation for the host-audio emulator target was 2026-05-24 22:19 AWST. `bash -n scripts/android_emulator_e2e.sh`, `bash -n scripts/android_pixel9_host_audio.sh`, `bash scripts/check-docs.sh`, `git diff --check`, and `PATH=/home/tom/.local/share/flutter/bin:$PATH bash scripts/check-supply-chain.sh` passed. `ARTIFACT_DIR=/tmp/realtime-translate-mobile-e2e-host-audio-preflight-2 scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only` passed after starting `Pixel_9_API_36_Play` with the repo-local host-audio launcher; proof at `/tmp/realtime-translate-mobile-e2e-host-audio-preflight-2/audio-preflight.txt` records `-allow-host-audio` and no `-no-audio`. No APK was installed, no live OpenAI secret was read, the app was not launched, app data was not cleared, no OpenAI request was made, and no physical microphone/speaker behavior is claimed yet.
- Latest host validation for the device-audio preflight slice was 2026-05-24 22:14 AWST. `bash -n scripts/android_emulator_e2e.sh` passed. `scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only` failed as expected with the current `android-pixel9-headless` launcher because `Pixel_9_API_36_Play` was started with `-no-audio`; proof was written to `/tmp/realtime-translate-mobile-e2e-audio-preflight-precommit/audio-preflight.txt`, no APK was installed, no live OpenAI secret was read, the app was not launched, and app data was not cleared. `scripts/final_qa_gate.sh` passed with `flutter pub get`, `flutter analyze`, `flutter test` (82 tests), docs check, supply-chain check, shell syntax checks, `git diff --check`, and fresh APK builds. Debug APK: `/tmp/realtime-translate-mobile-debug-e154ed3-20260524T141445Z.apk`. Release APK: `/tmp/realtime-translate-mobile-release-debug-signed-e154ed3-20260524T141448Z.apk`; it remains debug-signed and not store-ready. This slice adds no dependencies, Android permissions, backend routes, OpenAI request changes, live credential handling, audio recording, or microphone/speaker validation claim.
- Latest host validation for the realtime recovery UI slice was 2026-05-24 19:54 AWST. `flutter pub get`, `flutter analyze`, `flutter test` (76 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, `git diff --check`, `flutter build apk --debug`, and `scripts/android_emulator_e2e.sh --with-live-credential` passed. Redacted live OpenAI smoke `--all` could not produce valid live results because the local secret returned `insufficient_quota` for Responses and Realtime requests. Key scan counts after live/emulator cleanup were repo `0`, `/tmp` `0`, `/home/tom/.openclaw/logs` `0`, process environments `0`, and `~/.codex/auth.json` `0`. This slice adds no dependencies, Android permissions, backend routes, production debug hooks, OpenAI request-format changes, or credential logging. The current `android-pixel9-headless` workflow still launches with `-no-audio`, so no physical microphone or audible speaker-output claim is made.
- Latest host validation for the unsupported-language recovery UI slice was 2026-05-24 AWST. `flutter analyze`, `flutter test` (77 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, `git diff --check`, `scripts/build_debug_apk_artifact.sh`, and `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-44fe20a-20260524T123408Z.apk` passed. The installed emulator run used no live credential and verified install/launch/missing-credential gate only. This slice adds no dependencies, Android permissions, backend routes, production debug hooks, OpenAI request-format changes, live OpenAI calls, or credential logging.
- Latest host validation for APK handoff hardening was 2026-05-24 AWST. The artifact script supports debug, debug-live-events, and `--release`; release artifacts are named `release-local-signed` when `android/key.properties` is present and `release-debug-signed` otherwise. Validation passed with `bash -n scripts/build_debug_apk_artifact.sh`, `scripts/build_debug_apk_artifact.sh --help`, `flutter analyze`, `flutter test` (77 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, `git diff --check`, `scripts/build_debug_apk_artifact.sh`, `scripts/build_debug_apk_artifact.sh --release`, and a no-live installed emulator smoke using `/tmp/realtime-translate-mobile-release-debug-signed-8732d48-20260524T124418Z.apk`. The release-mode artifact SHA-256 is `d55cf2e5f79bb0b0fa79e0fa217a7df18bf3d81196de680cd809345552f8d005`; it is debug-signed for local handoff only, not store-ready. The validation did not read a live credential, call OpenAI, inject microphone audio, or prove audible speaker output.
- Latest host validation for the credential reset E2E slice was 2026-05-24 20:20 AWST. `bash -n scripts/android_emulator_e2e.sh`, `flutter test test/widget_test.dart`, `flutter analyze`, `flutter test` (76 tests), `bash scripts/check-docs.sh`, `git diff --check`, `bash scripts/check-supply-chain.sh` with the documented Flutter `PATH`, `scripts/build_debug_apk_artifact.sh`, and `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-ac2e265-20260524T121915Z.apk --verify-credential-reset` passed. The emulator run used only a non-secret placeholder credential, verified the saved value was not visible after save, removed it, confirmed the removal action disappeared, and confirmed starting a meeting returned to the setup-required gate. No live credential, OpenAI quota, microphone injection, or speaker-output claim was involved.
- Latest focused validation for the direct realtime recovery-label slice was 2026-05-24 20:52 AWST. `flutter test test/live_session_controller_test.dart test/widget_test.dart test/realtime_translation_coordinator_test.dart` passed. This local slice stores only sanitized realtime failure categories in session state, renders rate-limit recovery without raw OpenAI error details, and proves credential-expiry/rejection decisions close capture/realtime/playback resources. No live OpenAI request, live credential read, microphone injection, or audible speaker-output claim was made.
- Latest host validation for the installed invalid-credential recovery slice was 2026-05-24 21:17 AWST. `bash -n scripts/android_emulator_e2e.sh`, `flutter test test/openai_realtime_translation_test.dart test/openai_realtime_resilience_test.dart test/realtime_translation_coordinator_test.dart`, `flutter analyze`, `flutter test` (83 tests), `scripts/build_debug_apk_artifact.sh`, and `scripts/android_emulator_e2e.sh --apk /tmp/realtime-translate-mobile-debug-61b9239-20260524T131539Z.apk --verify-invalid-credential-recovery` passed. The emulator run used only a non-secret invalid placeholder credential, pre-granted microphone permission for the negative auth path, observed the realtime auth rejection, verified the setup-required recovery screen, wrote proof under `/tmp/realtime-translate-mobile-e2e-invalid-credential-precommit`, and cleared app data afterward. No live app key, physical microphone injection, or audible speaker-output claim was involved.
- Latest non-live final QA gate validation was 2026-05-24 21:49 AWST. `scripts/final_qa_gate.sh --emulator-smoke` passed with `flutter pub get`, `flutter analyze`, `flutter test` (82 tests), `bash scripts/check-docs.sh`, `bash scripts/check-supply-chain.sh`, shell syntax checks, `git diff --check`, fresh debug and release APK artifact builds, and a no-live installed-app smoke against `/tmp/realtime-translate-mobile-release-debug-signed-bdd6dcb-20260524T134822Z.apk`. The debug APK SHA-256 was `fe446ad7670619dae3b401d850af4b36b9cce4205428b8c52f73479092030706`; the release APK SHA-256 was `9f51c22befa8f96091108aff2def2e64d898e1b18d1909cae8f6e804ed40e07d`. The release artifact used the debug-signing fallback because local `android/key.properties` was absent, so it is not store-ready. The emulator proof was written under `/tmp/realtime-translate-mobile-e2e-final-qa`, did not read the local OpenAI secret, did not call live OpenAI, and made no microphone-injection or audible-speaker claim.
- Latest store-ready signing preflight validation was 2026-05-24 21:59 AWST. `bash -n scripts/check_android_release_signing.sh`, `scripts/check_android_release_signing.sh`, and `scripts/final_qa_gate.sh --require-store-signing` passed the expected absent-material behavior: store-ready mode failed clearly because `android/key.properties` is missing. Normal `scripts/final_qa_gate.sh` still passed with `flutter pub get`, `flutter analyze`, `flutter test` (82 tests), docs check, supply-chain check, shell syntax checks, `git diff --check`, and fresh APK builds. Debug APK: `/tmp/realtime-translate-mobile-debug-b5e0d2a-20260524T135914Z.apk`, SHA-256 `fe446ad7670619dae3b401d850af4b36b9cce4205428b8c52f73479092030706`. Release APK: `/tmp/realtime-translate-mobile-release-debug-signed-b5e0d2a-20260524T135921Z.apk`, SHA-256 `9f51c22befa8f96091108aff2def2e64d898e1b18d1909cae8f6e804ed40e07d`; it remains debug-signed and not store-ready.

- Secret scan or equivalent check for standard OpenAI API key leakage.
- Dependency/advisory checks for pinned Flutter/Dart/native package versions.
- Android emulator smoke check using `android-pixel9-headless`
- UI smoke coverage for supplied mockup-derived surfaces, meeting management, scoped AI chat, and generated exports
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
