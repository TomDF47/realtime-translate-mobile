# Architecture

This document summarizes the implementation boundaries from the canonical [live translate build spec](live-translate-build-spec.md). The build spec remains authoritative when details conflict.

## System Shape

```text
Flutter phone app
  -> OpenAI API directly
       Phase 1 live interpreter text path uses Responses with store: false
       detects first language, waits for second distinct language, then locks A <-> B
       translates subsequent turns A-to-B and B-to-A as text
       existing realtime audio seams remain for later validated audio work
       explicit compatibility/experimental profile: gpt-realtime-2

Flutter phone app
  -> OpenAI API directly for AI chat and summaries
       scope: This meeting or All meetings
       product intent for export summaries: GPT-5.5 with xhigh reasoning

Flutter phone app
  -> encrypted local device storage
       meetings, transcript/history, summary metadata, preferences,
       recent languages, generated exports, remembered export recipients,
       last selected recipients, and any credential/session material

Flutter phone app
  -> in-app generated export browser and explicit clipboard copy
       no app-operated outbound mail backend
       Transcript/Summary/Both exports are generated into encrypted local storage
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
- Direct OpenAI interpreter/realtime session connection, credential-invalid handling, reconnect, teardown, and error handling.
- Local encrypted storage for preferences, recent languages, meetings, transcript/history, summary metadata, generated exports, recipient preferences, and any credential/session material.
- Privacy-safe local diagnostics through a no-op-by-default allowlist/redaction helper.
- Meeting management for starting a new meeting, selecting an old meeting, and continuing from it.
- UI surfaces from [docs/mockup-ux-spec.md](mockup-ux-spec.md) and [assets/mockups](../assets/mockups), adapted for the phone-only MVP.
- Scoped AI chat UI and direct OpenAI request path for `This meeting` and `All meetings`.
- Generated export UI with Transcript/Summary/Both selector, local transcript/summary composition, direct OpenAI summary generation, encrypted local generated-export persistence, in-app export browser/detail views, and explicit Copy action.

## OpenAI Responsibilities

- Phase 1 normal live interpreter behavior is text-first: detect the two languages in use and translate turns bidirectionally through direct OpenAI calls with `store: false`.
- The existing live human-speech interpretation seam through `gpt-realtime-translate` on `/v1/realtime/translations` remains available for validated audio work, but the active UI must not claim automatic bidirectional spoken audio until it is safely supported.
- `gpt-realtime-2` kept only as an explicit compatibility/experimental voice-agent profile unless a later decision changes the live route.
- Stream source and translated transcript deltas when live audio support is explicitly validated.
- The active interpreter flow has no source picker, no target picker, no direction switch, no `Translate Text` toggle, no live-header AI chat launcher, and no live-screen export controls. Language discovery is automatic: one detected language shows a waiting state, and two distinct languages lock as `<A> <-> <B>`.
- Support AI chat over local meeting context sent directly from the phone app.
- Support summary generation for generated exports if current model and reasoning parameters allow it.
- Endpoint/model behavior, realtime translation target languages, and reasoning-parameter support must be verified during implementation rather than hard-coded from stale assumptions.

## Generated Export Boundary

Export generation and copying are user initiated.

- The app prepares the selected Transcript, Summary, or Both locally.
- If Summary or Both is selected, the app calls OpenAI directly from the phone to generate or refresh a local `gpt-5.5` summary with `reasoning.effort: xhigh` and `store: false`.
- The active MVP export UI does not show recipient input, recipient checklist, example recipients, add-recipient controls, or delete-recipient controls.
- Transcript, Summary, and Both export documents are saved only through encrypted local meeting storage and browsed inside the app.
- Plaintext export bodies are exposed only in the generated export detail view and when the user explicitly presses Copy.
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

The current app shell renders the phone-local welcome/start surface, OpenAI setup-required state, encrypted OpenAI setup sheet, Android microphone permission gate, two-party live interpreter surface, scoped AI chat sheet, encrypted local meeting history sheet, and local generated export surfaces. Issue #30 removes the old default route-translation controls from the active live surface: the UI starts as `Listening for languages...`, renders first-language and pair-lock state from detected transcript language codes, and hides source/target pickers, direction switching, the `Translate Text` toggle, live-header AI chat, live-screen export controls, read-aloud controls, and speaker/headphone chips until audio behavior and secondary workflows are safely placed without misleading the user. The storage layer persists meetings, transcript/history entries, summary text/metadata, generated export bodies, recent language routes, recipient preferences, sensitive preferences, and credential/session material through `flutter_secure_storage`, with Android backup disabled for app data. Privacy-safe diagnostics are no-op by default and can record only allowlisted state/configuration fields after redaction/omission. Meeting management can start a new local meeting after a credential is configured, select a stored meeting, reopen it as the active encrypted local context, append continuation transcript history, and delete stored meeting metadata; deleting the active meeting stops realtime/capture/playback before clearing active state. A fakeable direct OpenAI text interpreter gateway builds Responses requests with `store: false` and no backend route; focused tests cover first-language discovery, delayed first-turn backfill after the second language is discovered, pair lock, A-to-B/B-to-A fake translation, and no credential leakage in request bodies. Existing realtime scaffolding can still construct direct OpenAI WebSocket sessions for the dedicated `gpt-realtime-translate` live profile or explicit compatibility `gpt-realtime-2` profile, send PCM16 append events, parse translated audio plus transcript delta/completion/segment events, and keep credential material in the Authorization header only. Physical microphone translation smoke, audible Android speaker recovery under live streaming, live OpenAI app-coordinator transcript de-duplication under real reconnect streaming, live credential-expiry/network-drop/rate-limit validation with real credential material, iOS share handoff, and any analytics/crash-reporting sink remain scoped to their GitHub issues.

Language support is centralized in `lib/src/language/language_support.dart`. The current realtime table is conservative because official OpenAI Realtime Translation docs confirm the target-language parameter but do not publish a target-language enum. The target picker shows all app target languages while labeling English, Spanish, and French as realtime output targets and broader targets such as Japanese as direct-OpenAI fallback targets that stay inside the same phone-only privacy boundary.

## Prohibited MVP Flows

- Mobile app -> app backend -> OpenAI.
- Mobile app -> AWS/Lambda/token broker.
- Mobile app -> app-owned server mailer.
- Mobile app -> committed or bundled standard OpenAI API key.
- AI chat -> app backend or cloud transcript endpoint.
- Generated/email export -> app backend or cloud export service.
- Logs/analytics/crash reports/screenshots/test output -> raw transcript, translated text, prompts, summaries, recipient lists, microphone audio, OpenAI credentials/session material, or API keys.
- Cloud transcript sync in the MVP.
