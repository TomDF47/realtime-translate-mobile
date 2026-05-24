# Architecture

This document summarizes the implementation boundaries from the canonical [live translate build spec](live-translate-build-spec.md). The build spec remains authoritative when details conflict.

## System Shape

```text
Flutter phone app
  -> OpenAI API directly
       preferred model: gpt-realtime-2
       dedicated translation fallback/profile: gpt-realtime-translate
       sends microphone audio
       receives translated audio and transcript deltas
       target language must pass the local realtime language table

Flutter phone app
  -> OpenAI API directly for AI chat and summaries
       scope: This meeting or All meetings
       product intent for export summaries: GPT-5.5 with xhigh reasoning

Flutter phone app
  -> encrypted local device storage
       meetings, transcript/history, summary metadata, preferences,
       recent languages, remembered export recipients, last selected recipients,
       and any credential/session material

Flutter phone app
  -> device-native mail/share composer when user initiates export
       no app-operated outbound mail backend
       Transcript/Summary/Both exports use Android ACTION_SEND share handoff
       Summary/Both first generate or reuse a locally encrypted summary
```

There is no MVP AWS, Lambda, token broker, app backend, cloud sync, cloud identity gate, or server-side transcript handling. The accepted MVP credential approach is user-provided OpenAI credential/session material stored only in encrypted local device storage. Deferred cloud/backend/auth ideas live in [docs/v2-future-scope.md](v2-future-scope.md).

## Hard Boundaries

- Mobile source, committed config, assets, tests, screenshots, and build outputs never contain a standard OpenAI API key.
- The MVP has no app backend.
- Direct OpenAI API calls are the only routine network path for product behavior.
- Transcript text, translated text, prompts, microphone audio, audio chunks, audio-derived payloads, summaries, recipient lists, meeting metadata, and export payloads must not be sent to app-owned backend infrastructure.
- The app must not operate an outbound mail backend for MVP export.
- Meeting and transcript storage is local-only and encrypted for the MVP.
- Diagnostics, analytics, crash reports, screenshots, test output, and logs must exclude secrets and speech/transcript/summary/export payloads.

## Mobile App Responsibilities

- Flutter app with Android-first UX and iOS-compatible structure.
- Phone-local setup/start flow rather than cloud sign-in gate.
- Runtime microphone permissions and explicit session state transitions.
- Direct OpenAI realtime session connection, credential-invalid handling, reconnect, teardown, and error handling.
- Local encrypted storage for preferences, recent languages, meetings, transcript/history, summary metadata, recipient preferences, and any credential/session material.
- Privacy-safe local diagnostics through a no-op-by-default allowlist/redaction helper.
- Meeting management for starting a new meeting, selecting an old meeting, and continuing from it.
- UI surfaces from [docs/mockup-ux-spec.md](mockup-ux-spec.md) and [assets/mockups](../assets/mockups), adapted for the phone-only MVP.
- Scoped AI chat UI and direct OpenAI request path for `This meeting` and `All meetings`.
- Email export UI with Transcript/Summary/Both selector, recipient checklist, local transcript/summary composition, direct OpenAI summary generation, encrypted local summary persistence, and native share handoff.

## OpenAI Responsibilities

- Realtime voice/translation through `gpt-realtime-2` unless endpoint/API testing finds a major blocker.
- Dedicated translation fallback/profile through `gpt-realtime-translate`.
- Stream translated audio and transcript deltas while the speaker is still talking.
- Support AI chat over local meeting context sent directly from the phone app.
- Support summary generation for email export if current model and reasoning parameters allow it.
- Endpoint/model behavior, realtime translation target languages, and reasoning-parameter support must be verified during implementation rather than hard-coded from stale assumptions.

## Email Export Boundary

Email export is user initiated.

- The app prepares the selected Transcript, Summary, or Both locally.
- If Summary or Both is selected, the app calls OpenAI directly from the phone to generate or refresh a local `gpt-5.5` summary with `reasoning.effort: xhigh` and `store: false`.
- The app presents recipients as a local checklist and remembers the recipient list and last selected recipients locally.
- Transcript, Summary, and Both exports are handed to the Android native share sheet through an app-owned MethodChannel and `ACTION_SEND` intent.
- Generated summaries are stored only in encrypted local storage with model intent, transcript count, timestamp, and summary text; the app must not fabricate summaries.
- The app must not add a server mailer, backend relay, or cloud export queue in the MVP.

