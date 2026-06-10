# Live Translate Build Spec

This is the canonical build spec for the Realtime Translate Mobile repo. Future implementation, issue triage, README updates, and UI work should use this document as the first source of truth.

## Product Goal

Build an Android-first, iOS-compatible Flutter app for a two-party live interpreter using direct Gemini Live Translate for the live speech runtime plus direct OpenAI Responses calls for AI chat, summaries, and approved text fallback. Phase 1 of the revised MVP is text-first: the user selects the two languages in use, the app treats that pair as locked from session start, and transcript rows still use Gemini transcript metadata or deterministic local detection for per-turn source labels when available. Fully automatic bidirectional spoken audio is not claimed in the active UI until it is safely validated. The MVP is phone-only except for direct Gemini/OpenAI API calls. It should feel premium, clean, and executive-grade, with live interpretation and meeting history as usable product surfaces rather than a technical dashboard.

## Fixed MVP Decisions

| Area | Decision |
| --- | --- |
| Mobile framework | Flutter |
| Platform order | Android first, iOS-compatible later |
| MVP backend | None |
| Routine network path | Phone app connects directly to Gemini Live Translate for live translation and directly to OpenAI Responses for AI chat, summaries, and approved text fallback |
| Live model | Use Gemini Live Translate preview model `gemini-3.5-live-translate-preview` for MVP live human-speech interpretation; keep OpenAI realtime translation code only as an explicit compatibility/fallback seam |
| AI chat | Direct OpenAI path scoped explicitly to `This meeting` or `All meetings` |
| Storage | Encrypted local device storage only |
| Meetings | Local meeting history, transcript/history, and summary metadata stored on phone |
| Generated exports | In-app Transcript/Summary/Both export generation, encrypted local storage, explicit in-app Copy action; no outbound mail backend |
| Cloud/backend/auth scope | Deferred to [docs/v2-future-scope.md](v2-future-scope.md) |
| Mockups | Supplied Android mockups in `assets/mockups/`, interpreted through [docs/mockup-ux-spec.md](mockup-ux-spec.md) |

## Source Documents And Assets

- README and repo status: [README.md](../README.md)
- Agent operating instructions: [AGENTS.md](../AGENTS.md)
- UX interpretation: [docs/mockup-ux-spec.md](mockup-ux-spec.md)
- High-level product spec: [docs/product-spec.md](product-spec.md)
- Architecture handoff: [docs/architecture.md](architecture.md)
- V2/future scope: [docs/v2-future-scope.md](v2-future-scope.md)
- Cybersecurity report: [docs/cybersecurity-report.md](cybersecurity-report.md)
- Privacy-safe diagnostics: [docs/privacy-safe-diagnostics.md](privacy-safe-diagnostics.md)
- Development workflow: [docs/development-workflow.md](development-workflow.md)
- Environment setup: [docs/environment.md](environment.md)
- Testing strategy: [docs/testing-strategy.md](testing-strategy.md)
- Decision log: [docs/decision-log.md](decision-log.md)
- Starter prompt for first implementation: [docs/codex-starter-prompt.md](codex-starter-prompt.md)

Supplied mockups:

- [assets/mockups/01-live-listening-teal.jpg](../assets/mockups/01-live-listening-teal.jpg)
- [assets/mockups/02-transcript-assistant.jpg](../assets/mockups/02-transcript-assistant.jpg)
- [assets/mockups/03-welcome-local-setup.jpg](../assets/mockups/03-welcome-local-setup.jpg)
- [assets/mockups/04-speaking-paused-amber.jpg](../assets/mockups/04-speaking-paused-amber.jpg)

## MVP User Flow

1. User opens the app and sees a premium phone-local welcome/start surface.
2. User taps `Start interpreter` or selects an old local meeting and continues from it.
3. App gates live startup on encrypted local Gemini credential availability and Android microphone permission. AI chat, summaries, and direct text fallback separately require encrypted local OpenAI credential availability.
4. Live interpreter opens with visible `From` and `To` language selectors for the two-language pair, defaulting to Italian <-> English, plus no direction switch, no `Translate Text` toggle, no live-header AI chat launcher, and no live-screen export controls.
5. The status card shows the selected pair as `<A> <-> <B>` from session start. Source-row language chips may still come from Gemini transcript metadata or deterministic local detection.
6. Subsequent turns stream through Gemini Live Translate using 16 kHz mono PCM16 input chunks and map Gemini input/output transcripts into transcript rows with pending/detected/translating/final states. Approved text fallback remains direct OpenAI Responses with `store: false`.
7. User can change either selected language during the active meeting; the app persists the new pair locally and restarts the direct Gemini live session with the updated target language.
8. App stores meeting transcript/history/summary metadata in encrypted local device storage.
9. User can open AI chat from a meeting with `This meeting` scope or from a global/history surface with `All meetings` scope.
10. User can generate Transcript, Summary, or Both as an encrypted local export, continue browsing while generation runs, review generated exports in app, and explicitly copy an export when ready.

