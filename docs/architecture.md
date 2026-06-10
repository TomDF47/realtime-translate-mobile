# Architecture

This document summarizes the implementation boundaries from the canonical [live translate build spec](live-translate-build-spec.md). The build spec remains authoritative when details conflict.

## System Shape

```text
Flutter phone app
  -> Gemini Live API directly
       active live interpreter starts from a visible manual A <-> B pair
       default pair is Italian <-> English
       gemini-3.5-live-translate-preview translates live speech
       input audio is 16 kHz mono PCM16 in 100 ms chunks
       Gemini serverContent input/output transcripts map into local transcript rows

Flutter phone app
  -> OpenAI API directly
       per-turn text fallback uses Responses with store: false when a direction is text-only
       retained compatibility/experimental realtime profiles: gpt-realtime-translate and gpt-realtime-2

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

There is no MVP AWS, Lambda, token broker, app backend, cloud sync, cloud identity gate, or server-side transcript handling. The accepted MVP credential approach is user-provided Gemini/OpenAI credential/session material stored only in encrypted local device storage under provider-specific labels. Deferred cloud/backend/auth ideas live in [docs/v2-future-scope.md](v2-future-scope.md).

## Hard Boundaries

- Mobile source, committed config, assets, tests, screenshots, and build outputs never contain a standard Gemini or OpenAI API key.
- The MVP has no app backend.
- Direct Gemini API calls for live translation and direct OpenAI API calls for AI chat, summaries, and approved text fallback are the only routine network paths for product behavior.
- Transcript text, translated text, prompts, microphone audio, audio chunks, audio-derived payloads, summaries, recipient lists, meeting metadata, and export payloads must not be sent to app-owned backend infrastructure.
- The app must not operate an outbound mail backend for MVP export.
- Meeting and transcript storage is local-only and encrypted for the MVP.
- Diagnostics, analytics, crash reports, screenshots, test output, and logs must exclude secrets and speech/transcript/summary/export payloads.

## Mobile App Responsibilities

- Flutter app with Android-first UX and iOS-compatible structure.
- Phone-local setup/start flow rather than cloud sign-in gate.
- Runtime microphone permissions and explicit session state transitions.
- Direct Gemini interpreter session connection, credential-invalid handling, reconnect, teardown, and error handling, with retained OpenAI realtime compatibility seams.
- Local encrypted storage for preferences, recent languages, meetings, transcript/history, summary metadata, generated exports, recipient preferences, and any credential/session material.
- Privacy-safe local diagnostics through a no-op-by-default allowlist/redaction helper.
- Meeting management for starting a new meeting, selecting an old meeting, and continuing from it.
- UI surfaces from [docs/mockup-ux-spec.md](mockup-ux-spec.md) and [assets/mockups](../assets/mockups), adapted for the phone-only MVP.
- Scoped AI chat UI and direct OpenAI request path for `This meeting` and `All meetings`.
- Generated export UI with Transcript/Summary/Both selector, local transcript/summary composition, direct OpenAI summary generation, encrypted local generated-export persistence, in-app export browser/detail views, and explicit Copy action.

## Gemini Live Responsibilities

- The active live interpreter uses `gemini-3.5-live-translate-preview` through the Gemini Live API raw WebSocket contract.
- The setup message sets `setup.model = models/gemini-3.5-live-translate-preview`, `generationConfig.responseModalities = ["AUDIO"]`, `inputAudioTranscription = {}`, `outputAudioTranscription = {}`, and `translationConfig.targetLanguageCode` from the selected manual target language.
- Microphone capture for Gemini uses raw little-endian mono PCM16 at 16 kHz in 100 ms chunks, sent as `realtimeInput.audio` with `mimeType: audio/pcm;rate=16000`.
- Gemini `serverContent.inputTranscription` is the source/original transcript, `serverContent.outputTranscription` is the translated transcript, and `serverContent.modelTurn.parts[].inlineData` is translated 24 kHz mono PCM16 audio.
- Gemini credential material is stored only in encrypted local device storage under Gemini-specific keys and is never included in setup/audio JSON messages, diagnostics, logs, screenshots, or committed config.

## OpenAI Responsibilities

- Phase 1 normal live interpreter behavior starts from the visible manual two-language pair. The app no longer waits for automatic pair discovery before showing the route label or seeding bidirectional routing.
- The interpreter owns an explicit pair/direction model. Per-turn source labels can still come from OpenAI language metadata or deterministic local detection, but the user-selected pair is the routing contract from session start.
- The active Gemini live route supports the current app target set, including Arabic, and sends the selected target language directly to Gemini. The older OpenAI Realtime output-language table remains compatibility context only.
- Direct OpenAI text fallback remains available for approved text-only fallback cases. Missing or rejected OpenAI fallback credentials route the user to OpenAI setup, while Gemini live credential failures route to Gemini setup.
- The existing live human-speech interpretation seam through `gpt-realtime-translate` on `/v1/realtime/translations` remains available only as compatibility/fallback code; Gemini is the default live route and diagnostics label Gemini live sessions with the Gemini provider/model.
- The dedicated translation session must configure `audio.input.transcription` (`gpt-realtime-whisper`) and `audio.input.noise_reduction` (`near_field`) so OpenAI streams the source/original transcript (`session.input_transcript`). It sets only `audio.output.language` and sends no model, instructions, or source language. This is the boundary contract that lets the original speech display and lets the committer split turns on source-utterance boundaries; omitting it (the pre-2026-06-01 defect) yields translation-only events in a single block.
- On this no-item-id, no-language-metadata wire the completed source utterance is the only reliable turn boundary, so `RealtimeTranscriptCommitter` only rolls a new readable block once the current turn's source has completed, and never rolls a block on a translation event. Source and target transcripts stream on independent cadences, and the translation frequently crosses sentence boundaries (or grows long) while the same source utterance is still being transcribed; rolling on the translation alone there would orphan the continued translation onto a sourceless card (`Original speech pending`) and prevent second-language detection. Even after the source completes, a later translation delta/done for the same turn has no new source to distinguish it from a new turn, so it stays on the current card with the original preserved and the full translation appended. A genuinely new source utterance after completion is the sole splitter that starts a new card.
- The coordinator maintains content-free source/output transcript signal counters, exposes a `transcriptSignalSnapshot` (source/output turn counts, sourceless-final count, and derived `hasSourcelessFinal`/`translationArrivedWithoutSource`), and emits a privacy-safe `live_realtime.translation_without_source` warning when a card finalizes with translated output but no original text. `hasSourcelessFinal` (and `translationArrivedWithoutSource`, which now derives from it) trips on any sourceless final (`sourcelessFinalCount > 0`), so it catches the round-3 shape where the first card had source but a later card lost the original — not only the all-output/no-source case where source never arrived at all. Because a turn's translation can finalize before its source on this wire, a translation-only finalization is only provisionally counted by entry id: when the same row later backfills original text the count is reversed, so the valid translation-first-then-source-backfill ordering leaves `sourcelessFinalCount == 0` and does not falsely trip the signal. These signals carry only counts/derived flags — never transcript or translation content — so a release check can detect "translation arrived but original source never did" without weakening the redaction boundary.
- `gpt-realtime-2` kept only as an explicit compatibility/experimental voice-agent profile unless a later decision changes the live route.
- Stream source and translated transcript deltas; source deltas require the input-transcription config above.
- The active interpreter flow shows source and target selectors for the manual two-language pair, defaults to Italian <-> English, and treats that pair as locked from session start. It has no direction switch, no `Translate Text` toggle, no live-header AI chat launcher, and no live-screen export controls. Per-turn source labels still use OpenAI language metadata or deterministic local detection when available.
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

The current app shell renders the phone-local welcome/start surface, Gemini live setup-required state, encrypted Gemini live setup sheet, separate encrypted OpenAI chat/summary setup sheet, Android microphone permission gate, two-party live interpreter surface, scoped AI chat sheet, encrypted local meeting history sheet, and local generated export surfaces. Issue #30 removed the old default route-translation controls from the active live surface, and the 2026-06-02 manual-pair decision restores visible source/target selectors because on-device automatic language discovery did not reliably converge. The UI defaults to Italian <-> English, lets the user choose any supported app source/target pair, seeds that pair into the bidirectional interpreter runtime from session start, and hides direction switching, the `Translate Text` toggle, live-header AI chat, live-screen export controls, read-aloud controls, and speaker/headphone chips until secondary workflows are safely placed without misleading the user. The active live loop is text-first by default: read-aloud starts off and the coordinator skips translated-audio playback startup while read-aloud is off. Issue #53 makes Gemini Live Translate the default live route while retaining OpenAI realtime as compatibility code. The storage layer persists meetings, transcript/history entries, summary text/metadata, generated export bodies, recent language routes, recipient preferences, sensitive preferences, and provider-specific credential/session material through `flutter_secure_storage`, with Android backup disabled for app data. Privacy-safe diagnostics are no-op by default and can record only allowlisted state/configuration fields after redaction/omission. Meeting management can start a new local meeting after a Gemini live credential is configured, select a stored meeting, reopen it as the active encrypted local context, append continuation transcript history, and delete stored meeting metadata; deleting the active meeting stops realtime/capture/playback before clearing active state. A fakeable direct OpenAI text interpreter gateway builds Responses requests with `store: false` and no backend route; focused tests cover manual source/target selection, pair seeding, stable source-delta direct fallback, A-to-B/B-to-A fake translation, text-only playback suppression, and no credential leakage in request bodies. Existing realtime scaffolding can still construct direct OpenAI WebSocket sessions for the dedicated `gpt-realtime-translate` live profile or explicit compatibility `gpt-realtime-2` profile. Physical microphone translation smoke, audible Android speaker recovery under live streaming, live credential-expiry/network-drop/rate-limit validation with real credential material, iOS share handoff, and any analytics/crash-reporting sink remain scoped to their GitHub issues.

Language support is centralized in `lib/src/language/language_support.dart`. For the active Gemini live route, the app target picker sends the selected app target directly to Gemini, including Arabic. Retained OpenAI realtime output-language support is compatibility-only and must not rewrite the active Gemini target before live start.

## Prohibited MVP Flows

- Mobile app -> app backend -> OpenAI.
- Mobile app -> AWS/Lambda/token broker.
- Mobile app -> app-owned server mailer.
- Mobile app -> committed or bundled standard Gemini/OpenAI API key.
- AI chat -> app backend or cloud transcript endpoint.
- Generated/email export -> app backend or cloud export service.
- Logs/analytics/crash reports/screenshots/test output -> raw transcript, translated text, prompts, summaries, recipient lists, microphone audio, OpenAI credentials/session material, or API keys.
- Cloud transcript sync in the MVP.
