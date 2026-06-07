# Current Product Requirements

Last synthesized: 2026-06-07

This document summarizes the realtime translate app requirements as they stand now, based on the repository documentation and latest operator notes. If this document conflicts with older docs, the latest operator notes and accepted decision log entries win. The canonical long-form source remains [live-translate-build-spec.md](live-translate-build-spec.md).

## Scope

Build an Android-first Flutter mobile app, structured to remain iOS-compatible later, for phone-local two-party live interpretation.

The MVP is phone-only except for direct OpenAI API calls. There is no app backend, AWS, Lambda, token broker, cloud identity gate, cloud sync, outbound mail backend, server-side transcript handling, or server-side export handling. User-provided OpenAI credential/session material is stored only in encrypted local device storage and must never be committed, bundled, logged, screenshotted, or placed in mobile config.

The active live experience is a transcription-first two-party interpreter with on-demand spoken output per transcript row. The user selects the two languages in use, the app treats that pair as locked from session start, and the meeting is preserved locally. Android forwards every captured PCM16 chunk to a Realtime transcription-only session using `gpt-realtime-whisper`; local pause/hard-cap batching decides only when to commit the already-forwarded OpenAI input buffer. Each completed transcription batch creates one stable local transcript row immediately, and the direct Responses text interpreter translates it with `store: false` into that same row. Spoken translated audio is not automatic: a translated transcript row has a voice button. Pressing it flushes any pending mic buffer, speaks that row's finalized translation through phone-local Android TextToSpeech, pauses microphone forwarding during playback, and resumes listening only if capture was active before the tap. Normal active UI operation must not create simultaneous primary/reverse realtime audio output. `gpt-realtime-translate` on `/v1/realtime/translations` and `gpt-realtime-2` remain explicit compatibility/debug profiles only.

## User Goals

- Start a live interpreter quickly from a premium phone-local start screen.
- Resume a previous local meeting without losing prior transcript history.
- Select the two conversation languages once, then speak naturally in either language without choosing direction manually.
- See the original speech and translated text clearly, with confidence/status when one side is pending.
- Play a specific translated transcript row aloud on demand.
- Know when the app is connecting, listening, paused, reconnecting, offline, credential-invalid, or in error.
- Pause live listening without ending the meeting or deleting local transcript state.
- Review local meeting history, ask scoped AI chat questions, and generate local encrypted exports.
- Trust that transcripts, summaries, credentials, prompts, audio, and generated exports are not routed through app-owned infrastructure or unsafe logs.

## Required Flows

### First Run And Local Setup

1. User opens the app and sees the mockup-derived dark navy `Live Translate` start surface.
2. Primary actions are `Start interpreter`, `Open meeting history`, and phone-local OpenAI setup/status where needed.
3. Provider sign-in buttons from the original mockup are V2/future only and must not gate the MVP.
4. Starting without a saved credential shows `OpenAI setup required` before microphone permission, realtime, or capture resources open.
5. The setup sheet accepts user-provided OpenAI credential/session material, stores it encrypted locally, does not redisplay the saved value, and provides removal/reset.
6. After a credential exists, starting a meeting opens the paused live surface and connects OpenAI realtime transcription in the background.
7. Android microphone permission is requested when the user taps `Resume Listening`, before capture starts.
8. Denied, permanently denied, and revoked microphone permission states must be explicit and must not start capture.

### Live Interpreter Startup

1. After `Start interpreter`, the app moves immediately to a visible live startup state instead of appearing stalled.
2. Startup must show an explicit loading/connecting indicator such as `Connecting to OpenAI` because initial connection can take about 15 seconds.
3. With a saved credential, startup should reach `listeningPaused`: OpenAI realtime transcription may be connected, but microphone capture and phone-local spoken output remain closed until the user taps `Resume Listening`.
4. Microphone capture must not start until the user resumes and permission is granted.
5. Startup errors must keep the user on a useful live/recovery surface with sanitized labels.