## Mobile App Requirements

- Scaffold a Flutter project that builds for Android now and does not block iOS later.
- Keep platform-specific code isolated behind clear interfaces.
- Use Android runtime microphone permission flows before recording.
- Never start recording before explicit permission is granted.
- Handle permission denied, permanently denied, and permission revoked states.
- Model live session state explicitly, including at least:
  - `localSetup`
  - `meetingSelection`
  - `connecting`
  - `listening`
  - `listeningPaused`
  - `speaking`
  - `readAloudPaused`
  - `reconnecting`
  - `offline`
  - `credentialInvalid`
  - `error`
- Handle app lifecycle transitions such as backgrounding, foregrounding, audio focus changes, headset/speaker route changes, network loss, and session teardown.
- Keep transcript rows structured by meeting ID, language, original text, translated text, timestamp, speaker ownership, confidence/status, accent, and playback state.
- Store preferences, recent languages, meetings, transcript history, summary metadata, remembered export recipients, and last selected recipients locally with encryption.
- Provide retention and delete controls for meeting and transcript history.
- Do not add app backend, AWS, server-side transcript handling, or cloud transcript sync in the MVP.

## UI Requirements

Use [docs/mockup-ux-spec.md](mockup-ux-spec.md) and the four image files as the visual source of truth. The revised MVP should adapt any cloud sign-in affordances into phone-local setup/start-meeting controls unless a future decision restores cloud identity to MVP scope.

Required first-pass surfaces:

- Welcome/local setup screen.
- Meeting history or meeting selector entry point.
- Main live translation screen in teal listening mode.
- Scoped AI chat bottom sheet over a dimmed live screen.
- Main live translation screen in amber speaking/read-aloud-paused mode.
- Generated export sheet/dialog with Transcript/Summary/Both selector and generated export browser/detail views.

Required UI foundations:

- Small design token layer for colors, spacing, radii, typography, shadows/elevation, and state colors.
- Reusable components for app shell, header, status card, language selectors, direction switch, feature toggles, transcript cards, queue banner, jump-to-live chip, bottom controls, local setup actions, meeting selector/history rows, AI chat sheet, prompt chips, input, generated export controls, generated export browser/detail views, and privacy notes.
- Safe-area handling for Android status/navigation bars.
- Bottom transcript padding equal to fixed controls plus safe-area inset.
- Large-text and small-device handling so labels, buttons, transcript rows, export controls, and bottom controls do not overlap or clip.
- Semantic labels for icon-only controls and accessibility coverage for local setup, meeting management, live controls, language selection, playback, AI chat, export, and transcript actions.

## No MVP Backend

The MVP must not include an app backend.

- Do not add AWS API Gateway, Lambda, token broker endpoints, backend auth validation, backend-held OpenAI keys, server mailers, cloud transcript storage, or cloud sync.
- Do not send transcript text, translated text, prompts, microphone audio, audio chunks, audio-derived payloads, summaries, recipient lists, or meeting metadata to an app-owned backend.
- If a future backend is introduced, it must be treated as V2/future scope and reconciled through [docs/v2-future-scope.md](v2-future-scope.md), [docs/decision-log.md](decision-log.md), and the GitHub issue map before implementation.

## Gemini Live Translation Requirements

- Use `gemini-3.5-live-translate-preview` through the Gemini Live API raw WebSocket path for normal MVP live human-speech interpretation.
- Connect from the phone app directly to Gemini. Do not add an app backend, token broker, AWS, cloud sync, or server-side transcript handling.
- Store user-provided Gemini credential/session material only in encrypted local device storage, separately from OpenAI credential material, and never bundle, hard-code, log, screenshot, or commit it.
- Send the documented setup message with `setup.model = models/gemini-3.5-live-translate-preview`, `generationConfig.responseModalities = ["AUDIO"]`, `inputAudioTranscription = {}`, `outputAudioTranscription = {}`, and `translationConfig.targetLanguageCode` set to the selected target output language.
- Stream raw little-endian mono PCM16 microphone audio as `realtimeInput.audio` with `mimeType: audio/pcm;rate=16000` in 100 ms chunks.
- Parse `serverContent.inputTranscription` as source/original transcript, `serverContent.outputTranscription` as translated transcript, and `serverContent.modelTurn.parts[].inlineData` as translated PCM16 audio output. Output audio is 24 kHz mono PCM16.
- Keep `echoTargetLanguage: true` unless a later accepted decision changes how same-target speech should be handled.
- Recover from direct credential/session expiry, network drops, transient Gemini errors, and app lifecycle interruption with bounded reconnect/backoff behavior.
- Keep user-facing state clear during connecting, reconnecting, credential-invalid, unsupported-language, offline, permission-denied, rate-limit, and model/API error states.
- Ask Tom for a Gemini API key only at the first real Gemini network smoke/integration test.

