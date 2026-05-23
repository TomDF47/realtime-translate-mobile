# V2 Future Scope

This document keeps deferred cloud, backend, auth, and sync ideas out of the MVP while preserving useful context for later planning.

## Current Rule

The MVP is phone-only aside from direct OpenAI API calls. Do not add AWS, Lambda, token broker, app backend, cloud identity, cloud sync, server mailer, or server-side transcript handling unless a later accepted decision updates:

- [docs/live-translate-build-spec.md](live-translate-build-spec.md)
- [docs/architecture.md](architecture.md)
- [docs/decision-log.md](decision-log.md)
- [README.md](../README.md)
- the relevant GitHub issues

## Deferred Items

### Cloud Identity

Deferred from MVP:

- Microsoft personal account sign-in.
- Microsoft work/school organizational account sign-in.
- Google sign-in.
- Identity-gated app sessions.
- Cloud account linking across devices.

Relevant issue:

- #4 V2: Implement Google and Microsoft sign-in.

### Token Broker And Backend

Deferred from MVP:

- AWS API Gateway.
- AWS Lambda token broker.
- Backend-held standard OpenAI API key.
- Backend validation before issuing OpenAI client secrets.
- Backend token expiry metadata and refresh contract.

Relevant issue:

- #5 V2: Build AWS Lambda token broker.

### Cloud Sync And Server-Side Storage

Deferred from MVP:

- Cloud transcript storage.
- Meeting sync across devices.
- Server-side meeting metadata storage.
- Organization/team admin surfaces.
- Centralized policy management.

Any future design must explicitly decide whether transcript, summary, recipient, or meeting metadata can leave the device. The default remains no.

### Server-Side Transcript, Summary, Or AI Chat Handling

Deferred from MVP and high risk:

- App backend transcript ingestion.
- App backend transcript/audio proxying to OpenAI.
- Server-side summary generation.
- Server-side AI chat over transcripts.
- Server-side export preparation.

Future consideration requires a privacy and threat-model update before implementation.

### Outbound Mail Backend

Deferred from MVP:

- App-operated outbound email service.
- Server-side mail relay.
- Export queue.
- Server-side recipient management.

MVP export should use user-initiated device-native mail/share composer semantics where practical.

## Future Security Conditions

Before any V2 cloud/backend/auth work begins, update the threat model and answer:

- What exact data leaves the phone?
- Which system receives it?
- Why is phone-local operation insufficient?
- What is encrypted in transit and at rest?
- Which logs, traces, analytics, and crash systems can observe metadata?
- How are OpenAI credentials/session material protected?
- How does the design prevent transcript/audio/prompt/summary leakage?
- How will users delete cloud data?
- What new tests and CI gates prove the boundary?

## MVP Protection

Future agents should not treat this file as permission to implement deferred systems. It is only a parking lot for post-MVP scope.
