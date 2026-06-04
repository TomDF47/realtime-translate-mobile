# Current Product Requirements

Last synthesized: 2026-06-04

This document summarizes the realtime translate app requirements as they stand now, based on the repository documentation and latest operator notes. If this document conflicts with older docs, the latest operator notes and accepted decision log entries win. The canonical long-form source remains [live-translate-build-spec.md](live-translate-build-spec.md).

## Scope

Build an Android-first Flutter mobile app, structured to remain iOS-compatible later, for phone-local two-party live interpretation.

The MVP is phone-only except for direct OpenAI API calls. There is no app backend, AWS, Lambda, token broker, cloud identity gate, cloud sync, outbound mail backend, server-side transcript handling, or server-side export handling. User-provided OpenAI credential/session material is stored only in encrypted local device storage and must never be committed, bundled, logged, screenshotted, or placed in mobile config.

The active live experience is a text-first two-party interpreter with opt-in spoken output per language side. The user selects the two languages in use, the app treats that pair as locked from session start, transcript rows still use OpenAI metadata or deterministic local detection for source labels when available, and the meeting is preserved locally. Spoken translated audio is not automatic: each `From`/`To` language card has an `Output voice` checkbox that defaults off and persists with the recent language route. Checked sides speak finalized translated card text through serialized phone-local Android TextToSpeech; normal active UI operation must not create simultaneous primary/reverse realtime audio output. Normal live human-speech translation should use `gpt-realtime-translate` on `/v1/realtime/translations`; `gpt-realtime-2` remains only an explicit compatibility/experimental voice-agent profile.

## User Goals

- Start a live interpreter quickly from a premium phone-local start screen.
- Resume a previous local meeting without losing prior transcript history.
- Select the two conversation languages once, then speak naturally in either language without choosing direction manually.
- See the original speech and translated text clearly, with confidence/status when one side is pending.
- Choose independently whether each side's translated text should be spoken aloud.
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
6. After a credential exists, starting a meeting opens the paused live surface and connects OpenAI realtime in the background.
7. Android microphone permission is requested when the user taps `Resume Listening`, before capture starts.
8. Denied, permanently denied, and revoked microphone permission states must be explicit and must not start capture.

### Live Interpreter Startup

1. After `Start interpreter`, the app moves immediately to a visible live startup state instead of appearing stalled.
2. Startup must show an explicit loading/connecting indicator such as `Connecting to OpenAI` because initial connection can take about 15 seconds.
3. With a saved credential, startup should reach `listeningPaused`: OpenAI realtime may be connected, but microphone capture, realtime audio playback, and phone-local spoken output remain closed until the user taps `Resume Listening`.
4. Microphone capture must not start until the user resumes and permission is granted.
5. Startup errors must keep the user on a useful live/recovery surface with sanitized labels.

### Manual Language Pair And Translation

1. The live screen begins with visible `From` and `To` selectors for the two-language pair, defaulting to the last saved route when available and otherwise Italian <-> English.
2. `Auto-detect` is not offered as a source choice in the manual pair picker.
3. The top status shows the selected pair as `<A> <-> <B>` from session start.
4. Each selector has an `Output voice` checkbox. Both default off, persist with the recent route, and control whether that side's translated text is spoken. Spoken output is one utterance at a time and must stop when a new source utterance interrupts it.
5. The app must still detect Italian and other supported source languages from realtime metadata when available, and must fall back to deterministic local detection for source-row labels when metadata is missing.
6. The top status must not depend on successful language discovery to know the two-language pair.
7. Later turns translate A-to-B and B-to-A without manual direction switching.
8. First-turn translation may be pending while source/translation events arrive, but it must be backfilled into the correct transcript block.
9. The runtime tracks the selected pair and per-turn direction explicitly. For English/Italian, English speech creates an EN card with English original and Italian translation, while Italian speech creates an IT card with Italian original and English translation.

### Listening Controls

