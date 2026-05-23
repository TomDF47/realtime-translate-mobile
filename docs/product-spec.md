# Product Spec

## Goal

Build an Android-first, iOS-compatible mobile app for continuous live speech translation using OpenAI Realtime Translation.

## Core Experience

1. User signs in with Microsoft personal, Microsoft organisational, or Google identity.
2. User chooses source language detection or a known input language.
3. User chooses a supported output language.
4. App starts continuous translation.
5. OpenAI streams translated audio and transcript deltas while the speaker is still talking.
6. User can review local transcript history and ask Q&A about the transcript without sending transcript content through AWS.

## Architecture

### Mobile

- Flutter app.
- Android-first implementation.
- Keep iOS compatibility in project structure, dependencies, and auth choices.
- Store sensitive local data using encrypted device storage.
- Do not embed a standard OpenAI API key.

### Backend

- AWS API Gateway + Lambda.
- Token broker only.
- Validates user identity/session.
- Requests short-lived OpenAI client secrets.
- Returns client secrets to the mobile app.
- Does not receive transcript content.
- Does not store transcript content.

### OpenAI

- Live translation uses `gpt-realtime-translate`.
- App connects directly to OpenAI Realtime Translation with short-lived client secrets.
- Translation path should support streaming translated audio and transcript deltas.
- Account for current platform limits: broad input language coverage, narrower target output language coverage.
- Provide fallback route for broader target-language support when Realtime Translation output language is unsupported.

## Identity

Support:

- Microsoft personal accounts.
- Microsoft work/school organisational accounts.
- Google sign-in.

Implementation notes:

- Microsoft app registration should support both personal and work/school account types.
- Google Android credentials require package name and signing certificate.
- Identity should gate token broker access.

## Privacy

- AWS must not see transcript content.
- Backend logs must avoid user speech/transcript payloads.
- Transcript storage is local-only and encrypted.
- No cloud transcript sync in the first version.

## Initial Non-Goals

- Full iOS release.
- Organisation/team admin console.
- Cloud transcript storage.
- Human interpreter marketplace.
- Heavy backend business logic.

