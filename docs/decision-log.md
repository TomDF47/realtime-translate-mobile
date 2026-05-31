# Decision Log

Use this file for durable product and architecture decisions that future agents should preserve. The canonical build spec remains [docs/live-translate-build-spec.md](live-translate-build-spec.md).

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
- Phase 1 is text-first: detect the first language, wait for a second distinct language, lock the pair as `<A> <-> <B>`, and translate subsequent A-to-B and B-to-A turns as text.
- Keep startup gated by encrypted local OpenAI credential availability and microphone permission.
- Hide source/target pickers, direction switching, read-aloud controls, and speaker/headphone chips in the active live interpreter UI until spoken audio behavior is safely supportable.
- Hide the `Translate Text` toggle, live-header AI chat launcher, and live-screen export controls from the active live interpreter UI so secondary workflows do not compete with interpretation.
- Preserve the phone-only direct OpenAI path, encrypted local transcript storage, privacy-safe diagnostics, and no-backend MVP boundary.

Rationale:

- A live interpreter should not require users to preselect direction or manually switch speakers.
- The app should not imply fully automatic bidirectional spoken audio before real audio support is validated.
- Text-first interpreter behavior can be tested through fakeable direct OpenAI seams with `store: false` while retaining existing realtime/audio seams for later validation.

Implications:

- Start surface copy uses `Start interpreter`.
- Live status progresses through `Listening for languages...`, `Heard <language>. Waiting for the other language...`, and `<A> <-> <B>`.
- Tests and regression checklists should verify no source picker, target picker, direction switch, `Translate Text` toggle, live-header AI chat, live-screen export controls, or read-aloud claims appear in the active interpreter flow.

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

- Add `scripts/android_release_smoke.sh` as the repeatable Android release smoke entrypoint: build/locate a debug APK, run an APK metadata + signing preflight, cold-boot the emulator resiliently, install, clear app state, launch, and prove startup reaches a bounded state without a real OpenAI credential.
- Extract the emulator cold boot into a shared helper `scripts/lib/android_emulator_boot.sh` with reuse-online-device, bounded retries, an AVD-scoped process watchdog, `adb` device-state checks, conservative stale-lock cleanup, and per-attempt log tails. Source it from `scripts/android_emulator_e2e.sh`, replacing the previous single-shot launch plus unbounded `adb wait-for-device`.
- Add `scripts/check_apk_metadata.sh` to verify SHA-256 sidecar, package id, version metadata, and a least-privilege permission allowlist, and to report debug vs release signing without failing a debug release.
- Prove the bounded startup state with the existing no-secret `--verify-invalid-credential-recovery` path plus an explicit assertion that the UI never remains on `Preparing live session`.
- Keep Android emulator smoke local-only. CI stays Flutter-only (`flutter pub get`, `flutter analyze`, `flutter test`, supply-chain), and docs (`bash scripts/check-docs.sh`).
- Make GitHub result recording opt-in: print a sanitized result block by default, and post to a release (`--record-to-release`) or issue (`--record-to-issue`) via `gh` only when asked, after a secret-pattern guard.

Rationale:

- The 2026-05-31 debug release could not complete install/run validation because `Pixel_9_API_36_Play` repeatedly died during cold boot before stable `adb`, and the single-shot boot path either hung or failed without a repeatable outcome.
- A flaky cold boot should not block every release. Bounded retries plus a watchdog convert a hang into a fast, deterministic pass or fail.
- Validating an APK should not require a live OpenAI key; the invalid-credential recovery path already exercises the connecting phase and, with the #37 connect bound, reaches a bounded recovery state.
- A GitHub-hosted emulator job (for example `reactivecircus/android-emulator-runner`) was considered and rejected for the MVP: it is historically flaky, adds CI surface, and contradicts the existing local/manual emulator stance.

Implications:

- Releases should run `scripts/android_release_smoke.sh` (or `scripts/final_qa_gate.sh --release-smoke`) and record the sanitized result in release notes or an issue comment.
- If the emulator cannot cold-boot on the host, the smoke fails fast with a captured log tail; fall back to a physical device or an attached emulator rather than weakening the boot checks.
- The default smoke path must never read a real OpenAI credential, make a live OpenAI request, or print credential/transcript/audio/summary/export payloads.
- The boot helper must only stop emulator processes whose arguments name `Pixel_9_API_36_Play`, and must continue to avoid `emulator -no-window` on this Fedora/Wayland host.