## OpenAI Requirements

- Keep OpenAI Responses paths for AI chat, summaries, and approved text fallback. Use `store: false` for request paths that send meeting context or transcript-derived content.
- Keep `gpt-realtime-translate` and `gpt-realtime-2` code available only as explicit compatibility/fallback seams; do not use either as the default live meeting route unless a later accepted decision changes this.
- Configure `audio.input.transcription` (model `gpt-realtime-whisper`) and `audio.input.noise_reduction` (`near_field`) on the dedicated `/v1/realtime/translations` session so the endpoint emits the source/original transcript (`session.input_transcript.delta`/`.done`). Without input transcription the endpoint streams only translated audio and `session.output_transcript`, so the original speech cannot display and turns cannot split. Set only `audio.output.language`; do not send a model, instructions, or a source language on this endpoint.
- Receive translated audio and transcript deltas while the speaker is still talking.
- Recover from direct credential/session expiry, network drops, transient OpenAI errors, and app lifecycle interruption with bounded reconnect/backoff behavior.
- Keep user-facing state clear during connecting, reconnecting, credential-invalid, unsupported-language, offline, permission-denied, and model/API error states.
- Verify current OpenAI Realtime Translation language support during implementation rather than hard-coding stale external assumptions.
- The accepted MVP credential approach is user-provided OpenAI credential/session material stored only in encrypted local device storage. Never bundle, hard-code, or commit a standard OpenAI API key in mobile source, config, assets, tests, screenshots, or build outputs.
- Ask Tom for an OpenAI API key only at the first real OpenAI network smoke/integration test.
- Store credential/session material only in encrypted local storage, redact it from logs/screenshots/test output, and provide a clear removal/reset path.

Current implementation note: issue #30 originally changed the default MVP surface from route translation to a two-party live interpreter, and the 2026-06-02 manual-pair decision restores visible `From` and `To` selectors because on-device language discovery did not reliably converge. The Flutter app now opens with `Start interpreter`, keeps the credential and microphone gates, defaults the active pair to Italian <-> English, and lets the user choose any supported app source/target pair without a manual direction switch. The coordinator seeds the selected pair into `BidirectionalInterpreterRuntime` from session start, restarts cleanly when the pair changes, and uses Gemini transcript metadata or deterministic local detection for transcript-row source labels when available. The active live UI keeps direction switching, the `Translate Text` toggle, live-header AI chat, live-screen export controls, read-aloud controls, and speaker/headphone chips hidden so secondary workflows do not compete with interpretation. A fakeable direct OpenAI text interpreter gateway exists for Phase 1 text turns and builds Responses requests with `store: false`; tests cover manual source/target selection, pair seeding, local source-language row fallback, and A-to-B/B-to-A fake translation. Existing realtime, microphone, playback, encrypted storage, AI chat, generated export, and privacy-safe diagnostics seams remain in place, with Gemini/OpenAI credential material still confined to encrypted local storage and never included in JSON setup/audio messages or diagnostics.

Current implementation note: issue #31 adds a live listening pause separate from read-aloud pause. Pausing listening stops microphone capture, the realtime session, and translated-audio playback while preserving the active encrypted local meeting and transcript state; resuming reconnects with the active realtime config and transcript commit target. After issue #53, the active live interpreter shows a clear `Connecting to Gemini` startup indicator before capture starts, parses Gemini `serverContent` transcript metadata, falls back to deterministic local source-language detection when provider metadata is missing, stores the resolved source language on transcript entries, and rolls transcript blocks on source item/language changes or a new source after a completed source+translation pair.

