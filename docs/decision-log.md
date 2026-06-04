# Decision Log

Use this file for durable product and architecture decisions that future agents should preserve. The canonical build spec remains [docs/live-translate-build-spec.md](live-translate-build-spec.md).

## 2026-06-04 - Warm Paused Startup With Per-Side Spoken Output Opt-In

Status: Accepted as code direction (local Windows checkout still relies on CI/Fedora for Flutter analyzer, tests, APK build, and installed-device proof)

Context:

- Tom's Samsung retest showed the app could create English and Italian transcript boxes after a pause/resume cycle, but startup and language changes were still fragile: the first microphone permission flow could fall back to a preparing screen, English-to-Italian speech sometimes wrote English into the translation field, and unexpected translated audio played.
- The desired interpreter contract is a manual two-language pair, not automatic pair discovery. For English <-> Italian, English speech should create an EN card with English original and Italian translation; Italian speech should create an IT card with Italian original and English translation.
- Spoken output should be available, but it is not the default. Users need side-specific control because each speaker may or may not want the phone to speak the translation after their own utterances.

Decision:

- Starting an interpreter with a saved OpenAI credential opens the live screen in `listeningPaused`, connects the primary `/v1/realtime/translations` session in the background, and does not request microphone permission or start capture until the user taps `Resume Listening`.
- Pausing listening stops microphone capture and translated-audio playback, but keeps the realtime session warm when available. Resume reuses the warm session and only requests microphone permission/capture at that point.
- Each active `From` and `To` language card has an `Output voice` checkbox. Both checkboxes default off, persist with the recent language route, and are restored across sessions like the language pair.
- The checkbox on the side whose speaker just talked controls whether the app speaks that turn's translated text. In an English <-> Italian pair, checking English speaks the Italian translation after English speech; checking Italian speaks the English translation after Italian speech.
- The primary translated-audio path is enabled only for the selected side whose translation is produced by the primary realtime output language. The reverse audio-only session is enabled only when the opposite side's checkbox requires spoken output. Text transcript cards remain the single source of truth and still use direct OpenAI text fallback for reverse/text-only directions.

Implications:

- The active UI remains text-first by default while allowing intentional spoken translation output without reintroducing hidden global read-aloud controls.
- This adds no dependency, Android permission, backend route, app-owned network path, credential handling change, microphone recording persistence, or logging surface. The phone-only direct-OpenAI privacy boundary is unchanged.
- Regression coverage must include warm paused startup, pause/resume warm reuse, per-side checkbox persistence, English then Italian separate cards, and reverse-audio startup only when the matching side is checked.

## 2026-06-03 - Text-First Live Interpreter Suppresses Default Speaker And Reverse Audio

Status: Partially superseded by `2026-06-04 - Warm Paused Startup With Per-Side Spoken Output Opt-In`

Context:

- Tom's Samsung retest of the debug release showed the manual Italian <-> English screen, but accepting the microphone prompt could fall back to a `Preparing live session` screen, English speech produced an English-to-English assistant-like translation card instead of Italian, Italian speech did not reliably start a new source/translation card, and several unexpected translated-audio outputs played.
- The active live UI intentionally hides read-aloud controls and speaker/headphone chips, so enabling translated audio and the reverse realtime audio session by default was misleading and increased startup/audio failure surface.
- The live wire can provide enough source delta text to label the original speech before it provides a source completion event. Waiting only for `session.input_transcript.done` leaves English-in-English-output turns vulnerable to same-language realtime output before the direct text fallback fires.

Decision:

- Default the active phone live interpreter to text-first: at that point the legacy `_readAloudEnabled` flag started false, the main app did not enable the best-effort reverse audio session, and the coordinator skipped translated-audio playback queue startup whenever read-aloud was disabled. The 2026-06-04 decision supersedes the global flag with per-side `Output voice` checkboxes and opens reverse audio only for checked-side spoken output.
- Keep microphone capture and the primary `/v1/realtime/translations` text/transcript path active; only speaker playback/reverse audio are suppressed.
- Let stable source deltas (sentence-ending punctuation or long text) trigger the same direct OpenAI fallback used by completed source turns when the detected source language is already the primary realtime output language or the selected target requires direct fallback.
- Suppress no-item realtime output for a row once the direct text fallback has marked that row authoritative, so an English realtime echo cannot overwrite the Italian fallback translation.

Implications:

- The default tester build should be evaluated for original/translation text cards first. Audible translated output is now an explicit follow-up path, not a default release claim.
- This adds no dependency, Android permission, backend route, app-owned network path, credential handling, microphone recording, OpenAI request format change, or logging surface. The phone-only direct-OpenAI privacy boundary is unchanged.
- Regression coverage now includes the Samsung ordering: English source delta only, same-language realtime output, one EN original card, and Italian direct fallback translation.

## 2026-06-02 - Restore Manual Two-Language Pair Selection For Live Interpreter

Status: Accepted as code direction (Flutter analyzer/tests/APK build still need the Fedora toolchain)

Context:

- Tom's Samsung retest still did not reliably create new transcript boxes when the spoken language changed, and the issue is not limited to Italian.
- OpenAI's realtime translation path can auto-detect source language, but the app cannot rely on receiving per-turn language metadata early enough to safely drive the UI and bidirectional fallback routing for arbitrary language pairs.
- The previous issue #30 UI hid source/target pickers to avoid implying unsupported automatic spoken bidirectionality. That made the app brittle when language discovery did not converge on-device.

Decision:

- Restore explicit source and target language selectors in the active live interpreter surface. The default manual pair is Italian <-> English; users can pick any supported app source/target pair, and `Auto-detect` is no longer offered as a source choice in that manual picker.
- Treat the selected pair as the app's locked interpreter pair from session start. The coordinator seeds `BidirectionalInterpreterRuntime` with the selected pair and restarts cleanly when the pair changes within the same active meeting.
- Keep direction switching, `Translate Text`, read-aloud controls, speaker/headphone chips, live-header AI chat, and live-screen export controls hidden from the active live loop. The manual pair is bidirectional; users choose the two languages, not per-turn direction.
- Keep the dedicated `/v1/realtime/translations` network request broad-input and target-output only. The selected source code is app-side routing metadata and transcript commit context; the dedicated translation session still sets only `audio.output.language` plus required input transcription/noise-reduction config.

Implications:

- This reduces dependence on live language discovery for the header, reverse-session startup, and text fallback routing while preserving local language detection as a transcript-row fallback when OpenAI metadata is absent.
- No dependency, Android permission, backend route, app-owned network path, credential handling, microphone recording, or logging surface is added. The phone-only direct-OpenAI privacy boundary is unchanged.
- Product docs and regression checks now require visible source/target selectors in the active live interpreter and absence of only the secondary controls listed above.

## 2026-06-03 - Fallback-Only Targets Use The Realtime-Capable Paired Language For Audio

Status: Accepted as code direction (Flutter analyzer/tests/APK build still need the Fedora toolchain)

Context:

- The target picker intentionally shows all app target languages, including broader phone-only fallback targets.
- Arabic is source-supported and direct-fallback target-supported, but it is not one of the 13 documented Realtime Translation output languages.
- Before this fix, selecting a pair such as English <-> Arabic still configured the primary `/v1/realtime/translations` session with `audio.output.language = ar`, even though the UI labeled Arabic as a direct OpenAI fallback target.

Decision:

- Keep fallback-only targets selectable, but do not send unsupported realtime output languages to the dedicated realtime translation session.
- If the selected target supports realtime output, the primary realtime session outputs that selected target.
- If the selected target is fallback-only, the primary realtime session outputs the realtime-capable language on the other side of the pair, and the fallback-only direction uses the existing phone-only direct OpenAI text interpreter with `store: false`.
- Show a compact live route notice after the language selectors when the selected target is fallback-only.

Implications:

- English <-> Arabic starts realtime output in English, so Arabic speech can translate to English through realtime while English speech uses direct OpenAI text fallback to Arabic.
- This adds no dependency, Android permission, backend route, app-owned network path, credential handling, microphone recording, or logging surface.
- The installed-app physical microphone/audio proof for fallback-only target pairs remains under #6.

## 2026-06-02 - Split Source Cards On Supported-Language Changes Inside Continuous Samsung Streams

Status: Accepted as code direction (Flutter analyzer/tests/APK build still need the Fedora toolchain)

Context:

- Tom's Samsung retest showed one transcript card containing English, then Italian soccer speech (`Mi piace il calcio`, `Calcio e buono`), then English again. New boxes did not appear when the spoken language changed.
- The previous committer rule intentionally avoided translation-side rolling and split source rows only after source completion on the dedicated `/v1/realtime/translations` wire. That protected against sourceless translation cards, but it was too conservative when OpenAI streamed language changes inside one continuous source transcript before a completion boundary.
- The underlying product issue is not Italian-specific. If OpenAI does not emit language metadata, the app needs a local fallback that can segment the supported language set without logging or sending extra transcript content anywhere.

Decision:

- Add a shared, dependency-free local detector for the app's supported language set. It uses Unicode script ranges for Japanese, Chinese, Korean, Russian, Hindi, and Arabic, plus marker sets for English, Spanish, French, Italian, German, Portuguese, Indonesian, and Vietnamese.
- Keep source-delta language changes as a row boundary: supported-language deltas create separate cards even when no source completion event has arrived yet.
- When the committer has already split source cards, ignore a later cumulative source-completion transcript if it contains the current card text plus earlier segments, instead of overwriting the current card with the full mixed-language utterance and collapsing the UI back to one box.

Implications:

- This is local transcript segmentation only. It adds no dependency, Android permission, backend route, OpenAI request-format change, credential handling, microphone recording, or logging surface.
- The next physical-device debug APK should be built with `LIVE_TRANSLATE_DEBUG_EVENTS=true`; Tom's shared log contained no `LIVE_TX_EVENT` lines, so the raw wire recorder was either not enabled in that APK or not captured by the filter.

## 2026-06-01 - Two-Session Bidirectional Interpreter, Corrected Realtime Output Table, And Ground-Truth-First Live Debugging

Status: Accepted as code/design direction (Flutter analyzer/tests/APK build still need the Fedora toolchain; on-device EN+IT capture still pending)

Context:

- #31 was patched four times (PRs #46/#49/#50/#51 + follow-ups), each editing `RealtimeTranscriptCommitter` block-rolling, and Tom's physical-device retests kept failing in new ways (original speech missing, all text in one box, second language never detected). The root problem was not the committer logic: the agent loop had no live ground truth (the dev emulator has no audio source, #6), so every fix was verified against synthetic injected events whose shape was assumed, not observed.
- Re-checking the current OpenAI docs (Realtime Translation guide + cookbook, verified 2026-06-01) overturned two assumptions the prior design was built on:
  1. `gpt-realtime-translate` natively auto-detects the source language (70+ inputs) and emits `session.input_transcript.*` source events when `audio.input.transcription` is configured. Hand-rolled keyword language detection is therefore a fallback, not the primary mechanism.
  2. The documented two-party pattern is "two translation sessions, one per output language" ("A-to-B and B-to-A"), and Italian IS one of the 13 supported realtime output languages (Spanish, Portuguese, French, Japanese, Russian, Chinese, German, Korean, Hindi, Indonesian, Vietnamese, Italian, English). The single-session-output-English + English->Italian text-fallback design was fighting the API.

Decision:

- Ground truth first. Add a debug-only, content-free realtime wire-event recorder (`RealtimeEventDebugRecorder`, gated by `--dart-define=LIVE_TRANSLATE_DEBUG_EVENTS=true`) hooked at the raw socket-message boundary in `OpenAiRealtimeTranslationSession`. It logs only event type, JSON key names, payload lengths, language-code values, and item-id presence (never transcript/translation/audio content) as `LIVE_TX_EVENT` lines captured via `adb logcat`. Use it to confirm the real `/v1/realtime/translations` event shape on a physical device before further tuning committer/correlation logic.
- Correct the realtime output-language table in `language_support.dart` to the 13 documented output languages (adds Italian, German, Japanese, Chinese, Korean, Portuguese, Russian, Indonesian, Vietnamese, Hindi as realtime targets). Arabic stays a direct-OpenAI fallback target (it is an input language, not one of the 13 outputs). This supersedes the conservative "English/Spanish/French only" realtime table (`2026-05-24 - Conservative Realtime Language Table`) and the `2026-05-31 - Bidirectional Interpreter Uses Explicit Pair Direction With Text Fallback` claim that Italian realtime output is unproven.
- Implement the documented two-party pattern as an additive, best-effort reverse session. The primary `/v1/realtime/translations` session (output = first/default language, English) remains the single writer of transcript rows. Once the pair locks, `LiveRealtimeTranslationCoordinator` can open a SECOND dedicated translation session whose output language is the OTHER detected language, with `sourceTranscriptionEnabled: false` so it is audio-only and never writes a duplicate sourceless card. It is opt-in (`enableBidirectionalReverseSession`) and best-effort (a reverse-session failure never disturbs the primary path). The later 2026-06-03 text-first decision keeps this disabled from the main phone UI by default.
- Reverse-direction TEXT stays owned by the direct OpenAI text path, made principled: the text fallback now fires whenever a completed source turn's language equals the primary session's configured output language (the case where the single dedicated session stays silent because the speech is already in its output language) OR the target is a non-realtime-output language. This makes reverse-direction text appear reliably whether or not the reverse-audio session is up, and is independent of the corrected language table.

Rationale:

- The loop wasn't converging because it was debugging blind against an architecture that fought the API. Capturing one real session and adopting the documented two-session pattern addresses the actual cause instead of the fifth downstream symptom.
- Keeping reverse TEXT on the existing direct path (rather than correlating a second session's transcript without item ids) avoids fragile timing-based merging; the second session adds the missing reverse AUDIO without risking the transcript text path.

Implications:

- Phone-only direct-OpenAI privacy boundary is unchanged: two WebSocket sessions are still direct phone-to-OpenAI, no backend. Note the reverse session roughly doubles realtime translation minutes while the pair is active.
- This work was authored on a Windows machine with no Flutter/Dart toolchain, so `flutter analyze`/`flutter test`/APK build must run on the Fedora toolchain (as all prior validation has). The reverse-session correlation and committer behavior should be reconciled against the on-device `LIVE_TX_EVENT` capture; the fixture at `test/fixtures/realtime_translation_documented_turns.json` currently holds documented shapes and is the swap-in point for the real capture.
- #31 and #6 stay open until Tom confirms on a physical Android device that EN+IT shows original + translation per turn in both directions, boxes split per turn, and the header locks `English <-> Italian`.

## 2026-06-01 - Gate Readable-Block Rolling On Source-Utterance Completion, And Track Content-Free Source/Output Signal Evidence

Status: Partially superseded by `2026-06-02 - Restore Manual Two-Language Pair Selection For Live Interpreter`

Context:

- After PR #50 enabled input transcription, Tom's physical-device retest on 2026-06-01 showed the first card with original speech and translation (`EN` chip), but later cards reverted to `Original speech pending` with a `--` chip while still translating, and the second language was never detected.
- Root cause: `RealtimeTranscriptCommitter._shouldRollReadableBlock` marked a block ready to roll when the translated text crossed a sentence boundary or grew past a length threshold, even while the same continuous source utterance was still streaming. Source transcription lags the translation, so the next translation delta opened a new block with no source text; the continued translation orphaned onto a sourceless card and the coordinator never recorded that turn's source language, so the bidirectional header could not lock the second language.

Decision:

- On the dedicated `/v1/realtime/translations` wire (no item ids, no per-event language metadata), treat the completed source utterance as the only reliable turn boundary. On this wire `RealtimeTranscriptCommitter` never rolls a readable block on a translation event; a genuinely new source utterance is the sole reliable splitter that starts a new card. (Source and target transcripts stream on independent cadences, so once a turn's source has completed a later translation delta/done for the same turn has no new source to distinguish it from a new turn; rolling on it would orphan the continued translation onto a sourceless card. Item-id/language-code splitting for the primary realtime profile is unchanged.)
- Maintain content-free source/output transcript signal counters on the coordinator, expose a `transcriptSignalSnapshot` (source/output turn counts, sourceless-final count, and derived `hasSourcelessFinal`/`translationArrivedWithoutSource`), and emit a privacy-safe `live_realtime.translation_without_source` warning when a card finalizes with translated output but no original text. The release-checkable failure derivation is `hasSourcelessFinal == (sourcelessFinalCount > 0)`, and `translationArrivedWithoutSource` derives from it (plus the all-output/no-source case), so it catches the round-3 shape where the first card had source but a later card lost the original, not only the case where source never arrived at all. Because a turn's translation can finalize before its source on this wire, a translation-only finalization is only provisionally counted: if the SAME row later backfills original text, the count is reversed so a valid translation-first ordering leaves `sourcelessFinalCount == 0`, `hasSourcelessFinal == false`, and `translationArrivedWithoutSource == false`.
- Harden the live generated-speech smoke to count source (`session.input_transcript`) and output (`session.output_transcript`) transcript events separately and fail on translation-only output, so a release check can detect "translation arrived but original source never did."

Rationale:

- The fix is minimal and production-safe: it changes only block-boundary timing on the existing wired path, preserves source-label detection as a transcript-row fallback, and keeps original speech and its translation on one card for a continuous utterance.
- The signal counters and diagnostic give a deterministic, content-free way to detect the sourceless-final failure mode in tests and future smokes without storing transcript/translation content.

Implications:

- No dependency, Android permission, backend route, app-owned network path, live credential read, or microphone recording is added. The new diagnostic keys (`hasSourceSignal`, `hasOutputSignal`, `sourceTurnCount`, `outputTurnCount`, `sourcelessFinalCount`, `signalState`) are presence-only and allowlisted in `PrivacySafeDiagnostics`; transcript-bearing keys remain redacted.
- Regression coverage: a committer test reproduces the screenshot (2 cards, second sourceless) and proves the fix yields 1 card retaining original + full translation; a guard proves new utterances still split; coordinator tests prove the translation-without-source diagnostic/snapshot and second-language detection from later source; a diagnostics test proves the new keys are allowlisted, not redacted.
- The installed-app live-UI proof stays blocked behind #6 (no emulator audio source); #31 stays open until Tom confirms on a physical Android device.

## 2026-06-01 - Enable Source Input Transcription On The Realtime Translation Session, And Keep Debug-Signed Release APKs Out Of Tester Distribution

Status: Accepted

Context:

- Tom re-tested the installed app on 2026-06-01 after PR #49 and the original speech still never appeared; all recognized/translated text went into a single transcript box and the header stayed on `Heard English`. The release assets for `debug-20260601-a7a2743` contained two APKs: a 49 MB `release-debug-signed` build that "does not work at all" and a 168 MB plain debug build that runs but still showed the transcript bug.
- Root cause: the dedicated `/v1/realtime/translations` session config (`OpenAiRealtimeTranslationConfig._dedicatedTranslationSessionUpdate`) only set `audio.output.language` and never configured `audio.input.transcription`. The official OpenAI Realtime Translation guide and cookbook state that the source/original transcript (`session.input_transcript.delta`/`.done`) is emitted only when input transcription is configured. With no source events, the original speech could never display, and the committer's source-utterance block boundary never fired, so every translation delta appended to one block. PR #49's block-splitting/attribution fixes were correct but could not engage because their input — source events — never arrived; the test seams injected source events the live session never requested.

Decision:

- Configure input transcription on the dedicated translation session: `session.audio.input.transcription.model = gpt-realtime-whisper`, plus `session.audio.input.noise_reduction.type = near_field` per the official guide. Keep `audio.output.language` as the only language we set; source-language detection stays server-side. Do not send a model, instructions, or a source language on this endpoint (it rejects custom prompting/voice and detects source automatically).
- Keep the existing parser and committer behavior; they already handle `session.input_transcript.*`. The defect was purely the missing session input-transcription request.
- Keep a coordinator safety net: a completed translation with no source ever arriving must not finalize a sourceless row (it stays `partial`/`interrupted`), so a future config/endpoint regression degrades safely instead of presenting falsely complete turns.
- Do not distribute the debug-signed release APK (`release-debug-signed`) for installed device testing. It is a store-signing rehearsal artifact only until real local release-signing material exists (#24). The supported installed-test artifact is the debug APK. The artifact builder and `scripts/check_apk_metadata.sh` now print explicit tester guidance, and release notes/checklists must recommend only the debug APK to testers.

Rationale:

- Enabling input transcription is the minimal, production-safe, phone-only change that makes the source/original transcript and per-turn source boundaries arrive on the existing direct-OpenAI path, with no backend.
- The 49 MB release APK builds and boots to the bounded `OpenAI setup required` state on the emulator (offline release smoke passed), and carries the correct `INTERNET`/`RECORD_AUDIO` permissions, so the binary is not broken at the code level. Debug-signed builds presented as releases have repeatedly failed to install/run for testers (a debug-signed "release" is the kind of artifact device security such as Play Protect commonly blocks), so the safe action is to stop presenting it for testing rather than ship a confusing second artifact.

Implications:

- This changes the OpenAI realtime session request body for the dedicated translation profile (adds `audio.input.transcription` and `audio.input.noise_reduction`). It adds no dependency, Android permission, backend route, app-owned network path, live credential read, microphone recording, or logging/diagnostics surface, and preserves the phone-only direct-OpenAI privacy boundary. No transcript/audio/prompt/credential content is logged.
- Regression coverage: a session-config test asserts input transcription is configured (fails cleanly on main with a null source `input` block), a wire-level connect assertion proves the gateway sends the input-transcription request over the socket, and a coordinator regression proves output-only streams never finalize a sourceless row. The existing wired coordinator/full-app EN-then-IT block-split tests continue to prove two language-correct blocks once source events flow.
- The installed-app live-UI proof (a real credential reaching `Listening`, physical microphone capture, the EN/IT two-turn UI, and audible output) stays blocked behind #6 because this machine's emulator has no audio source. #31 stays open until Tom confirms on a physical Android device.

## 2026-06-01 - Live Block Splitting And Language Attribution For The Real Translation Wire Shape

Status: Accepted

Decision:

- Treat the live `/v1/realtime/translations` wire shape as authoritative: `session.input_transcript` (source) and `session.output_transcript` (translation) deltas can arrive with no item ids and no per-event language metadata, and source detection is automatic on OpenAI's side without a published language field.
- Drive transcript block splitting on the wired path from source-utterance boundaries: once the current block's source has completed, the next incoming source content always starts a new block. Do not require a realtime translation to be present on the block to roll, because a fallback turn's translated text is written separately.
- Never default an unresolved source language to the target language. An unknown source language stays neutral (`auto`) so the live header and per-row language chips do not collapse every turn to the target language.
- Resolve a short, distinctive foreign phrase from a single high-signal marker (for example `buongiorno`, `ciao`, `hola`, `bonjour`) while keeping the higher multi-marker threshold for English, whose markers are common function words. English-homograph markers (for example Italian `come`) are excluded from single-marker eligibility so an English-only phrase does not resolve to a foreign language at score 1.
- Make the runtime's detected-language ordering the single source of truth for the live header/status, falling back to stored-entry derivation only for resumed/historical meetings.

Rationale:

- Tom re-tested the installed app on 2026-06-01 and the prior #31 fix (proven only against the text-first/metadata-rich test seam) did not hold: a long English block kept "Original speech pending" while a later Italian turn's English translation merged into it, and the header stayed on "Heard English" instead of locking Italian/English.
- The previous block-split heuristic depended on translation text being present and on item ids/language metadata that the dedicated endpoint does not send, so it mis-bucketed source and translation and mislabeled every turn as the target language.
- Source-utterance boundaries and target-contrast-safe language attribution are deterministic against the real wire shape and keep the English-to-Italian direct fallback turn paired with its own block.

Implications:

- This is wired-path logic and test coverage only. It adds no dependency, Android permission, backend route, network path, OpenAI request format, live credential read, microphone recording, or logging surface change, and preserves the phone-only direct-OpenAI boundary.
- Regression coverage includes a wired coordinator test and a full-app widget test for the exact "English paragraph, then Italian phrase meaning Good morning, how are you?" scenario, plus committer unit tests for neutral unknown-language attribution and single-marker foreign-phrase resolution.
- The installed-app live-UI header/block proof remains blocked behind #6 because this machine's emulator has no audio source; this decision does not claim physical microphone or audible output validation.

## 2026-05-24 - Phone-Only MVP Architecture

Status: Accepted

Decision:

- Build an Android-first Flutter mobile app while keeping the project iOS-compatible later.
- Keep the MVP completely phone-only aside from direct OpenAI API calls.
- Do not include AWS API Gateway, Lambda, a token broker, app backend, cloud identity gate, cloud sync, server mailer, or server-side transcript handling in the MVP.
- Use the current accepted model-routing decision for live interpretation; as of 2026-05-26, normal MVP live human-speech interpretation uses `gpt-realtime-translate` on `/v1/realtime/translations`.
- Keep `gpt-realtime-2` as an explicit compatibility/experimental voice-agent profile.
- Store meetings, transcript/history, summaries, recipient preferences, sensitive preferences, and credential/session material only in encrypted local device storage for the MVP.
- Add local meeting management: start a new meeting, select an old meeting, and continue from it.
- Add scoped AI chat over `This meeting` or `All meetings`.
- Add user-initiated export support. The active MVP export UX is now superseded by `2026-05-25 - Generated Exports Stay In App Until Copy`.
- Treat cybersecurity as a first-class acceptance criterion.

Rationale:

- Phone-local operation minimizes backend privacy risk and keeps executive meeting transcripts away from app-owned infrastructure.
- Direct phone-to-OpenAI calls preserve the intended realtime product path without introducing a transcript/audio proxy.
- Local encrypted storage keeps the MVP privacy model simple and auditable.
- Explicit AI chat scope reduces accidental cross-meeting disclosure.
- In-app generated export copy avoids operating a server-side email relay for sensitive transcript data.

Implications:

- Any AWS, backend, cloud identity, or cloud sync proposal is V2/future until the source-of-truth docs and GitHub issues are updated.
- Implementation must verify endpoint behavior before changing model routing and keep GPT-5.5 `xhigh` reasoning for summary intent.
- Logs, diagnostics, analytics, crash reports, screenshots, and tests must avoid transcript, audio, prompt, summary, recipient, and credential/session leakage.
- Dependency/package hygiene, permission minimization, and supply-chain checks are required acceptance criteria.

## 2026-05-27 - MVP Defaults To Two-Party Text-First Interpreter

Status: Accepted

Decision:

- Redesign the active MVP live flow around a two-party interpreter rather than a user-selected source-to-target route.
- Phase 1 is text-first. As of 2026-06-02, the user manually selects the two-language pair and the app locks it from session start; transcript-row language labels still use OpenAI metadata or local detection when available.
- Keep startup gated by encrypted local OpenAI credential availability and microphone permission.
- Keep direction switching, read-aloud controls, and speaker/headphone chips hidden in the active live interpreter UI until spoken audio behavior is safely supportable. Source/target pickers are visible again under the 2026-06-02 manual-pair decision.
- Hide the `Translate Text` toggle, live-header AI chat launcher, and live-screen export controls from the active live interpreter UI so secondary workflows do not compete with interpretation.
- Preserve the phone-only direct OpenAI path, encrypted local transcript storage, privacy-safe diagnostics, and no-backend MVP boundary.

Rationale:

- A live interpreter should not require users to manually switch speakers or per-turn direction. The user now selects the two languages once.
- The app should not imply fully automatic bidirectional spoken audio before real audio support is validated.
- Text-first interpreter behavior can be tested through fakeable direct OpenAI seams with `store: false` while retaining existing realtime/audio seams for later validation.

Implications:

- Start surface copy uses `Start interpreter`.
- Live status now starts from the selected `<A> <-> <B>` pair.
- Tests and regression checklists should verify source/target pickers appear, while direction switch, `Translate Text` toggle, live-header AI chat, live-screen export controls, and read-aloud claims remain absent from the active interpreter flow.

## 2026-05-28 - Live Listening Pause Is Privacy-First

Status: Accepted

Decision:

- Add a `listeningPaused` state separate from `readAloudPaused`.
- `Pause Listening` stops microphone capture, the direct OpenAI realtime session, and translated-audio playback.
- Pausing preserves the active encrypted local meeting, transcript rows, detected language state, and resume target.
- `Resume Listening` reconnects with the active realtime config and transcript commit target.
- Startup must show a clear `Connecting to OpenAI` indicator before microphone capture starts.

Rationale:

- Users need a direct way to stop live capture without ending or deleting the meeting.
- Reusing read-aloud pause would imply only speaker output is paused while capture may continue, which is wrong for the privacy expectation.
- Slow realtime startup must not look like active recording before the phone has connected to OpenAI.

Implications:

- Tests should cover pause/resume resource teardown, transcript preservation, accessible pause/resume controls, and no regression of the simplified issue #30 interpreter UI.
- Paused listening must not add a backend, token broker, cloud sync, live smoke requirement, or logging of transcript/audio/credential material.

## 2026-05-31 - Bidirectional Interpreter Uses Explicit Pair Direction With Text Fallback

Status: Accepted

Decision:

- Track the detected interpreter pair as runtime state: first language, second distinct language, locked pair, and per-turn source-to-target direction.
- For a locked pair, each turn targets the other language in the pair rather than relying on the one configured realtime output language.
- Continue using the dedicated realtime translation session for validated realtime output targets such as English, Spanish, and French.
- Treat Italian as supported source and direct OpenAI text-fallback target until OpenAI realtime Italian output is proven by current documentation or live validation.
- For English/Italian, Italian speech can continue to target English through the realtime-capable route; English speech targets Italian through the phone-only direct OpenAI text fallback with `store: false`.
- Preserve the MVP network boundary: no app backend, AWS, Lambda, token broker, cloud sync, server-side transcript handling, or server-side fallback proxy.

Rationale:

- The dedicated `/v1/realtime/translations` session has one configured output language, so a single English-target session cannot honestly claim English-to-Italian realtime output.
- Explicit direction state makes pair lock testable and avoids silently translating every turn into the startup target language.
- A direct OpenAI text fallback keeps unsupported realtime targets inside the accepted phone-only credential and privacy model while avoiding unsupported spoken-audio claims.

Implications:

- Tests must prove English/Italian pair lock, English-to-Italian visible text fallback, Italian-to-English visible translation, route metadata, and no credential or payload leakage into diagnostics/backend paths.
- Future agents may widen Italian to realtime output only after source-of-truth docs or redacted live validation prove `gpt-realtime-translate` target support for Italian.
- This is a text-first fallback boundary; it does not prove bidirectional spoken audio or audible Italian output.

## 2026-05-31 - Live-Session Startup Is Fully Time-Bounded

Status: Accepted

Decision:

- Bound every post-connect live-session bring-up step in `LiveRealtimeTranslationCoordinator` (translated-audio playback start and microphone capture start) with a `startupStepTimeout`, in addition to the existing WebSocket `connectionTimeout`.
- Apply the same bound on the reconnect bring-up path, not only the first start.
- On a startup-step timeout, raise a sanitized `LiveRealtimeStartupTimeoutException` that flows through the existing realtime failure classification and bounded reconnect/backoff recovery, so the session leaves `connecting` for a visible `reconnecting`/`offline` state instead of stalling on `Preparing live session`.
- Keep the 2026-05-26 rule that startup still waits for `session.updated` or a sanitized startup error (within the connection timeout) before microphone capture starts.

Rationale:

- The post-connect playback and microphone starts were unbounded platform-channel calls. A hung native audio/microphone init could pin the session in `connecting` indefinitely with no recovery, error, or credential-invalid transition, which matched the #25 installed-app `Preparing live session` stall.
- The build spec requires bounded reconnect/backoff behavior and clear user-facing state during connecting/reconnecting/credential-invalid/error.

Implications:

- This is robustness hardening only. It does not prove live microphone translation, audible output, or accepted realtime auth, and it does not close #25 (accepted-credential blocker) or the #6 wired live-path proof.
- The startup-step timeout exception carries only a sanitized operation name; it never includes credential, transcript, audio, or translation content.
- Tests must prove a hung playback/microphone start leaves `connecting` for a bounded recovery state and that a persistently hung start terminates in a recovery state rather than stalling.

## 2026-05-24 - Direct OpenAI Credential And Model Preference

Status: Accepted

Decision:

- Proceed with direct phone-to-OpenAI API calls for the MVP.
- Do not add an MVP backend, AWS/Lambda token broker, or cloud identity gate.
- Use user-provided OpenAI credential/session material stored only in encrypted local device storage.
- Do not commit, bundle, or embed a standard OpenAI API key in mobile code, config, assets, tests, screenshots, or build outputs.
- Ask Tom for an OpenAI API key only when the app reaches the first real OpenAI network smoke/integration test.
- Use `gpt-realtime-translate` on `/v1/realtime/translations` for normal MVP live human-speech interpretation.
- Keep `gpt-realtime-2` as an explicit compatibility/experimental voice-agent profile.
- Use GPT-5.5 with `xhigh` reasoning intent for transcript summary generation.

Rationale:

- This preserves the phone-only MVP architecture while unblocking non-secret OpenAI integration scaffolding.
- Official OpenAI docs verified on 2026-05-26 list `gpt-realtime-2` as the voice-agent Realtime model and `gpt-realtime-translate` as the dedicated continuous streaming speech-translation model.
- Official Realtime client-secret docs still recommend server-minted ephemeral credentials for browser/mobile clients, but Tom accepted a phone-local user-provided credential path for MVP rather than introducing an app backend.

Implications:

- Credential UX, encrypted storage, redaction, reset/removal, and credential-invalid recovery are MVP implementation requirements.
- A real OpenAI network smoke test requires Tom to provide a key out-of-band or interactively at that point; no placeholder or real key belongs in the repo.
- Future changes that route live interpretation away from `gpt-realtime-translate` need a fresh accepted decision and must not add backend infrastructure.

## 2026-05-26 - Live Interpretation Uses Dedicated Realtime Translation Profile

Status: Accepted

Decision:

- Route normal MVP live meeting interpretation through `gpt-realtime-translate` on `/v1/realtime/translations`.
- Keep `gpt-realtime-2` configured only as an explicit compatibility/experimental profile for voice-agent or endpoint comparison work.
- Do not call `response.create` for the dedicated translation path; stream source PCM16 audio with `session.input_audio_buffer.append` and consume source/target transcript deltas as they arrive.
- Require only target/output language for the dedicated translation path. Keep live source language auto-detected, keep the From card display-only, and disable direction switching so source cannot become a fixed input language.
- Realtime startup must wait for `session.updated` or a sanitized startup error before microphone capture starts.
- Graceful stop should send `session.close`, wait briefly for `session.closed`, then fall back to immediate close.
- Keep original/source transcript text and translated text in separate local transcript fields.

Rationale:

- Current official OpenAI Realtime guidance identifies `gpt-realtime-translate` and `/v1/realtime/translations` as the continuous human-speech translation architecture.
- The standard `gpt-realtime-2` session is documented as the voice-agent path, with a different conversation/response lifecycle.
- Tom's installed-app report showed user-visible assistant-like behavior and missing original speech in the prior default route.
- Waiting for session readiness prevents early `session.updated` or startup `error` events from being dropped before the coordinator subscribes.

Implications:

- The 2026-05-25 `Runtime Realtime Sessions Prefer GPT Realtime 2` decision is superseded for normal live interpretation.
- Tests should prove the app default uses `dedicatedTranslation`, startup errors do not start capture, dedicated translation append messages remain credential-free, and source/translation transcript updates stay paired without transcript logging.
- This decision does not add a backend, token broker, cloud sync, bundled key, or server-side transcript handling.

## 2026-05-25 - Generated Exports Stay In App Until Copy

Status: Accepted

Decision:

- Replace the active MVP email-recipient/share-sheet export flow with in-app generated exports.
- Keep the Transcript/Summary/Both selector.
- Disable the active recipient list UI: no recipient input, checklist, example recipients, add-recipient controls, delete-recipient controls, or selected-recipient requirement.
- Generate exports in the background from the UI perspective and notify completion with an in-app action that opens the generated export detail view.
- Store generated export bodies only through encrypted local meeting storage.
- Expose plaintext export bodies only in the generated export detail view and the explicit user-triggered Copy action.

Rationale:

- Opening the share sheet after summary generation blocks too long for the meeting workflow.
- Executive-grade privacy requires generated exports to remain phone-local and encrypted until the user deliberately copies content out of the app.
- Keeping browsing/review inside the app avoids accidental external handoff through a mail/share target before the user is ready.

Implications:

- Native share/mail handoff can remain a later explicit user-initiated option, but it is no longer the primary MVP generation flow.
- Tests and diagnostics must avoid real generated export payloads and must not log export bodies.
- Future recipient or outbound delivery work remains deferred unless source-of-truth docs and issue scope are updated.

## 2026-05-25 - Target Picker Shows All App Languages

Status: Accepted

Decision:

- Keep the conservative realtime target table of English, Spanish, and French until current OpenAI documentation or live validation provides an authoritative broader realtime target enum.
- Show all app target languages in the target picker, including Japanese, German, Portuguese, Chinese, Korean, Arabic, and Hindi.
- Label realtime-supported targets separately from broader direct-OpenAI fallback targets.
- Keep fallback behavior phone-only and do not add AWS, an app backend, cloud sync, server-side transcript handling, or server mailer behavior.

Rationale:

- Users expect the target picker to expose the app's full language set, not only the currently conservative realtime subset.
- Explicit per-language labels avoid silently implying unsupported realtime output while keeping broader target choices discoverable.

Implications:

- `2026-05-24 - Conservative Realtime Language Table` still governs the realtime target table, but no longer means the target picker hides fallback-capable app languages.
- UI, tests, and regression checklists must verify both realtime labels and fallback labels.
- Selecting a fallback target must continue to surface the direct OpenAI fallback state instead of routing through app-owned backend infrastructure.

## 2026-05-25 - Runtime Realtime Sessions Prefer GPT Realtime 2

Status: Superseded by `2026-05-26 - Live Interpretation Uses Dedicated Realtime Translation Profile`

Decision:

- Route the installed app's live meeting runtime through the primary `gpt-realtime-2` profile when the selected language route is realtime-capable.
- Keep `gpt-realtime-translate` as the dedicated translation compatibility fallback/profile.
- Configure realtime input transcription with `gpt-realtime-whisper` so on-screen original speech updates from input transcription delta/completed events.
- Treat realtime model output as translation-only: selected target language only, no answers, no explanations, no continuation, no follow-up questions, and no filler.

Rationale:

- Tom's installed APK report showed assistant-like behavior and pending original speech. `gpt-realtime-2` is the stronger instruction-following realtime voice model, while `gpt-realtime-whisper` is intended for low-latency live transcript deltas.
- Hard translation-only session instructions reduce the chance that phrases such as "yellow what's going on" are interpreted as conversational prompts instead of text to translate.
- Preserving the dedicated translation profile keeps a narrow fallback if endpoint compatibility or live validation requires it.

Implications:

- Runtime event handling must keep input transcription text separate from translated output and use event item IDs to update the correct transcript block.
- The dedicated translation endpoint remains available for compatibility testing and fallback, but the app's normal realtime-capable path should start with `gpt-realtime-2`.

## 2026-05-24 - Initial MVP Architecture

Status: Superseded by `2026-05-24 - Phone-Only MVP Architecture`

Decision:

- Build an Android-first Flutter mobile app while keeping the project iOS-compatible later.
- Use AWS API Gateway + Lambda only as a token broker.
- Keep the standard OpenAI API key in backend secret storage/config only.
- Have the mobile app connect directly to OpenAI with short-lived client secrets.
- Use `gpt-realtime-translate` as the primary live translation model.
- Store transcript history only in encrypted local device storage for the MVP.
- Support Microsoft personal, Microsoft work/school organizational, and Google sign-in.

Rationale:

- This was the first planning baseline. It has been retained for provenance only.

Implications:

- Token broker, AWS, and Google/Microsoft sign-in work is now V2/future scope. See [docs/v2-future-scope.md](v2-future-scope.md).

## 2026-05-24 - Supplied Mockups Are First-Pass UI Source

Status: Accepted with phone-only MVP adaptation

Decision:

- Treat the four supplied 720x1280 Android portrait JPGs in [assets/mockups](../assets/mockups) and [docs/mockup-ux-spec.md](mockup-ux-spec.md) as the visual source of truth for the first Flutter implementation.
- Adapt cloud sign-in affordances to phone-local setup/start-meeting behavior for MVP unless a future accepted decision restores cloud identity.

Rationale:

- The mockups define the expected product feel, required first-pass surfaces, labels, states, and interaction hierarchy more concretely than a generic design-system description.
- The product architecture changed after mockup intake, so sign-in-specific behavior must not override the phone-only MVP decision.

Implications:

- UI work must inspect the images before implementation.
- Any intentional drift from the mockups must update [docs/mockup-ux-spec.md](mockup-ux-spec.md) or this decision log, depending on whether interpretation or product direction changed.

## 2026-05-24 - Conservative Realtime Language Table

Status: Accepted

Decision:

- Keep a typed, centralized language support table in the Flutter app.
- Show only English, Spanish, and French as default realtime target languages until OpenAI publishes or exposes an authoritative Realtime Translation target-language enum.
- Treat broader targets such as Japanese as direct-OpenAI fallback-pending, not as confirmed realtime targets.
- Keep fallback routing phone-only and do not add AWS, app backend, cloud sync, server-side transcript handling, or server mailer behavior.

Rationale:

- Official OpenAI docs verified on 2026-05-24 confirm `gpt-realtime-translate`, `/v1/realtime/translations`, one session per target output language, and an `audio.output.language` parameter, but do not publish a target-language enum.
- A conservative table avoids silently offering unverified realtime output targets while preserving a clear path for product-approved fallback.

Implications:

- Future implementation can widen the realtime target table only after current OpenAI docs, API metadata, or live API validation provides stronger evidence.
- Unsupported target UI should make fallback state visible and should stay direct phone-to-OpenAI using the accepted encrypted local credential/session approach.

## 2026-05-24 - Android PCM16 Capture Uses App-Owned Platform Code

Status: Accepted

Decision:

- Implement the first Android microphone capture increment with app-owned native `AudioRecord` code behind a fakeable Flutter EventChannel/MethodChannel seam.
- Emit 24 kHz mono PCM16 chunks for the OpenAI realtime WebSocket path.
- Do not add a Flutter audio recording package for this increment.
- Keep capture closed until both the encrypted local OpenAI credential and runtime microphone permission gates pass.
- Route microphone streaming through the dedicated `gpt-realtime-translate` profile for now because official OpenAI docs identify it as the live human-speech translation endpoint; the primary `gpt-realtime-2` profile remains available for follow-up spoken-translation validation.

Rationale:

- The existing Android platform channel layer already owns microphone permission and keeps the supply-chain surface smaller than adding an audio dependency.
- OpenAI's current translation client-event docs describe 24 kHz PCM16 mono little-endian raw audio and 200 ms chunks for WebSocket translation sessions.
- A fakeable capture gateway lets tests prove credential/permission gating and chunk flow without recording microphone audio or using a live credential.
- The primary Realtime 2 session remains configured, no-audio session creation passes, and a redacted live smoke accepts a 200 ms non-speech PCM16 append after the session output audio format includes an explicit 24 kHz rate, but this does not prove live spoken translation.

Implications:

- Future audio package, SDK, resampling, or playback additions must update the cybersecurity report and rerun supply-chain checks.
- At this capture slice, real microphone translation smoke, native translated-audio speaker output, and live transcript validation remained open #6/#14 work; Android speaker output is now covered by the later `AudioTrack` decision below.

## 2026-05-24 - Generated Speech Smoke Validates Endpoint Events Only

Status: Accepted

Decision:

- Extend the redacted live OpenAI smoke harness with a local generated-spoken-audio check for the dedicated `gpt-realtime-translate` profile.
- Generate a short Spanish phrase locally with `espeak-ng`, convert the stdout WAV to 24 kHz mono PCM16 in process memory, and stream it directly to `/v1/realtime/translations` in 200 ms chunks.
- Treat the smoke as passing only when transcript and translated-audio events arrive.
- Report only event counts, model, and endpoint path. Do not print transcript text, audio bytes, generated audio payloads, credential material, or response bodies.
- Do not treat this as proof of Android physical microphone capture, Android speaker audibility, live reconnect recovery, or primary `gpt-realtime-2` spoken translation behavior.

Rationale:

- The emulator workflow still lacks a reliable microphone injection command, so local generated speech is the safest repeatable way to validate actual spoken PCM16 behavior against the dedicated translation endpoint without storing a live key in the emulator.
- Keeping audio generation local avoids adding an OpenAI TTS dependency or committing audio fixtures.
- The harness exercises the same PCM16 WebSocket append path used by the app while preserving the phone-only privacy and secret-handling boundary.

Implications:

- #6 is advanced because the dedicated translation endpoint has now returned transcript and translated-audio events from spoken input, not just accepted append schema.
- #6 remains open for physical microphone translation smoke and audible Android speaker validation.
- #14 remains open for live reconnect, credential-expiry, and transcript de-duplication behavior under real streaming.

## 2026-05-24 - Controlled Generated Speech Reconnect Smoke Validates Endpoint Recovery

Status: Accepted

Decision:

- Extend the redacted live OpenAI smoke harness with a controlled reconnect check for the dedicated `gpt-realtime-translate` profile.
- Reuse local `espeak-ng` generated Spanish speech and keep generated WAV/PCM bytes in process memory only.
- Open one live dedicated translation WebSocket, wait for session readiness, stream a small number of generated-speech chunks, intentionally close that socket, open a second live session, stream generated speech again, and pass only when transcript plus translated-audio events arrive from the recovered session.
- Report only controlled reconnect count, chunk count, event counts, model, and endpoint path. Do not print transcript text, audio bytes, generated audio payloads, credential material, response bodies, or raw socket messages.
- Treat this as live endpoint/harness recovery evidence only. Do not treat it as proof of Android physical microphone capture, installed-app transcript persistence, app-coordinator de-duplication, credential-expiry recovery, Android speaker audibility, or primary `gpt-realtime-2` spoken translation behavior.

Rationale:

- The generated-speech harness gives #14 a repeatable live streaming input source without emulator microphone injection or storing a live key in app/emulator data.
- A deliberate socket close plus a second successful live session narrows the remaining reconnect risk while preserving the phone-only privacy boundary.
- Keeping the check in the redacted host smoke avoids adding package dependencies, backend routes, committed fixtures, or mobile permissions.

Implications:

- #14 is advanced because a controlled live socket interruption can recover transcript and translated-audio evidence through the dedicated translation endpoint.
- #14 remains open for app-coordinator reconnect de-duplication, credential-expiry/network-drop/rate-limit recovery, and audible Android output recovery under live streaming.
- #6 remains open for physical microphone translation smoke and installed-app committed transcript validation from live speech.

## 2026-05-24 - Translated Audio Playback Starts As A Fakeable Local Queue

Status: Accepted as first slice; Android production output added by `2026-05-24 - Android Translated Audio Output Uses App-Owned AudioTrack`

Decision:

- Decode OpenAI realtime translated-audio deltas into PCM16 chunks inside the phone app.
- Send decoded chunks only to a local `TranslatedAudioPlaybackGateway` seam.
- Keep the first production gateway as a no-op placeholder that does not retain audio-derived data.
- Start the playback gateway only after credential, microphone permission, and realtime connection gates pass.
- Stop and clear playback resources during reconnecting, offline, credential-invalid, backgrounded, stopped, and failed reconnect states.
- Do not add an audio playback package, native speaker output engine, backend relay, logging sink, or extra Android permission in this software-only first slice.

Rationale:

- The fakeable gateway lets tests prove decoded translated-audio routing and reconnect teardown/restart behavior without requiring a physical speaker path or controllable microphone source.
- Keeping audio-derived payloads in transient memory only preserved the phone-only privacy boundary while this first slice left native output unimplemented.
- A no-dependency seam keeps supply-chain risk low until the app is ready for a focused Android/iOS audio-output implementation.

Implications:

- This first slice intentionally left native speaker output open; Android output is now covered by the later `AudioTrack` decision below.
- Diagnostics around playback must remain limited to sanitized operation/result/error labels and must never include audio bytes, base64 chunks, transcript text, translated text, or credentials.

## 2026-05-24 - Android Translated Audio Output Uses App-Owned AudioTrack

Status: Accepted

Decision:

- Implement the first native translated-audio output increment with app-owned Android `AudioTrack` stream-mode code behind the existing fakeable `TranslatedAudioPlaybackGateway`.
- Keep the Flutter gateway fakeable, and keep the no-op gateway available for tests and non-Android shells.
- Accept mono PCM16 chunks only when their sample rate and channel count match the opened playback stream.
- Keep decoded output audio in transient memory only through a bounded native queue, dropping oldest queued chunks if the queue fills.
- Close and clear playback during reconnecting, offline, credential-invalid, backgrounded, stopped, and failed reconnect paths.
- Do not add a playback package, external SDK, backend relay, logging sink, persistent audio store, or extra Android permission for this increment.

Rationale:

- The existing platform-channel layer already owns Android audio capture and can add output without widening the dependency or permission surface.
- `AudioTrack` gives the MVP a direct Android speaker path while preserving the phone-only architecture and fakeable Dart test boundary.
- A bounded transient queue avoids unbounded retention of audio-derived payloads and fits the current skip-to-live/reconnect direction.

Implications:

- Real audible translated-audio validation still requires a real streaming session or controllable translated-audio source; do not claim spoken end-to-end translation from fake PCM16 queue tests.
- Future iOS output must stay behind the same gateway and receive equivalent privacy/security review.
- Any future playback package, resampler, audio effects SDK, route-management permission, or persisted audio cache must update the cybersecurity report and rerun supply-chain checks.

## 2026-05-24 - Debug Installed-App Generated Event Proof

Status: Accepted

Decision:

- Add an opt-in installed-app proof that is available only in debug builds compiled with `--dart-define=LIVE_TRANSLATE_DEBUG_E2E=true`.
- Drive generated-speech-shaped realtime transcript/audio events through the app coordinator, simulate playback teardown/restart, verify exactly one new realtime transcript row plus one recovered audio chunk through sanitized UI text, restart the app, verify the generated row persists in encrypted meeting history, reopen the meeting, and verify `This meeting` AI context sees the persisted local transcript count.
- Keep the proof absent from normal debug builds, absent from release UI through `kDebugMode`, and guarded in the coordinator by an assert-enabled runtime check.
- Treat this as coordinator/storage/playback validation only, not as live OpenAI, physical microphone, or audible speaker evidence.

Rationale:

- The current `android-pixel9-headless` launcher hardcodes `-no-audio`, while the Android emulator exposes host microphone passthrough through `-allow-host-audio` but not a reliable documented generated WAV/PCM microphone injection path.
- The debug proof gives the installed APK a repeatable E2E check for transcript de-duplication, playback recovery, encrypted history persistence after process restart, and local AI-context visibility without storing audio fixtures, printing payloads, adding packages, or adding a production backdoor.

Implications:

- #6/#14 still need physical microphone/live speech validation and audible speaker validation on a real device, a host-audio emulator launcher variant, or a controllable virtual audio device.
- Future agents must not present `--debug-live-events` as live OpenAI or microphone evidence.

## 2026-05-24 - Host-Audio Emulator Target For Live Audio Validation

Status: Accepted as a validation path, not product evidence

Decision:

- Add `scripts/android_pixel9_host_audio.sh` as the repo-local `Pixel_9_API_36_Play` launcher for live #6/#14 audio validation attempts.
- Launch that emulator with `-allow-host-audio` and without `-no-audio`.
- Make `scripts/android_emulator_e2e.sh --require-device-audio` use the repo-local host-audio launcher when no Android device is already connected.
- Keep the no-audio guard strict: physical Android devices pass the target preflight, but emulators must expose process arguments containing `-allow-host-audio` and must not include `-no-audio`.

Rationale:

- Tom's global `android-pixel9-headless` helper remains the standard no-window emulator for non-audio Android checks, but it hardcodes `-no-audio`.
- The repo needs a concrete, testable target before any physical microphone or audible speaker validation claim can be made.
- Requiring `-allow-host-audio` avoids treating an unspecified emulator launch as audio-capable while preserving a physical-device path.

Implications:

- Passing `--require-device-audio --audio-preflight-only` proves target readiness only. It does not prove microphone capture, translated-audio audibility, installed-app live transcript persistence, or realtime reconnect behavior.
- If the host-audio emulator cannot produce usable microphone/speaker evidence in practice, #6/#14 should use a physical Android device or a documented controllable virtual audio route rather than weakening the guard.

## 2026-05-31 - Repeatable Local Android Release Smoke (#39)

Status: Accepted

Decision:

- Add `scripts/android_release_smoke.sh` as the repeatable Android release smoke entrypoint: build/locate an APK (debug by default, `--release` for a release artifact), run an APK metadata + signing preflight, cold-boot the emulator resiliently, install, clear app state, launch, and prove startup reaches a bounded state.
- Extract the emulator cold boot into a shared helper `scripts/lib/android_emulator_boot.sh` with reuse-online-device, bounded retries, an AVD-scoped process watchdog, `adb` device-state checks, conservative stale-lock cleanup, and per-attempt log tails. Source it from `scripts/android_emulator_e2e.sh`, replacing the previous single-shot launch plus unbounded `adb wait-for-device`.
- Add `scripts/check_apk_metadata.sh` to verify SHA-256 sidecar, package id, version metadata, and a least-privilege permission allowlist, and to report debug vs release signing without failing a debug release.
- Make the default release smoke truly offline. Prove the bounded startup state with `scripts/android_emulator_e2e.sh --verify-offline-startup`: with no credential saved, the live coordinator returns `missingCredential` before any network call, microphone-permission request, or OpenAI request, so the app reaches the `OpenAI setup required` gate, and the proof asserts the UI never remains on `Preparing live session`. The default path reads no credential and makes no OpenAI network request.
- Keep invalid-credential auth-rejection recovery as an explicit opt-in (`--verify-invalid-credential-recovery`) that makes a live OpenAI auth-rejection network request using a non-secret placeholder credential, and live realtime validation as a separate opt-in (`--with-live-credential`) that reads the local secret. Document both as network paths.
- Keep Android emulator smoke local-only. CI stays Flutter-only (`flutter pub get`, `flutter analyze`, `flutter test`, supply-chain), and docs (`bash scripts/check-docs.sh`).
- Make GitHub result recording opt-in: print a sanitized result block by default, and post to a release (`--record-to-release`) or issue (`--record-to-issue`) via `gh` only when asked, after a secret-pattern guard.

Rationale:

- The 2026-05-31 debug release could not complete install/run validation because `Pixel_9_API_36_Play` repeatedly died during cold boot before stable `adb`, and the single-shot boot path either hung or failed without a repeatable outcome.
- A flaky cold boot should not block every release. Bounded retries plus a watchdog convert a hang into a fast, deterministic pass or fail.
- Validating an APK on the default path must not contact OpenAI at all. With no credential saved the app fails closed at the setup gate before any network, which is a genuine bounded-state proof and is safe on machines with no OpenAI key. Exercising the connecting phase through an auth rejection is still useful but is a network request, so it must be an explicit opt-in rather than the default.
- A GitHub-hosted emulator job (for example `reactivecircus/android-emulator-runner`) was considered and rejected for the MVP: it is historically flaky, adds CI surface, and contradicts the existing local/manual emulator stance.

Implications:

- Releases should run `scripts/android_release_smoke.sh` (or `scripts/final_qa_gate.sh --release-smoke`) and record the sanitized result in release notes or an issue comment.
- If the emulator cannot cold-boot on the host, the smoke fails fast with a captured log tail; fall back to a physical device or an attached emulator rather than weakening the boot checks.
- The default smoke path must never read an OpenAI credential, make any OpenAI network request, or print credential/transcript/audio/summary/export payloads. Any auth-rejection or live validation must stay behind the explicit opt-in flags.
- The boot helper must only stop emulator processes whose arguments name `Pixel_9_API_36_Play`, and must continue to avoid `emulator -no-window` on this Fedora/Wayland host.

Revision (2026-05-31): An initial implementation made the default path run `--verify-invalid-credential-recovery`, which saves a placeholder credential and waits for an OpenAI auth rejection. A max-model solution-architect review of PR #40 flagged that this is a live OpenAI request and violates the stated default boundary. The default was corrected to the offline `--verify-offline-startup` proof above, and the auth-rejection recovery moved behind the explicit opt-in flag.

## 2026-05-31 - Release Builds Declare INTERNET And The Metadata Gate Requires Product-Critical Permissions (#41)

Status: Accepted

Decision:

- Declare `android.permission.INTERNET` in `android/app/src/main/AndroidManifest.xml` alongside `android.permission.RECORD_AUDIO`, so release/store builds keep the permission instead of relying on the Flutter debug/profile manifest overlay that only applies to debug and profile builds.
- Treat `RECORD_AUDIO` + `INTERNET` as the exact least-privilege permission set for the phone-only MVP; the only other entry expected in a built APK is the AndroidX `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` self-scoped signature permission.
- Strengthen the release metadata gate (`scripts/check_apk_metadata.sh`) so that, in addition to rejecting permissions outside the allowlist, it now fails when either product-critical permission (`RECORD_AUDIO`, `INTERNET`) is absent from the built APK. The dynamic-receiver permission stays allowed but not required.
- Strengthen the source-level supply-chain gate (`scripts/check-supply-chain.py`) to add `INTERNET` to the allowlist and require both `RECORD_AUDIO` and `INTERNET` in the source main manifest, so the regression is caught in CI before any APK is built.

Rationale:

- The repeatable release smoke (#39) surfaced that a fresh release APK requested only `RECORD_AUDIO` (plus the dynamic-receiver permission); `INTERNET` was declared only in the debug and profile manifests.
- The MVP's only routine network path is direct phone-to-OpenAI HTTPS/WebSocket calls. A release build without `INTERNET` cannot perform realtime translation, scoped AI chat, summary generation, or export generation, even though debug/emulator builds work.
- The offline default release smoke fails closed at the `OpenAI setup required` gate before any network call, so the gap was invisible to the bounded-state proof and only showed up in the permission list. Encoding the requirement in both the source gate (CI-cheap) and the APK gate (artifact-true) prevents the regression from recurring.

Implications:

- This is a least-privilege-preserving fix: it adds exactly one already-needed permission and adds no backend, AWS, token broker, cloud sync, or server-side transcript path. The phone-only direct-OpenAI boundary is unchanged.
- Docs that describe release smoke or permissions (README, testing strategy, regression checklist, environment, cybersecurity report) state that `INTERNET` is declared in the main manifest and required by both gates.
- A real release/store build still depends on store-ready signing (#24) and a fresh max-model architecture review; this change does not create or publish a release.