### Manual Language Pair And Translation

1. The live screen begins with visible `From` and `To` selectors for the two-language pair, defaulting to the last saved route when available and otherwise Italian <-> English.
2. `Auto-detect` is not offered as a source choice in the manual pair picker.
3. The top status shows the selected pair as `<A> <-> <B>` from session start.
4. Language selectors do not expose voice buttons or `Output voice` checkboxes in the active flow.
5. Each translated transcript row has a voice button that reads only that row's translated text on demand.
6. The top status must not depend on successful language discovery to know the two-language pair.
7. Later turns translate A-to-B and B-to-A without manual direction switching.
8. First-turn translation may be pending while transcription and text translation complete, but it must be backfilled into the correct transcript row.
9. The runtime tracks the selected pair and per-turn direction explicitly. For English/Italian, English speech creates an EN card with English original and Italian translation, while Italian speech creates an IT card with Italian original and English translation.

### Listening Controls

1. The active live screen has `Stop Listening`.
2. The active live screen must also have `Pause Listening` and `Resume Listening`.
3. `Pause Listening` is privacy-first: it commits pending microphone audio when present, stops microphone capture and any in-progress spoken output while preserving the active encrypted local meeting, transcript rows, selected pair, resume target, and warm realtime transcription session when available.
4. `Resume Listening` reuses the warm realtime transcription session when available, otherwise reconnects with the active realtime config and transcript commit target.
5. The elapsed timer advances only while microphone capture is open, pauses while listening is paused/reconnecting/offline/backgrounded, and resets for a new meeting.

### Meeting History

1. User can start a new meeting.
2. User can open meeting history, select an old meeting, and continue it.
3. Continuing a meeting appends new transcript/history entries without losing prior local history.
4. User can delete local meeting data.
5. Meeting metadata includes meeting ID, title or generated label, created/updated timestamps, language route or pair, transcript count, summary availability, and last activity.

### AI Chat

1. The feature is called `AI Chat`, not `air chat` or `Transcript Assistant` in product requirements.
2. AI chat scope is always explicit: `This meeting` or `All meetings`.
3. AI chat uses local transcript context and direct phone-to-OpenAI calls with `store: false`.
4. AI answers should cite local timestamps when possible.
5. AI chat handles empty transcript, no selected meeting, offline, unsupported, credential-invalid, and model/API error states.
6. The active live interpreter screen currently hides the live-header AI chat launcher so it does not compete with interpretation; AI chat remains available from appropriate meeting/history surfaces.

### Generated Exports

1. User can generate `Transcript`, `Summary`, or `Both`.
2. Generation runs asynchronously from the UI perspective; user can close the sheet and continue browsing.
3. Summary/Both uses direct phone-to-OpenAI Responses intent with GPT-5.5, `reasoning.effort: xhigh`, and `store: false`, subject to implementation-time API verification.
4. Generated export bodies are stored only in encrypted local storage and are browsed in app.
5. Plaintext export body appears only in the generated export detail view and through explicit `Copy`.
6. The active MVP export UI has no recipient input, recipient checklist, example recipients, add-recipient controls, delete-recipient controls, outbound mail backend, or server mailer.

## UI And State Requirements

- Preserve the supplied Android mockup visual direction: premium dark navy UI, teal listening accent, blue translation accent, amber speaking/read-aloud reference state, compact controls, restrained card radii, safe areas, and readable typography.
- The active MVP first screen focuses on starting or resuming interpretation, not cloud sign-in or a technical dashboard.
- The active live interpreter shows source and target language pickers without language-card voice buttons, and hides direction switch, `Translate Text` toggle, `Output voice` checkboxes, legacy global read-aloud controls, speaker/headphone chips, live-header AI chat, and live-screen export controls.
- Screenshotting or opening incidental device/app overlays must not cause hidden old direction-switch/read-aloud/export/chat controls to appear in the active live interpreter flow.
- Required session states include at least `localSetup`, `meetingSelection`, `connecting`, `listening`, `listeningPaused`, `speaking`, `readAloudPaused`, `reconnecting`, `offline`, `credentialInvalid`, and `error`.
- User-visible recovery labels must be sanitized and must not expose raw OpenAI server details, credentials, prompts, transcript text, or payloads.
- Bottom transcript padding must account for fixed controls and Android safe-area insets.
- Large text and compact viewports must not clip labels, transcript rows, export controls, or bottom controls.
- Icon-only controls need semantic labels; setup, meeting management, live controls, AI chat, export, and transcript actions need accessibility coverage.