Current implementation note: issue #31 follow-up hardens the wired live interpreter path against the real `/v1/realtime/translations` wire shape, which streams `session.input_transcript` (source) and `session.output_transcript` (translation) deltas with no item ids and no per-event language metadata. Three defects were fixed against the wired coordinator/committer path rather than only the text-first test seam. First, transcript block splitting no longer requires a realtime translation to be present on the block to roll: a new source utterance after the current block's source completed always starts a new block, so a later turn's source and translation can no longer merge into a prior source-only block (for example an English turn whose Italian translation comes from the direct OpenAI text fallback). Second, source-language resolution never defaults an unknown source to the target language; an unresolved source stays neutral (`auto`, presented in the transcript card as a `--` chip rather than a raw code) so the live header and per-row language chips do not collapse every turn to the target language, and a single distinctive non-English marker (for example `buongiorno`, `ciao`) now resolves short foreign phrases while English-homograph markers (for example Italian `come`) only count toward the higher multi-marker threshold. Third, before the 2026-06-02 manual-pair restoration, the live header/status was driven by the runtime's detected-language ordering so it could advance from `Heard <language>. Waiting for the other language...` to the locked two-language pair label as soon as a second distinct language was heard; the current UI instead seeds the selected manual pair from session start, while the same committer fix still prevents a turn that finalizes its own translation on a sentence boundary from orphaning its `output_transcript.done` into a new, source-less block. This is wired-path logic and test coverage only; it adds no dependency, Android permission, backend route, network path, OpenAI request format, live credential read, microphone recording, or logging surface change. The installed-app live-UI header/block proof remains blocked behind #6 because this machine's emulator has no audio source.

Current implementation note: issue #31 root-cause fix (2026-06-01, after Tom's installed-app retest of PR #49). The reason original speech never appeared and all text collapsed into one transcript box on the device was that the dedicated `/v1/realtime/translations` session config set only `audio.output.language` and never configured `audio.input.transcription`. Per the official OpenAI Realtime Translation guide and cookbook, the source/original transcript is emitted only when input transcription is configured, so the live session received no `session.input_transcript` events at all; the original speech could not display, and the committer's source-utterance block boundary (the reliable boundary on this no-item-id, no-language-metadata wire shape) never fired, so every `session.output_transcript` delta appended to one block. The session config now sends `audio.input.transcription.model = gpt-realtime-whisper` and `audio.input.noise_reduction.type = near_field` while still setting only `audio.output.language`. The parser and committer already handled `session.input_transcript.*`; the fix is purely the session config request. A coordinator safety net keeps a completed translation with no source from finalizing a sourceless row (it stays `partial`/`interrupted`) so any future config/endpoint regression degrades safely. This changes only the dedicated translation session request body (adds `audio.input.transcription` and `audio.input.noise_reduction`); it adds no dependency, Android permission, backend route, app-owned network path, live credential read, microphone recording, or logging surface, and preserves the phone-only direct-OpenAI boundary. The installed-app live-UI proof remains blocked behind #6 (no emulator audio source); #31 stays open until Tom confirms on a physical Android device.

Current implementation note: issue #31 round-3 live-source-detection fix (2026-06-01, after Tom's physical-device retest of PR #50). With input transcription configured, source events now arrive for the first turn (the first card showed an `EN` chip with original and translation), but later cards reverted to `Original speech pending` with a `--` chip while still translating, and the second language was never detected. The residual cause was translation-side block rolling in `RealtimeTranscriptCommitter`: a readable block was marked complete when the translation crossed a sentence boundary or grew long, even while the same continuous source utterance was still streaming. The next translation delta then opened a new block whose source was empty, so the continued translation orphaned onto a sourceless card and the runtime never recorded that turn's source language (so the bidirectional header could not lock the second language). On the dedicated `/v1/realtime/translations` wire (no item ids, no per-event language metadata), the completed source utterance is the only reliable turn boundary, so the committer now only rolls a readable block once the current turn's source has completed; a genuinely new source utterance after completion still starts a new card. The coordinator now maintains content-free source/output transcript signal counters, exposes a `transcriptSignalSnapshot`, and emits a privacy-safe `live_realtime.translation_without_source` warning when a card finalizes with translated output but no original text. This adds no dependency, Android permission, backend route, app-owned network path, live credential read, or microphone recording, preserves local source-label detection behind the manual pair selectors, and keeps the phone-only direct-OpenAI boundary. The installed-app live-UI proof remains blocked behind #6 (no emulator audio source); #31 stays open until Tom confirms on a physical Android device.