1. The active live screen has `Stop Listening`.
2. The active live screen must also have `Pause Listening` and `Resume Listening`.
3. `Pause Listening` is privacy-first: it stops microphone capture, realtime audio playback, and any in-progress spoken output while preserving the active encrypted local meeting, transcript rows, detected languages, resume target, and warm realtime session when available.
4. `Resume Listening` reuses the warm realtime session when available, otherwise reconnects with the active realtime config and transcript commit target.
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
- The active live interpreter shows source and target language pickers with per-side `Output voice` checkboxes, and hides direction switch, `Translate Text` toggle, legacy global read-aloud controls, speaker/headphone chips, live-header AI chat, and live-screen export controls.
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
- Realtime source/original transcript deltas and translated output deltas must update separate fields in the same logical block.
- Translation-first rows must be backfilled when original speech arrives.
- Blocks roll on source item changes, source language changes, or a new source after a completed source-plus-translation pair.
- When the user switches from one language to another, such as English to Italian, the Italian speech must create a new block rather than appending to the existing previous-language block.
- A language change inside the same visible block is a defect unless it is an explicitly unfinished partial that resolves before finalization.
- Roughly every two completed spoken sentences should form a separate readable block when the source/language continuity allows it.
- Partial text should update the current visible block before final completion.
- Duplicate completed transcript events after reconnect must not create duplicate rows.
- Transcript rows are stored with meeting ID, language, original text, translated text, timestamp, speaker ownership, confidence/status, accent, playback state, and lifecycle status.

## Language Detection And Translation Behavior

- Source-row language labels are automatic in the active interpreter flow, but the interpreter pair itself is selected manually and locked from session start.
- The app does not wait to detect the first and second language before showing the pair.
- Italian must be recognized in the top status and transcript block language labels when spoken.
- Common nested realtime language metadata must be parsed.
- Deterministic local fallback detection must cover at least English, Italian, Spanish, and French when realtime metadata is absent.
- The realtime target table covers the 13 documented OpenAI Realtime Translation output languages: Spanish, Portuguese, French, Japanese, Russian, Chinese, German, Korean, Hindi, Indonesian, Vietnamese, Italian, and English (corrected 2026-06-01 from the earlier English/Spanish/French-only conservative table per the OpenAI cookbook).
- Arabic and other auto-detected input languages that are not among the 13 outputs may be shown in picker/fallback contexts, but must be labeled as direct-OpenAI fallback targets.
- Fallback behavior must be explicit in UI and must stay phone-only with direct OpenAI calls only.
- Italian is a realtime output target. The two-party bidirectional design uses a primary `/v1/realtime/translations` session as the single transcript writer for source/translation evidence. Reverse-direction text is produced by the direct OpenAI text path when needed, and spoken output is produced by serialized phone-local TTS from finalized translated card text rather than by opening an additive reverse realtime audio session.

## Realtime Connection, Loading, And Recovery

- Direct OpenAI calls are the only routine product network path.
- Normal live translation uses `gpt-realtime-translate` on `/v1/realtime/translations`.
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

- Latest operator report says the translate app is still not working as expected when language detection is expected to infer the pair.
- After screenshotting, secondary options must not leak into the active interpreter UI.
- Original speech is not reliably shown; final rows with missing original speech must be prevented.
- Italian speech appended onto an existing `1124` block instead of creating a new block; block splitting must honor source item and language changes.
- The top status should not depend on detecting that Italian was spoken; the manually selected pair should be visible before speech arrives.
- A dedicated `Pause Listening` control is required if not already present in the tested build.
- Initial connect takes about 15 seconds and needs a visible loading indicator.
- Physical microphone translation, installed-app committed transcript validation from live speech, app-coordinator de-duplication under real live reconnect, live credential-expiry/network/rate-limit validation, and audible Android speaker recovery still require further validation.
- Store-ready Android signing is not complete without local signing material.

## Acceptance Criteria

- Start screen shows phone-local MVP actions and on-device privacy reassurance; no Google/Microsoft sign-in is required for MVP.
- Starting without a credential shows setup-required before microphone permission or capture.
- Starting with a credential immediately shows a live connecting/loading state, then listening or sanitized recovery.
- Initial connect shows `Connecting to OpenAI` or equivalent for the slow startup window.
- Active live interpreter begins with visible source/target selectors and the selected pair as `<A> <-> <B>`.
- Italian speech updates transcript row language labels when metadata or local detection is available and does not append to a previous-language completed block.
- Every final transcript card includes visible original speech and translation fields, with no blank final original.
- Translation-first rows backfill original speech into the same block when it arrives.
- Pause Listening closes capture/realtime/playback while preserving local meeting and transcript state; Resume Listening reconnects.
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
- Resolved 2026-06-01: Italian is one of the 13 documented Realtime Translation output languages, so it is now a realtime output target (no longer text-fallback-only). Remaining validation is the on-device EN+IT bidirectional confirmation under #6/#31.
- What exact text should be used for pending placeholders in production: `Original speech pending`, `Translation pending`, or shorter labels?
- Should `Pause Listening` be the primary center control, or should it sit beside `Stop Listening` in a simplified bottom bar?
- Which device/emulator path should be used for the next real microphone validation: host-audio emulator, physical Android device, or a controllable virtual audio route?
