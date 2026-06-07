# Architecture

This document summarizes the implementation boundaries from the canonical [live translate build spec](live-translate-build-spec.md). The build spec remains authoritative when details conflict.

## System Shape

```text
Flutter phone app
  -> OpenAI API directly
       active live interpreter starts from a visible manual A <-> B pair
       default pair is Italian <-> English
       gpt-realtime-whisper transcription-only session receives PCM16 audio batches
       app-side pause/hard-cap commits create transcript rows
       per-turn text translation uses Responses with store: false
       per-row voice buttons trigger on-demand phone-local TTS
       startup requests microphone permission and opens active capture
       legacy gpt-realtime-translate remains a compatibility/debug seam
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

- Phase 1 normal live interpreter behavior starts from the visible manual two-language pair. The app no longer waits for automatic pair discovery before showing the route label or seeding bidirectional routing.
- The interpreter owns an explicit pair/direction model. Per-turn source labels can still come from OpenAI language metadata or deterministic local detection, but the user-selected pair is the routing contract from session start.
- The realtime output-language table follows the 2026-06-01 verified 13-language Realtime Translation output list: English, Spanish, French, Italian, Japanese, Russian, Chinese, German, Korean, Hindi, Indonesian, Vietnamese, and Portuguese. Arabic remains source-supported and direct-fallback target-supported, but it is not a realtime output target.
- Legacy `/v1/realtime/translations` behavior still follows the realtime output-language table when that gateway is used for compatibility/debug checks. The active path does not depend on realtime output-language support for transcript rows because it transcribes first, then translates completed text through Responses with `store: false`.
- The existing live human-speech interpretation seam through `gpt-realtime-translate` on `/v1/realtime/translations` remains available for compatibility/debug use, but the active app path uses Realtime transcription-only sessions (`gpt-realtime-whisper`, `type: transcription`, manual commits) followed by direct Responses translation. The active UI keeps secondary direction switch, legacy global read-aloud controls, live-header AI chat, live-screen export controls, language-card voice buttons, and `Output voice` checkboxes hidden. Spoken translated audio is available only as on-demand playback from the voice button on each translated transcript row.
- Starting an interpreter with a saved credential requests microphone permission, opens microphone capture, and enters active `listening` once the primary realtime transcription session is ready. Pausing listening commits pending microphone audio when present, stops microphone capture and any in-progress spoken output while keeping the realtime transcription session warm when available; resume reuses the warm session instead of reconnecting.
- The selected transcript-row voice button controls spoken output on demand. Pressing it flushes any pending microphone buffer, speaks that row's finalized translated text through phone-local Android TextToSpeech, stops microphone capture while the utterance is playing, and resumes listening only if capture was active before the tap. The active UI leaves primary/reverse realtime audio playback closed in normal operation. Text transcript rows and direct OpenAI text translation remain available regardless of manual spoken playback.
- The active transcription session must configure `session.type = transcription`, 24 kHz mono PCM input, `audio.input.transcription.model = gpt-realtime-whisper`, and `audio.input.turn_detection = null`. Local batching commits the input buffer manually. Local pause detection must never decide whether a chunk is forwarded to OpenAI; it only decides when the already-forwarded buffer should be committed.
- On this no-item-id, no-language-metadata wire the completed source utterance is the only reliable turn boundary, so `RealtimeTranscriptCommitter` only rolls a new readable block once the current turn's source has completed, and never rolls a block on a translation event. Source and target transcripts stream on independent cadences, and the translation frequently crosses sentence boundaries (or grows long) while the same source utterance is still being transcribed; rolling on the translation alone there would orphan the continued translation onto a sourceless card (`Original speech pending`) and prevent second-language detection. Even after the source completes, a later translation delta/done for the same turn has no new source to distinguish it from a new turn, so it stays on the current card with the original preserved and the full translation appended. A genuinely new source utterance after completion is the sole splitter that starts a new card.
- The coordinator maintains content-free source/output transcript signal counters, exposes a `transcriptSignalSnapshot` (source/output turn counts, sourceless-final count, and derived `hasSourcelessFinal`/`translationArrivedWithoutSource`), and emits a privacy-safe `live_realtime.translation_without_source` warning when a card finalizes with translated output but no original text. `hasSourcelessFinal` (and `translationArrivedWithoutSource`, which now derives from it) trips on any sourceless final (`sourcelessFinalCount > 0`), so it catches the round-3 shape where the first card had source but a later card lost the original — not only the all-output/no-source case where source never arrived at all. Because a turn's translation can finalize before its source on this wire, a translation-only finalization is only provisionally counted by entry id: when the same row later backfills original text the count is reversed, so the valid translation-first-then-source-backfill ordering leaves `sourcelessFinalCount == 0` and does not falsely trip the signal. These signals carry only counts/derived flags — never transcript or translation content — so a release check can detect "translation arrived but original source never did" without weakening the redaction boundary.
- `gpt-realtime-translate` and `gpt-realtime-2` are kept only as explicit compatibility/debug profiles unless a later decision changes the live route.
- Stream source transcript completions from Realtime transcription, then translate completed transcript text through Responses with `store: false`.
- The active interpreter flow shows source and target selectors for the manual two-language pair, defaults to the last saved pair when available and otherwise Italian <-> English, and treats that pair as locked from session start. It has no direction switch, no `Translate Text` toggle, no `Output voice` checkbox, no live-header AI chat launcher, and no live-screen export controls. Per-turn source labels still use OpenAI language metadata or deterministic local detection when available.
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

The current app shell renders the phone-local welcome/start surface, OpenAI setup-required state, encrypted OpenAI setup sheet, Android microphone permission gate, two-party live interpreter surface, scoped AI chat sheet, encrypted local meeting history sheet, and local generated export surfaces. The UI defaults to the last saved pair when available and otherwise Italian <-> English, lets the user choose any supported app source/target pair, seeds that pair into the bidirectional interpreter runtime from session start, and hides direction switching, the `Translate Text` toggle, live-header AI chat, live-screen export controls, legacy global read-aloud controls, language-card voice buttons, `Output voice` checkboxes, and speaker/headphone chips until secondary workflows are safely placed without misleading the user. Starting a meeting requests microphone permission, opens the OpenAI transcription session, opens room microphone capture, and lands on the active listening surface with `Pause Listening`. Pausing listening flushes any pending transcription buffer, stops microphone capture and in-progress spoken output, and keeps the OpenAI session warm when available; resume reuses that warm session with the active config and commit target. The active live loop is text-first: each completed transcription batch creates a stable transcript row, direct Responses translation updates that row, and row-level playback speaks only that row's finalized translation. The coordinator pauses capture during manual TTS and resumes capture only if it was active before the tap. Android room capture requests an unprocessed/MIC audio source where possible and disables platform input effects in the active batch path. The storage layer persists meetings, transcript/history entries, summary text/metadata, generated export bodies, recent language routes, recipient preferences, sensitive preferences, and credential/session material through `flutter_secure_storage`, with Android backup disabled for app data. Privacy-safe diagnostics are no-op by default and can record only allowlisted state/configuration fields after redaction/omission. Existing realtime translation scaffolding can still construct direct OpenAI WebSocket sessions for the dedicated `gpt-realtime-translate` live profile or explicit compatibility `gpt-realtime-2` profile, but production app startup now opts into the transcription-first path. Physical microphone translation smoke, audible Android TTS behavior from installed per-row playback, live OpenAI app-coordinator transcript de-duplication under real reconnect streaming, live credential-expiry/network-drop/rate-limit validation with real credential material, iOS share handoff, and any analytics/crash-reporting sink remain scoped to their GitHub issues.

Language support is centralized in `lib/src/language/language_support.dart`. The current realtime output table follows the 2026-06-01 verified OpenAI Realtime Translation cookbook list of 13 output languages: Spanish, Portuguese, French, Japanese, Russian, Chinese, German, Korean, Hindi, Indonesian, Vietnamese, Italian, and English. Arabic remains a direct-OpenAI fallback target because it is input-supported but not in that realtime output list. The target picker shows all app target languages while labeling realtime output targets and broader direct-OpenAI fallback targets inside the same phone-only privacy boundary.

## Prohibited MVP Flows

- Mobile app -> app backend -> OpenAI.
- Mobile app -> AWS/Lambda/token broker.
- Mobile app -> app-owned server mailer.
- Mobile app -> committed or bundled standard OpenAI API key.
- AI chat -> app backend or cloud transcript endpoint.
- Generated/email export -> app backend or cloud export service.
- Logs/analytics/crash reports/screenshots/test output -> raw transcript, translated text, prompts, summaries, recipient lists, microphone audio, OpenAI credentials/session material, or API keys.
- Cloud transcript sync in the MVP.