Current implementation note: issue #31 round-3 follow-up after the solution-architect review of PR #51 (2026-06-01). The round-3 fix gated the readable-block roll on the current turn's source having completed, but the architect found two residual gaps. First, `RealtimeTranscriptCommitter` could still create a sourceless card when source completion arrived while the same turn's translation was still streaming: the completed source armed the readable roll, then a later translation delta for the same turn rolled a new, source-less block and orphaned the translation tail (the exact `Original speech pending`/`--` failure). The committer now never rolls a readable block on a translation event on this wire; once a turn's source has completed, a continued translation for that same turn always stays on the current card (original preserved, full translation appended), and a genuinely new source utterance after completion remains the sole splitter. Second, `RealtimeTranscriptSignalSnapshot.translationArrivedWithoutSource` only detected the all-output/no-source case (`hasOutputSignal && !hasSourceSignal`), which could never catch Tom's actual round-3 shape (a first source-backed card followed by later sourceless cards) because the earlier source had already set `hasSourceSignal`. The snapshot now exposes a release-checkable `hasSourcelessFinal` derived from `sourcelessFinalCount > 0`, and `translationArrivedWithoutSource` derives from it, so any sourceless final trips the failure state. Deterministic tests cover the exact failing ordering (source delta, translation delta on a sentence boundary, source done, then later translation delta/done for the same turn — one card retaining original + full translation) and the first-source-backed-then-later-sourceless-final diagnostics/snapshot shape. This adds no dependency, Android permission, backend route, app-owned network path, live credential read, microphone recording, or logging surface change, preserves local source-label detection behind the manual pair selectors, and keeps the phone-only direct-OpenAI boundary. The installed-app live-UI proof remains blocked behind #6 (no emulator audio source); #31 stays open until Tom confirms on a physical Android device.

Current implementation note: issue #31 release-artifact guidance (2026-06-01). The `debug-20260601-a7a2743` release published two APKs and Tom reported the 49 MB `release-debug-signed` build "does not work at all" while the 168 MB plain debug build runs. The release-mode APK builds, carries the correct `INTERNET`/`RECORD_AUDIO` permissions, and boots to the bounded `OpenAI setup required` state on the emulator (offline release smoke passed), so it is not broken at the code level; debug-signed builds presented as release artifacts are the kind of build device security (for example Play Protect) commonly blocks on real devices. The supported installed-test artifact is the debug APK. `scripts/build_debug_apk_artifact.sh` and `scripts/check_apk_metadata.sh` now print explicit tester guidance, and release notes/checklists must recommend only the debug APK to testers until real local release-signing material exists (#24).

Current implementation note: issue #31/#6 two-session bidirectional rework (2026-06-01, authored on a Windows checkout without the Flutter toolchain; Flutter analyzer/tests/APK build still need the Fedora toolchain, on-device EN+IT capture pending). After four committer patches kept failing on-device, the OpenAI Realtime Translation guide/cookbook were re-verified and corrected two assumptions: `gpt-realtime-translate` auto-detects the source language and emits `session.input_transcript.*` when input transcription is configured (so the keyword detector is a fallback, not primary), and the documented two-party pattern is two sessions (one per output language) with Italian among the 13 supported realtime output languages. Changes: (1) a debug-only, content-free wire-event recorder (`RealtimeEventDebugRecorder`, `--dart-define=LIVE_TRANSLATE_DEBUG_EVENTS=true`, `adb logcat | grep LIVE_TX_EVENT`) to capture the real event shape before further tuning; (2) the realtime output-language table corrected to the documented 13 (Arabic stays a fallback target); (3) an additive, best-effort, opt-in reverse audio session (`enableBidirectionalReverseSession`) in the coordinator, later disabled from the main phone UI by the 2026-06-03 text-first decision; (4) reverse-direction TEXT kept on the direct OpenAI text path with a principled trigger (fires when the source turn is already in the primary session's output language). See the 2026-06-01 two-session decision-log entry, the 2026-06-03 text-first decision-log entry, and the Live-Path Evidence Rule in [development-workflow.md](development-workflow.md). The installed-app live-UI proof remains blocked behind #6; #31 stays open until Tom confirms EN+IT bidirectional original+translation per turn on a physical device.

Current implementation note: issue #31/#6 Samsung mixed-language source follow-up (2026-06-02). Tom's physical Samsung retest showed a single card containing English, then Italian soccer speech (`Mi piace il calcio`, `Calcio e buono`), then English again. The source stream did not expose a turn boundary before the language changed, so the previous "split only after source completion" rule kept all text in one box. The committer now uses a shared local detector for supported languages when OpenAI language metadata is absent: script ranges cover Japanese, Chinese, Korean, Russian, Hindi, and Arabic, while marker sets cover supported Latin-script languages including English, Spanish, French, Italian, German, Portuguese, Indonesian, and Vietnamese. Source deltas split when the deterministic language changes, and already-split cards are protected from a later cumulative `session.input_transcript.done` transcript that includes the full mixed-language utterance. This changes local transcript segmentation only: no dependency, permission, backend route, credential handling, OpenAI request format, microphone recording, or logging surface is added. Flutter analyzer/tests/APK build still need to run on the Fedora toolchain before a replacement debug APK is published.

