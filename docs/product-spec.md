# Product Spec

This is the high-level product spec. Use [docs/live-translate-build-spec.md](live-translate-build-spec.md) as the canonical build-ready spec for implementation, verification, and issue triage.

## Goal

Build an Android-first, iOS-compatible mobile app for continuous live speech translation using OpenAI Realtime Translation. The MVP is phone-only except for direct OpenAI API calls.

## Core Experience

1. User opens the app and starts a new meeting or selects an old meeting.
2. User chooses source language detection or a known input language.
3. User chooses a supported output language.
4. App starts continuous translation through a direct OpenAI API connection.
5. OpenAI streams translated audio and transcript deltas while the speaker is still talking.
6. User can review local meeting history and continue from an old meeting.
7. User can use scoped AI chat over `This meeting` or `All meetings`.
8. User can generate Transcript, Summary, or Both as encrypted local exports, review them in app, and explicitly copy an export when ready.

## Supplied Mockups

Tom has supplied four Android mockups covering the welcome screen, teal listening live translation state, transcript assistant bottom sheet, and amber speaking or paused read-aloud state. Use [docs/mockup-ux-spec.md](mockup-ux-spec.md) as the visual and interaction source of truth for the first Flutter implementation.

The source image files are in [assets/mockups](../assets/mockups):

- [01-welcome-sign-in.jpg](../assets/mockups/01-welcome-sign-in.jpg)
- [02-live-listening-teal.jpg](../assets/mockups/02-live-listening-teal.jpg)
- [03-transcript-assistant.jpg](../assets/mockups/03-transcript-assistant.jpg)
- [04-speaking-paused-amber.jpg](../assets/mockups/04-speaking-paused-amber.jpg)

The revised MVP keeps the visual direction but adapts sign-in affordances into phone-local setup/start-meeting behavior. Google/Microsoft sign-in is V2/future.

## Architecture

### Mobile

- Flutter app.
- Android-first implementation.
- Keep iOS compatibility in project structure and dependencies.
- Store sensitive local data using encrypted device storage.
- Store meetings, transcript/history, summary metadata, generated exports, recipient preferences, recent languages, and sensitive settings locally.
- Do not embed a standard OpenAI API key.

### Backend

- No app backend in MVP.
- No AWS API Gateway, Lambda, token broker, cloud sync, cloud identity gate, server mailer, or server-side transcript handling.
- Deferred cloud/backend/auth scope is tracked in [docs/v2-future-scope.md](v2-future-scope.md).

### OpenAI

- Live translation uses `gpt-realtime-translate` on `/v1/realtime/translations` for normal MVP human-speech interpretation.
- Keep `gpt-realtime-2` only as an explicit compatibility/experimental voice-agent profile.
- App connects directly to the OpenAI API from the phone.
- Translation path should support streaming translated audio and transcript deltas.
- AI chat and summary generation use direct OpenAI calls from the phone.
- The accepted MVP credential approach is user-provided OpenAI credential/session material stored only in encrypted local device storage; no key may be committed or bundled.
- Account for current platform limits: broad input language coverage, narrower target output language coverage, endpoint/model support, and reasoning parameter availability must be verified during implementation.

## Meeting Management

- User can start a new meeting.
- User can select an old meeting and continue from it.
- Meetings have local transcript/history/summary metadata stored on the phone.
- Meeting history is encrypted on device and can be deleted.

## Scoped AI Chat

- Document and implement this as AI chat.
- AI chat scope is explicit:
  - `This meeting`
  - `All meetings`
- Answers should be grounded in local transcript context and cite timestamps when possible.
- Transcript context is sent only through direct OpenAI calls from the phone.

## Generated Exports

- User can choose Transcript, Summary, or Both.
- Generation runs in the background from the UI perspective.
- Active MVP UI does not show recipient input, recipient checklist, example recipients, add-recipient controls, or delete-recipient controls.
- Generated export bodies are stored only in encrypted local storage.
- The app shows generated exports in app and exposes clipboard copy only after an explicit user action.
- No outbound mail backend in MVP.
- If Summary or Both is selected, product intent is GPT-5.5 with `xhigh` reasoning through the Responses API.

## Privacy And Security

- Direct OpenAI API calls are the only routine network path for product behavior.
- No app-owned backend may receive transcript, audio, prompt, summary, recipient, or export payloads.
- Local storage is encrypted.
- No cloud transcript sync in the MVP.
- Logs, analytics, crash reports, screenshots, and test output must avoid user speech/transcript payloads, prompts, translations, summaries, recipient lists, and OpenAI credential/session material.
- Dependency/package hygiene, mobile permission minimization, supply-chain checks, and no transcript leakage are first-class acceptance criteria.

## Initial Non-Goals

- Full iOS release.
- Organization/team admin console.
- App backend, AWS, Lambda, token broker, or cloud identity gate.
- Cloud transcript storage or sync.
- Server-side transcript, summary, audio, or email handling.
- Outbound mail backend.
- Human interpreter marketplace.
- Heavy backend business logic.
