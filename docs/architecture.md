# Architecture

This document summarizes the implementation boundaries from the canonical [live translate build spec](live-translate-build-spec.md). The build spec remains authoritative when details conflict.

## System Shape

```text
Signed-in Flutter app
  -> AWS API Gateway + Lambda token broker
       -> OpenAI API, backend-held standard API key
       <- short-lived OpenAI client secret metadata

Signed-in Flutter app
  -> OpenAI Realtime Translation directly
       model: gpt-realtime-translate
       sends microphone audio
       receives translated audio and transcript deltas

Signed-in Flutter app
  -> encrypted local device storage
       preferences, recent languages, transcript history

Transcript Q&A
  -> direct OpenAI path or equivalent privacy-preserving path
       AWS must not see transcript content
```

## Hard Boundaries

- Mobile code never contains a standard OpenAI API key.
- AWS is a token broker only.
- AWS must not receive transcript text, translated text, prompts about transcripts, microphone audio, audio chunks, or audio-derived payloads.
- The mobile app connects directly to OpenAI using short-lived client secrets.
- Transcript storage is local-only and encrypted for the MVP.
- Diagnostics, analytics, crash reports, and logs must exclude secrets and speech/transcript payloads.

## Mobile App Responsibilities

- Flutter app with Android-first UX and iOS-compatible structure.
- Auth UI and session handling for Microsoft personal, Microsoft work/school, and Google identity.
- Runtime microphone permissions and explicit session state transitions.
- Realtime session connection, refresh, reconnect, and teardown.
- Local encrypted storage for preferences, recent languages, and transcript history.
- UI surfaces from [docs/mockup-ux-spec.md](mockup-ux-spec.md) and [assets/mockups](../assets/mockups).
- Transcript Q&A UI and direct privacy-preserving model path.

## Backend Responsibilities

- Validate signed-in caller identity/session.
- Use backend secret storage/config for the standard OpenAI API key.
- Request short-lived OpenAI client secrets.
- Return only the short-lived secret and metadata such as expiry.
- Redact bearer tokens, client secrets, identity tokens, and API keys from logs.

The backend must not add transcript endpoints for the MVP.

## OpenAI Responsibilities

- Live speech translation through `gpt-realtime-translate`.
- Stream translated audio and transcript deltas while the speaker is still talking.
- Support client-secret expiry handling and reconnect behavior in the app.
- Language support must be verified during implementation rather than hard-coded from stale assumptions.

## Suggested Future Repo Layout

When implementation begins, keep boundaries visible:

```text
app/ or mobile/              Flutter application
backend/token-broker/        AWS Lambda token broker
docs/                        Product, architecture, setup, testing, decisions
assets/mockups/              Supplied Android mockups
test/                        Flutter tests once scaffolded
```

Use the actual Flutter scaffold conventions when the app is created; update this section if the final layout differs.

## Prohibited Flows

- Mobile app -> AWS -> OpenAI transcript or audio proxy.
- Mobile app -> committed standard OpenAI API key.
- Transcript Q&A -> AWS transcript endpoint.
- Logs -> raw transcript, translated text, prompts, microphone audio, auth tokens, OpenAI client secrets, or standard API keys.
- Cloud transcript sync in the MVP.
