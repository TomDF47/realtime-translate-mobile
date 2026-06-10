# Privacy-Safe Diagnostics

This document defines the MVP logging and diagnostics boundary. The phone app may record local diagnostic state for debugging, but it must not record user meeting content, OpenAI credential material, or export payloads.

## Implementation

Diagnostics flow through `PrivacySafeDiagnostics` in `lib/src/diagnostics/privacy_safe_diagnostics.dart`.

- The default sink is no-op.
- Any future sink must receive records only after field allowlisting, redaction, and omission.
- Current wired paths cover live-session state transitions, realtime recovery decisions, and OpenAI credential status/read/save/remove events.
- Diagnostic records are for local state only; they are not analytics, crash reports, telemetry, or backend logs.

## Allowed Fields

Allowed fields are low-sensitivity state and configuration labels:

- app lifecycle state
- audio route
- bounded retry/backoff numbers
- credential status as `missing` or `configured`
- endpoint path/model intent labels
- export type
- local operation/result labels
- permission name/status
- previous and next live-session phase
- resource-open booleans
- scope labels such as `This meeting` or `All meetings`
- storage area labels

If a field is not allowlisted, the diagnostics helper records `[omitted]` unless the key is sensitive, in which case it records `[redacted]`.

## Forbidden Fields

Do not log, print, emit, screenshot, or add to diagnostics:

- standard Gemini/OpenAI API keys, Realtime client secrets, session tokens, bearer tokens, cookies, or authorization headers
- transcript text, translated text, prompt text, summary text, request bodies, response bodies, or raw payloads
- microphone audio, audio chunks, audio-derived payloads, or playback buffers
- recipient email addresses, recipient lists, export payloads, or native mail/share payload bodies
- meeting IDs, transcript IDs, session IDs, or credential material
- full model requests or responses
- crash/analytics events that contain any of the above

## Verification

Current tests in `test/privacy_safe_diagnostics_test.dart` prove:

- secret-like OpenAI keys and session tokens are redacted
- email addresses, prompts, transcript text, translated text, request bodies, and recipient fields do not appear in serialized diagnostic records
- live-session diagnostics record state transitions only, not user-facing notices or payloads
- realtime recovery diagnostics record sanitized error code, retry attempt, and backoff milliseconds only
- OpenAI credential diagnostics never include credential values or API-key field names

Run:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter test test/privacy_safe_diagnostics_test.dart
```

For full local verification, also run the standard gates from [docs/testing-strategy.md](testing-strategy.md).
