# Decision Log

Use this file for durable product and architecture decisions that future agents should preserve. The canonical build spec remains [docs/live-translate-build-spec.md](live-translate-build-spec.md).

## 2026-05-24 - Phone-Only MVP Architecture

Status: Accepted

Decision:

- Build an Android-first Flutter mobile app while keeping the project iOS-compatible later.
- Keep the MVP completely phone-only aside from direct OpenAI API calls.
- Do not include AWS API Gateway, Lambda, a token broker, app backend, cloud identity gate, cloud sync, server mailer, or server-side transcript handling in the MVP.
- Prefer `gpt-realtime-2` for realtime voice/translation unless endpoint/API testing finds a major blocker.
- Keep `gpt-realtime-translate` as a dedicated translation fallback/profile.
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
- Implementation must verify endpoint behavior for `gpt-realtime-2` versus `gpt-realtime-translate` and keep GPT-5.5 `xhigh` reasoning for summary intent.
- Logs, diagnostics, analytics, crash reports, screenshots, and tests must avoid transcript, audio, prompt, summary, recipient, and credential/session leakage.
- Dependency/package hygiene, permission minimization, and supply-chain checks are required acceptance criteria.

## 2026-05-24 - Direct OpenAI Credential And Model Preference

Status: Accepted

Decision:

- Proceed with direct phone-to-OpenAI API calls for the MVP.
- Do not add an MVP backend, AWS/Lambda token broker, or cloud identity gate.
- Use user-provided OpenAI credential/session material stored only in encrypted local device storage.
- Do not commit, bundle, or embed a standard OpenAI API key in mobile code, config, assets, tests, screenshots, or build outputs.
- Ask Tom for an OpenAI API key only when the app reaches the first real OpenAI network smoke/integration test.
- Prefer `gpt-realtime-2` for realtime voice/translation unless endpoint/API testing finds a major blocker.
- Keep `gpt-realtime-translate` as a dedicated translation fallback/profile.
- Use GPT-5.5 with `xhigh` reasoning intent for transcript summary generation.

Rationale:

- This preserves the phone-only MVP architecture while unblocking non-secret OpenAI integration scaffolding.
- Official OpenAI docs verified on 2026-05-24 list `gpt-realtime-2` as the most capable realtime voice model and `gpt-realtime-translate` as a dedicated streaming speech-to-speech translation model.
- Official Realtime client-secret docs still recommend server-minted ephemeral credentials for browser/mobile clients, but Tom accepted a phone-local user-provided credential path for MVP rather than introducing an app backend.

Implications:

- Credential UX, encrypted storage, redaction, reset/removal, and credential-invalid recovery are MVP implementation requirements.
- A real OpenAI network smoke test requires Tom to provide a key out-of-band or interactively at that point; no placeholder or real key belongs in the repo.
- If live endpoint/API testing shows `gpt-realtime-2` cannot meet translation needs, use the dedicated `gpt-realtime-translate` profile without adding backend infrastructure.

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
