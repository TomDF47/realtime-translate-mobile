# Architecture

This document summarizes the implementation boundaries from the canonical [live translate build spec](live-translate-build-spec.md). The build spec remains authoritative when details conflict.

## System Shape

```text
Flutter phone app
  -> OpenAI API directly
       model: gpt-realtime-translate
       sends microphone audio
       receives translated audio and transcript deltas

Flutter phone app
  -> OpenAI API directly for AI chat and summaries
       scope: This meeting or All meetings
       product intent for export summaries: GPT-5.5 with extra-high reasoning
       implementation must verify current model/reasoning support before coding

Flutter phone app
  -> encrypted local device storage
       meetings, transcript/history, summary metadata, preferences,
       recent languages, remembered export recipients, last selected recipients,
       and any credential/session material

Flutter phone app
  -> device-native mail/share composer when user initiates export
       no app-operated outbound mail backend
```

There is no MVP AWS, Lambda, token broker, app backend, cloud sync, cloud identity gate, or server-side transcript handling. Deferred cloud/backend/auth ideas live in [docs/v2-future-scope.md](v2-future-scope.md).

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
- Direct OpenAI realtime session connection, reconnect, teardown, and error handling.
- Local encrypted storage for preferences, recent languages, meetings, transcript/history, summary metadata, recipient preferences, and any credential/session material.
- Meeting management for starting a new meeting, selecting an old meeting, and continuing from it.
- UI surfaces from [docs/mockup-ux-spec.md](mockup-ux-spec.md) and [assets/mockups](../assets/mockups), adapted for the phone-only MVP.
- Scoped AI chat UI and direct OpenAI request path for `This meeting` and `All meetings`.
- Email export UI with Transcript/Summary/Both selector and recipient checklist.

## OpenAI Responsibilities

- Live speech translation through `gpt-realtime-translate`.
- Stream translated audio and transcript deltas while the speaker is still talking.
- Support AI chat over local meeting context sent directly from the phone app.
- Support summary generation for email export if current model and reasoning parameters allow it.
- Language, authentication/session, realtime, and reasoning-parameter support must be verified during implementation rather than hard-coded from stale assumptions.

## Email Export Boundary

Email export is user initiated.

- The app prepares the selected Transcript, Summary, or Both locally.
- If Summary or Both is selected, the app may call OpenAI directly to generate the summary after support is verified.
- The app presents recipients as a local checklist and remembers the recipient list and last selected recipients locally.
- The app should hand the export to the device-native mail/share composer where practical.
- The app must not add a server mailer, backend relay, or cloud export queue in the MVP.

## Current Repo Layout

The first Flutter scaffold keeps boundaries visible:

```text
android/                     Android Flutter project and app namespace
ios/                         iOS-compatible Flutter project shell
lib/                         Flutter app code
lib/src/session/             Phone-local permission and live-session lifecycle state
lib/src/theme/               Shared design tokens and app theme
lib/src/ui/                  Structured UI state models and reusable components
lib/src/mock/                Local mock session data for UI development
test/                        Flutter tests
pubspec.yaml                 Flutter package manifest
pubspec.lock                 Pinned Dart package versions
docs/                        Product, architecture, setup, testing, decisions
assets/mockups/              Supplied Android mockups
```

The current app shell renders the phone-local welcome/start surface, Android microphone permission gate, mockup-derived live translation surfaces, scoped AI chat sheet, meeting history sheet, and local email export sheet. The lifecycle controller models permission, listening, read-aloud-paused, reconnecting, stop, app background/foreground, and audio-route state transitions, but real microphone capture, direct OpenAI streaming, encrypted storage, AI chat request execution, summary generation, native share handoff, and logging implementations remain scoped to their GitHub issues.

## Prohibited MVP Flows

- Mobile app -> app backend -> OpenAI.
- Mobile app -> AWS/Lambda/token broker.
- Mobile app -> app-owned server mailer.
- Mobile app -> committed or bundled standard OpenAI API key.
- AI chat -> app backend or cloud transcript endpoint.
- Email export -> app backend or cloud export service.
- Logs/analytics/crash reports/screenshots/test output -> raw transcript, translated text, prompts, summaries, recipient lists, microphone audio, OpenAI credentials/session material, or API keys.
- Cloud transcript sync in the MVP.