## Transcript And Block Behavior

- Every visible transcript card must have both an original speech section and a translation section.
- Original speech must be shown. A final row with missing original speech is a defect.
- Pending halves use explicit placeholders such as `Original speech pending` or translation pending status, not blank cards.
- Completed transcription batches and translated text results must update separate fields in the same logical row.
- Transcription-first rows must be backfilled with the matching translation when the direct Responses request completes.
- Local batching rolls rows on committed transcription batches; later completed speech must not overwrite an earlier row.
- When the user switches from one language to another, such as English to Italian, the Italian speech must create a new block rather than appending to the existing previous-language block.
- A language change inside the same visible block is a defect unless it is an explicitly unfinished partial that resolves before finalization.
- Detected pauses should commit a readable batch, and a hard cap must prevent long-running speech from staying uncommitted indefinitely.
- Partial text should update the current visible block before final completion.
- Duplicate completed transcript events after reconnect must not create duplicate rows.
- Transcript rows are stored with meeting ID, language, original text, translated text, timestamp, speaker ownership, confidence/status, accent, playback state, and lifecycle status.

## Language Detection And Translation Behavior

- Source-row language labels are automatic in the active interpreter flow, but the interpreter pair itself is selected manually and locked from session start.
- The app does not wait to detect the first and second language before showing the pair.
- Italian and other supported languages should appear in transcript row language labels when transcription metadata or deterministic local detection can resolve them.
- The retained realtime target table covers the 13 documented OpenAI Realtime Translation output languages for compatibility/debug routes: Spanish, Portuguese, French, Japanese, Russian, Chinese, German, Korean, Hindi, Indonesian, Vietnamese, Italian, and English.
- Arabic and other languages that are not among the retained realtime output targets may be shown in picker/fallback contexts, but fallback behavior must stay phone-only with direct OpenAI calls only.
- The active two-party bidirectional design uses transcription-only Realtime intake as the single audio writer, direct Responses text translation for both directions, and serialized phone-local TTS from finalized translated row text. It does not open an additive reverse realtime audio session.

## Realtime Connection, Loading, And Recovery

- Direct OpenAI calls are the only routine product network path.
- Normal live intake uses Realtime transcription-only sessions with `gpt-realtime-whisper`, manual `input_audio_buffer.commit`, and direct Responses translation with `store: false`.
- Realtime startup can reach a warm paused state before microphone capture. Capture starts only after `Resume Listening` and microphone permission.
- Connection startup should have a bounded timeout/recovery path and a visible loading state; it must not leave the user staring at a static start screen for the roughly 15 second startup window.
- Credential expiry/rejection moves to `credentialInvalid` and closes capture/realtime/playback resources.
- Retryable network drops, socket closes, rate limits, transient OpenAI failures, connect timeouts, and lifecycle interruptions use bounded reconnect/backoff and show `reconnecting` or recovery UI.
- Unsupported language failures show a language-specific non-retryable recovery state.
- Offline/retry-exhausted states close live resources and preserve local meeting state where safe.

## Privacy, Security, And Diagnostics