Current implementation note: issue #31/#6 Samsung text-first routing follow-up (2026-06-03). Tom's next physical-device retest showed English speech in the manual Italian <-> English session being accepted as English realtime output instead of translating to Italian, Italian speech not reliably creating the next Italian-original/English-translation card, and unexpected translated audio playback. The active phone live loop is now text-first by default: `_readAloudEnabled` starts false, `main.dart` leaves `enableBidirectionalReverseSession` off, and `LiveRealtimeTranslationCoordinator` skips translated-audio playback queue startup whenever read-aloud is disabled. Stable source deltas can now trigger the same direct OpenAI text fallback as source completions when the detected source language is already the primary realtime output language (for example English in an English-output Italian <-> English session), and no-item realtime output is suppressed once that fallback owns the row. This changes app-side routing/startup behavior only: no dependency, Android permission, backend route, credential handling, OpenAI request format, microphone recording, or logging surface is added. Audible translated output is no longer a default tester-build claim; #6 should first verify installed text cards from physical microphone speech.

Current implementation note: issue #37 makes live-session startup fully time-bounded. In addition to the existing WebSocket connect timeout, the post-connect bring-up steps (translated-audio playback start and microphone capture start) are each bounded by an app-side startup-step timeout. A stuck native audio/microphone init can no longer pin the session on `Preparing live session`; a timed-out bring-up step raises a sanitized startup-timeout exception that routes through the existing realtime failure classification into bounded reconnect/offline recovery. This is robustness hardening only and does not prove live microphone translation, audible output, or accepted realtime auth; #25 (accepted credential) and the #6 wired live-path proof remain open.

## Language Support And Fallback

Gemini Live Translation supports the current MVP language set for live translation. Direct OpenAI text fallback remains available for approved text-only fallback cases and AI chat/summary workflows.

Implementation requirements:

- Keep a centralized, easy-to-update language support table.
- Show all app target languages in the target picker.
- Clearly label which target languages use Gemini live output and which require the direct OpenAI fallback route.
- Detect when a requested target language is unsupported by the active live route.
- Provide a clear direct-OpenAI fallback path for broader target language support when product-approved.
- Make fallback behavior explicit in the UI rather than failing silently.
- Keep fallback AI chat and translation routes phone-only except for direct OpenAI calls.

Current implementation note: language support was verified again on 2026-05-26 against the official OpenAI Realtime overview and Realtime Translation guide. The official docs confirm the dedicated `/v1/realtime/translations` endpoint, streaming translated audio plus transcript deltas, one session per output language, and the `audio.output.language` target parameter, but they do not publish an authoritative target-language enum. The official docs list `gpt-realtime-2` as the standard voice-agent Realtime model and `gpt-realtime-translate` as the model to use when the app should translate what a human says. The app keeps `gpt-realtime-2` configured only as an explicit compatibility/experimental profile for future voice-agent validation, while microphone streaming for the MVP live-interpretation surface uses `gpt-realtime-translate`. The app uses a conservative realtime target table of English, Spanish, and French, while the target picker shows all app target languages and labels broader targets such as Italian and Japanese as direct-OpenAI fallback targets. Fallback must not use AWS, an app backend, cloud sync, or server-side transcript handling.

Updated 2026-06-01: the OpenAI Realtime Translation cookbook enumerates 13 supported output languages (Spanish, Portuguese, French, Japanese, Russian, Chinese, German, Korean, Hindi, Indonesian, Vietnamese, Italian, English), so the conservative English/Spanish/French-only realtime table was corrected to mark all 13 (including Italian) as realtime output targets in `language_support.dart`. Arabic remains a direct-OpenAI fallback target because it is an auto-detected input language but not one of the 13 outputs. This supersedes the "Italian is direct-fallback only" stance for realtime output.

Updated 2026-06-03: fallback-only targets stay selectable and explicit. If a selected target such as Arabic is not a realtime output language, the live surface shows a direct OpenAI text-fallback notice, the primary realtime session outputs the realtime-capable language on the other side of the pair so source transcripts and supported audio direction still work, and the fallback-only direction uses the phone-only direct OpenAI text path with `store: false`.

