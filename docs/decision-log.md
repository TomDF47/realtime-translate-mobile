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
- Add user-initiated email export through device-native mail/share composer semantics where practical.
- Treat cybersecurity as a first-class acceptance criterion.

Rationale:

- Phone-local operation minimizes backend privacy risk and keeps executive meeting transcripts away from app-owned infrastructure.
- Direct phone-to-OpenAI calls preserve the intended realtime product path without introducing a transcript/audio proxy.
- Local encrypted storage keeps the MVP privacy model simple and auditable.
- Explicit AI chat scope reduces accidental cross-meeting disclosure.
- Native mail/share export avoids operating a server-side email relay for sensitive transcript data.

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
- Route microphone streaming through the dedicated `gpt-realtime-translate` profile for now because live synthetic PCM16 append was accepted there while the current primary `gpt-realtime-2` append flow returned `missing_required_parameter`.

Rationale:

- The existing Android platform channel layer already owns microphone permission and keeps the supply-chain surface smaller than adding an audio dependency.
- OpenAI's current translation client-event docs describe 24 kHz PCM16 mono little-endian raw audio and 200 ms chunks for WebSocket translation sessions.
- A fakeable capture gateway lets tests prove credential/permission gating and chunk flow without recording microphone audio or using a live credential.
- The primary Realtime 2 session remains configured and no-audio session creation passes, but its current audio append flow needs follow-up before it should receive live microphone chunks.

Implications:

- Future audio package, SDK, resampling, or playback additions must update the cybersecurity report and rerun supply-chain checks.
- Real microphone translation smoke, native translated-audio speaker output, and live transcript validation remain open #6/#14 work.

## 2026-05-24 - Translated Audio Playback Starts As A Fakeable Local Queue

Status: Accepted

Decision:

- Decode OpenAI realtime translated-audio deltas into PCM16 chunks inside the phone app.
- Send decoded chunks only to a local `TranslatedAudioPlaybackGateway` seam.
- Keep the first production gateway as a no-op placeholder that does not retain audio-derived data.
- Start the playback gateway only after credential, microphone permission, and realtime connection gates pass.
- Stop and clear playback resources during reconnecting, offline, credential-invalid, backgrounded, stopped, and failed reconnect states.
- Do not add an audio playback package, native speaker output engine, backend relay, logging sink, or extra Android permission in this software-only slice.

Rationale:

- The fakeable gateway lets tests prove decoded translated-audio routing and reconnect teardown/restart behavior without requiring a physical speaker path or controllable microphone source.
- Keeping audio-derived payloads in transient memory only preserves the phone-only privacy boundary while native output remains unimplemented.
- A no-dependency seam keeps supply-chain risk low until the app is ready for a focused Android/iOS audio-output implementation.

Implications:

- Native speaker output is still open #6/#14 work and must update the cybersecurity report, dependency checks, and tests when implemented.
- Diagnostics around playback must remain limited to sanitized operation/result/error labels and must never include audio bytes, base64 chunks, transcript text, translated text, or credentials.