- No standard OpenAI API keys in source, config, assets, tests, screenshots, build outputs, docs, or logs.
- No transcript, translated text, prompt, summary, recipient list, export payload, microphone audio, audio chunk, or audio-derived payload may be sent to app-owned backend infrastructure.
- Local meetings, transcripts, summaries, generated exports, preferences, recipient preferences, and credential/session material are encrypted on device.
- Android `RECORD_AUDIO` (live microphone capture) and `INTERNET` (the direct phone-to-OpenAI network path) are the only declared mobile permissions and must remain minimized/justified. Release builds must declare `INTERNET` in the main manifest, not rely on the debug/profile tooling overlay.
- Diagnostics are no-op by default and may record only allowlisted state/configuration labels after redaction/omission.
- Logs, diagnostics, analytics, crash reports, screenshots, and tests must exclude speech, transcripts, prompts, translations, summaries, recipient lists, export bodies, audio payloads, credentials, tokens, request bodies, and response bodies.
- Dependency/package changes require lockfile updates, advisory checks, and cybersecurity report updates.

## Known Defects And Gaps

- Physical Samsung validation still needs to prove the new room-capture path hears both people, commits real transcript batches, translates into distinct chronological rows, and speaks the selected row through Android TTS.
- After screenshotting, secondary options must not leak into the active interpreter UI.
- Final rows with missing original speech must be prevented.
- Initial connect can take about 15 seconds and needs a visible loading indicator.
- App-coordinator de-duplication under real live reconnect, live credential-expiry/network/rate-limit validation, production-volume storage behavior, and iOS share handoff still require further validation.
- Store-ready Android signing is not complete without local signing material.

## Acceptance Criteria

- Start screen shows phone-local MVP actions and on-device privacy reassurance; no Google/Microsoft sign-in is required for MVP.
- Starting without a credential shows setup-required before microphone permission or capture.
- Starting with a credential immediately shows a live connecting/loading state, then listening or sanitized recovery.
- Initial connect shows `Connecting to OpenAI` or equivalent for the slow startup window.
- Active live interpreter begins with visible source/target selectors and the selected pair as `<A> <-> <B>`.
- English then Italian speech creates distinct chronological transcript rows and does not append new speech to a previous completed row.
- Every final transcript card includes visible original speech and translation fields, with no blank final original.
- Completed transcription rows backfill the matching translation into the same row when the Responses request returns.
- Pause Listening commits pending mic audio when present, closes capture/spoken output while preserving local meeting and transcript state, and Resume Listening reuses the warm transcription session when available.
- Hidden active-flow controls remain hidden before and after screenshot/overlay/menu interactions: direction switch, `Translate Text`, read-aloud, speaker/headphone, live-header AI chat, and live-screen export controls.
- Meeting history can continue and delete encrypted local meetings.
- AI chat always shows `This meeting` or `All meetings` scope and sends context only through direct OpenAI with `store: false`.
- Generated exports stay encrypted in app until explicit Copy.
- No app backend, AWS, Lambda, token broker, cloud sync, server mailer, or server-side transcript/export handling is introduced.
- Validation for docs-only changes passes `bash scripts/check-docs.sh` and `git diff --check`.
- App changes additionally pass relevant Flutter tests, privacy/secret checks, supply-chain checks, and Android emulator or device smoke checks described in [testing-strategy.md](testing-strategy.md).

## Open Questions

- What exactly triggers "after screenshotting, other options appear": Android screenshot overlay, app menu, debug overlay, lifecycle pause/resume, or a specific screenshot tool?
- What is the `1124` block identifier: a visible timestamp, internal transcript row ID, meeting ID suffix, or UI test label?
- Resolved 2026-06-07: Italian remains in the retained realtime output-language table, but the active phone-test path no longer depends on realtime output-language support because it transcribes first and translates text batches.
- What exact text should be used for pending placeholders in production: `Original speech pending`, `Translation pending`, or shorter labels?
- Should `Pause Listening` be the primary center control, or should it sit beside `Stop Listening` in a simplified bottom bar?
- Which device/emulator path should be used for the next real microphone validation: host-audio emulator, physical Android device, or a controllable virtual audio route?