Updated 2026-06-10: issue #53 changes the active live runtime to Gemini Live Translate preview. The official Gemini Live Translate docs list Arabic and the current app languages as supported live translation languages, and the app configures Gemini with the selected target language directly. The OpenAI realtime output table and `/v1/realtime/translations` notes above are retained as historical compatibility context, not the default live route.

## Meeting Management Requirements

- User can start a new meeting.
- User can select an old meeting and continue from it.
- Meetings have local transcript/history/summary metadata stored on the phone.
- Meeting metadata should include at least meeting ID, title or generated label, created/updated timestamps, language route, transcript count, summary availability, and last activity.
- Continuing a meeting appends new transcript/history entries without losing prior local history.
- Deleting a meeting removes its local transcript/history/summary metadata.
- Meeting data must remain encrypted on device for the MVP.

## AI Chat Requirements

- Document and implement this feature as AI chat.
- Do not call it `air chat`.
- AI chat answers must be based on local meeting transcript context.
- AI chat can operate over:
  - `This meeting` when invoked from a meeting.
  - `All meetings` when invoked from a global/history surface.
- The active scope must be explicit in the UI, request construction, tests, and errors.
- AI chat uses a direct OpenAI path from the phone app.
- Answers should cite local transcript timestamps when possible.
- AI chat must handle empty transcript, no selected meeting, offline, unsupported, credential-invalid, and model/API error states.

Current implementation note: the Flutter app has a scoped AI chat sheet for `This meeting`, an `All meetings` entry from meeting history, local transcript context assembly, a fakeable direct OpenAI Responses gateway, and tests that verify `store: false` request construction without credential leakage. Live Responses smoke on 2026-05-24 passed for both `This meeting` and `All meetings` using `gpt-5.5`, `reasoning.effort: medium`, and `store: false` without printing generated answer text.

## Generated Export Requirements

- User can choose `Transcript`, `Summary`, or `Both` before generating an export.
- Export generation must be asynchronous from the UI perspective; the user can close the sheet and continue browsing while summary/export generation runs.
- Active MVP export UI does not show recipient input, recipient checklist, example recipients, add-recipient controls, or delete-recipient controls.
- The app stores generated export documents only in encrypted local device storage and exposes them through an in-app generated exports browser/detail view.
- A completion snackbar/banner should appear when generation finishes, with an action that opens the generated export detail view.
- The generated export detail view may render the plaintext export body in app and must provide an explicit Copy action through platform clipboard APIs.
- The MVP must not operate an outbound mail backend.
- Native share/mail handoff is deferred as a later explicit user-initiated option and must not be the primary generation flow.
- If `Summary` or `Both` is selected, product intent is GPT-5.5 with `xhigh` reasoning to summarize the transcript through the Responses API.
- Summary output must include:
  - brief executive summary paragraph
  - all critical talking points and outcomes as bullet points
  - actions listed at the bottom
  - transcript below the summary if `Both` was selected
- Transcript, summary, recipient addresses, and export payloads must not be logged, sent to app-owned backend infrastructure, stored in plaintext files/preferences, or included in analytics/crash reports.

Current implementation note: Transcript/Summary/Both exports are generated into encrypted local meeting storage and browsed in app. Summary and Both exports use a fakeable direct OpenAI Responses gateway from the phone with `gpt-5.5`, `reasoning.effort: xhigh`, and `store: false`; credentials stay in the Authorization header only, generated summary text/metadata and generated export bodies are stored only in encrypted local storage. Generation runs in the background from the UI perspective, completion appears as an in-app snackbar with an Open action, and plaintext export bodies are exposed only in the generated export detail view and the explicit Copy action. Unit/widget tests cover request construction, credential non-leakage, local summary persistence, encrypted local generated-export persistence, and Summary/Both export composition. Live Responses smoke on 2026-05-24 passed for the summary path with `gpt-5.5`, `reasoning.effort: xhigh`, `store: false`, and expected summary headings validated without printing generated summary text.

## Privacy, Security, And Logging Requirements

Target users include very high-level executives. Cybersecurity is a first-class acceptance criterion.