## Current Repo Layout

The first Flutter scaffold keeps boundaries visible:

```text
android/                     Android Flutter project, app namespace, native microphone/playback/share channels
ios/                         iOS-compatible Flutter project shell
lib/                         Flutter app code
lib/src/diagnostics/         Privacy-safe diagnostics allowlist and redaction helper
lib/src/export/              Local export composer and native share gateway
lib/src/openai/              OpenAI model defaults, realtime/AI chat gateways, and encrypted credential helpers
lib/src/session/             Phone-local permission, PCM16 capture, translated-audio playback queue, realtime coordination, transcript commitment, and lifecycle state
lib/src/storage/             Encrypted local store, meeting repository, and storage models
lib/src/theme/               Shared design tokens and app theme
lib/src/ui/                  Structured UI state models and reusable components
lib/src/mock/                Local mock session data for UI development
test/                        Flutter tests
pubspec.yaml                 Flutter package manifest
pubspec.lock                 Pinned Dart package versions
docs/                        Product, architecture, setup, testing, decisions
assets/mockups/              Supplied Android mockups
```

The current app shell renders the phone-local welcome/start surface, OpenAI setup-required state, encrypted OpenAI setup sheet, Android microphone permission gate, mockup-derived live translation surfaces, scoped AI chat sheet, encrypted local meeting history sheet, and local email export sheet. The lifecycle controller models permission, credential-invalid, listening, read-aloud-paused, reconnecting, offline, error, stop, app background/foreground, audio-route, realtime retry attempt, reconnect-backoff state transitions, the last realtime recovery action, and the sanitized realtime failure category. The home surface listens to controller changes after live start so asynchronous realtime failures can update the visible UI; `reconnecting`, `offline`, and `error` render a local recovery banner with retry/back controls and sanitized notice text, unsupported-language errors are labeled as language-selection failures without a retry button, rate-limit and transient-OpenAI failures get category-specific labels without raw server error details, and credential-invalid recovery still uses the setup-required screen. The storage layer persists meetings, transcript/history entries, summary text/metadata, recent language routes, recipient preferences, sensitive preferences, and credential/session material through `flutter_secure_storage`, with Android backup disabled for app data. Privacy-safe diagnostics are no-op by default and can record only allowlisted state/configuration fields after redaction/omission. Meeting management can start a new local meeting after a credential is configured, select a stored meeting, reopen it as the active encrypted local context, append continuation transcript history, and delete stored meeting metadata. Realtime scaffolding can construct a direct OpenAI WebSocket session for the primary `gpt-realtime-2` profile or dedicated `gpt-realtime-translate` fallback/profile, send PCM16 append events, parse translated audio plus transcript delta/completion events, keep credential material in the Authorization header only, classify direct realtime failure categories, classify WebSocket upgrade status codes and close reasons, and schedule bounded jittered reconnect attempts. Android microphone capture now uses app-owned `AudioRecord` platform code behind a fakeable Flutter capture gateway to emit 24 kHz mono PCM16 chunks, and the realtime coordinator starts capture only after encrypted credential and microphone-permission gates pass. Translated audio deltas are base64-decoded into a fakeable local PCM16 playback gateway; production Android playback now uses an app-owned MethodChannel and `AudioTrack` stream-mode output with a bounded transient queue, while the no-op gateway remains available for tests and non-Android shells. Realtime transcript deltas are coalesced by a dedicated committer and upserted into the active encrypted local meeting row, with completion/interruption status stored but no transcript content logged. Fake-gateway tests prove a retryable realtime close keeps capture/realtime/playback closed during backoff, reconnects through the same direct profile, restarts capture/playback, preserves the active transcript row across retry, clears stale playback chunks, queues recovered translated audio, keeps a generated-speech-style dedicated translation transcript to one committed row, closes resources on credential rejection, keeps credential-expiry and rate-limit recovery notices sanitized, and marks a partial row interrupted when reconnect attempts exhaust. The installed app now has an opt-in debug-only generated-event persistence proof, compiled into the UI only for debug builds with `LIVE_TRANSLATE_DEBUG_E2E=true`, that feeds synthetic realtime event shapes through the coordinator, simulates playback teardown/restart, verifies one new realtime row, restarts the app, verifies the encrypted meeting-history transcript count, reopens the meeting, verifies `This meeting` AI context sees the persisted transcript count, and reports only sanitized counts/status text. The installed E2E script also has a non-secret invalid-credential recovery mode that stores a placeholder through the app UI, grants microphone permission for that negative path, observes OpenAI's realtime auth rejection, verifies the setup-required recovery screen, and clears app data afterward. It now has a `--require-device-audio` preflight that must be used before physical microphone or audible speaker validation claims; on emulators, that preflight fails if the process was launched with `-no-audio`, and `--audio-preflight-only` performs only the preflight without installing the APK, reading a live credential, launching the app, or clearing app data. Live endpoint smoke on 2026-05-24 accepted both realtime profiles and returned `session.created` without microphone audio. Dedicated translation smoke accepted a synthetic 200 ms PCM16 append without microphone input. A generated-spoken-audio smoke now uses local `espeak-ng` Spanish speech converted in memory to 24 kHz mono PCM16 and validates transcript plus translated-audio events from the dedicated translation endpoint without printing payloads. A controlled generated-spoken-audio reconnect smoke now intentionally closes one live dedicated translation socket after generated-speech chunks, opens a second live session, and validates recovered transcript plus translated-audio events without printing payloads. Primary Realtime 2 smoke now also accepts a 200 ms non-speech PCM16 append after the session output audio format includes an explicit 24 kHz rate; that is an append-schema check, not a spoken-translation claim. Official OpenAI docs now explicitly describe `/v1/realtime/translations` with `gpt-realtime-translate` as the live translation endpoint and `/v1/realtime` with `gpt-realtime-2` as the standard voice-agent endpoint, so app microphone streaming currently uses the dedicated translation profile while primary Realtime 2 spoken-translation behavior remains follow-up work. Retryable realtime decisions close capture/realtime/playback resources while the UI is `reconnecting`; credential failures fail closed to `credentialInvalid`; exhausted network/lifecycle retries fail closed to `offline`; unsupported-language and fatal failures fail closed to `error`; backgrounding and stop paths close capture, playback, and realtime resources. AI chat builds scoped local transcript context for `This meeting` or `All meetings`, sends a direct phone-to-OpenAI Responses request through a fakeable gateway when a credential is available, sets `store: false`, and avoids app-owned backend routing; live Responses smoke has passed for both scopes. Export can compose Transcript, Summary, or Both locally; Summary/Both generate or reuse encrypted local GPT-5.5 summary text through a fakeable direct OpenAI Responses gateway with `store: false`, then launch the Android native share sheet with selected recipients; live Responses smoke has passed for the summary path with expected headings validated. Physical microphone translation smoke, audible Android speaker recovery under live streaming, live OpenAI app-coordinator transcript de-duplication under real reconnect streaming, live credential-expiry/network-drop/rate-limit validation with real credential material, iOS share handoff, and any analytics/crash-reporting sink remain scoped to their GitHub issues.

Language support is centralized in `lib/src/language/language_support.dart`. The current table is conservative because official OpenAI Realtime Translation docs confirm the target-language parameter but do not publish a target-language enum. Default target options expose only English, Spanish, and French for realtime output; broader targets such as Japanese are represented as direct-OpenAI fallback-pending and stay inside the same phone-only privacy boundary.

## Prohibited MVP Flows

- Mobile app -> app backend -> OpenAI.
- Mobile app -> AWS/Lambda/token broker.
- Mobile app -> app-owned server mailer.
- Mobile app -> committed or bundled standard OpenAI API key.
- AI chat -> app backend or cloud transcript endpoint.
- Email export -> app backend or cloud export service.
- Logs/analytics/crash reports/screenshots/test output -> raw transcript, translated text, prompts, summaries, recipient lists, microphone audio, OpenAI credentials/session material, or API keys.
- Cloud transcript sync in the MVP.