- No standard Gemini or OpenAI API keys in mobile source, committed config, assets, logs, tests, screenshots, or app bundles.
- No app backend, AWS, cloud sync, server mailer, or server-side transcript handling in the MVP.
- Direct Gemini API calls for live translation and direct OpenAI API calls for AI chat, summaries, and approved text fallback are the only routine network paths for app product behavior.
- User-initiated generated export copy may place content on the platform clipboard only after the user explicitly presses Copy; the app must not run an outbound mail backend.
- Local meeting transcript history, summary metadata, sensitive preferences, remembered recipients, and credential/session material must be encrypted on device when implementation exists.
- Use least-privilege mobile permissions. Microphone access is required; any additional permission needs product/security justification.
- Logs and diagnostics must exclude speech, transcript payloads, full prompts, translated content, summaries, recipient lists, raw auth/session tokens, Gemini/OpenAI credential material, and API keys.
- Crash reporting or analytics, if added later, must use redaction and opt-in/notice appropriate to the product.
- Dependencies must be pinned through lockfiles once implementation exists and checked against credible advisory sources before merge.
- Tests should include negative assertions for transcript routing, secret leakage, and logging/diagnostics leakage.

## Verification Requirements

Minimum verification plan once implementation exists:

- `flutter analyze`
- `flutter test`
- Android emulator smoke check using `android-pixel9-headless`
- Secret scanning or equivalent check that no standard Gemini/OpenAI API key appears in mobile code/config/assets/tests/build outputs
- Dependency/advisory check for pinned Flutter/Dart/native package versions
- Local cybersecurity gate: `bash scripts/check-supply-chain.sh`
- UI smoke checks for supplied mockup-derived surfaces plus meeting management and generated export surfaces
- Accessibility checks for labels, focus order, large text, generated export controls, and contrast-sensitive states
- Privacy routing test showing no transcript/audio/prompt/summary/export content is sent to an app backend
- Logging/diagnostics tests showing transcript, summary, recipients, prompts, microphone audio, and OpenAI credential material are redacted or absent

Tom's Fedora machine has an Android SDK and boot-tested emulator available:

```bash
android-pixel9-headless
```

Do not use:

```bash
emulator -no-window
```

It is known to segfault on this Fedora/KDE/Wayland setup.

## README And Issue Maintenance

- Update [README.md](../README.md) whenever setup, architecture, behavior, issue status, verification steps, or known risks change.
- Keep GitHub issue scope aligned with this build spec and acceptance criteria.
- Close completed issues only after matching verification has run or the reason for skipped verification is documented.
- If a new implementation gap appears, create or update a focused issue instead of burying it in an unrelated task.

## GitHub Issue Map

Closed planning and implementation intake:

- #1 Finalize product spec and mockup intake.
- #2 Scaffold Flutter mobile app.
- #3 Implement Flutter UI from supplied mockups for phone-only MVP.
- #7 Implement language support and fallback routing.
- #8 Add scoped AI chat over local meetings.
- #9 Implement local encrypted meeting storage.
- #10 Maintain cybersecurity threat model and report.
- #11 Document Android emulator workflow for Codex.
- #12 Create phone-only MVP test strategy.
- #13 Implement microphone permissions and live session lifecycle.
- #15 Implement privacy-safe local logging and diagnostics controls.
- #16 Add CI quality gates for docs, Flutter, and secret safety.
- #17 Add accessibility and responsive text verification.
- #18 Define Flutter design tokens and reusable mockup components.
- #20 Implement local meeting management.
- #21 Add email export for transcripts and summaries.
- #22 Implement dependency and supply-chain cybersecurity controls.
- #23 Decide safe direct OpenAI mobile credential approach.

Open MVP/planning work:

- #6 Integrate direct OpenAI Realtime Translation.
- #14 Harden direct OpenAI realtime resilience.
- #19 Maintain README and agent handoff docs during implementation.
- #24 Track store-ready Android release signing.

Deferred V2/future issues:

- #4 V2: Implement Google and Microsoft sign-in.
- #5 V2: Build AWS Lambda token broker.

## Initial Non-Goals

- Full iOS release.
- Organization/team admin console.
- App backend.
- AWS API Gateway or Lambda.
- Token broker.
- Google/Microsoft cloud identity as an MVP gate.
- Cloud transcript storage or sync.
- Server-side transcript, audio, summary, or email handling.
- Outbound mail backend.
- Human interpreter marketplace.
- Heavy backend business logic.

## Open Questions To Resolve During Implementation

- Final Android signing certificate details; tracked in #24 for store-ready release handoff.
- The accepted credential/session implementation details for user-provided OpenAI credential material, including UX, encrypted storage reset/removal, and credential-invalid recovery.
- The installed-app physical microphone/audio behavior for fallback-only target pairs, such as English <-> Arabic, still needs device validation under #6 after the 2026-06-03 fallback routing fix.
- Real physical microphone/audio behavior for the dedicated `gpt-realtime-translate` live route under installed-app streaming.
- Whether diagnostics/crash reporting is included in MVP or deferred.
