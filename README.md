# Realtime Translate Mobile

Android-first Flutter app for live speech translation, designed to stay iOS-compatible.

## Source Of Truth

- Canonical build spec: [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md)
- Mockup UX spec: [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md)
- Supplied mockups: [assets/mockups](assets/mockups)
- Codex agent instructions: [AGENTS.md](AGENTS.md)

## Decision Record

- Mobile app: Flutter, Android-first, iOS-compatible later
- Backend: Minimal AWS API Gateway + Lambda token broker
- OpenAI connection: App connects directly to OpenAI using short-lived client secrets
- Main translation model: `gpt-realtime-translate`
- Transcript Q&A: Prefer a direct OpenAI path that avoids AWS seeing transcript content
- Data storage: Local encrypted device storage only
- Identity: Microsoft personal accounts, Microsoft work/school organisational accounts, and Google sign-in

## Product Direction

The app should feel premium, clean, and executive-grade. The first usable surface should be the live translation experience, not a technical dashboard. Treat the backend as a narrow security component whose only job is issuing short-lived OpenAI client secrets after identity checks.

## Current Status

Planning repo created. Supplied Android mockups have been received, copied into [assets/mockups](assets/mockups), and captured in [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md). The canonical build-ready spec is [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).

Do not start Flutter implementation until the implementation issue is explicitly picked up. Keep work aligned to the GitHub issue acceptance criteria.

## GitHub Issue Map

Closed planning intake:

- #1 Finalize product spec and mockup intake

Open MVP/planning work:

- #2 Scaffold Flutter mobile app
- #3 Implement Flutter UI from supplied mockups
- #4 Implement Google and Microsoft sign-in
- #5 Build AWS Lambda token broker
- #6 Integrate OpenAI Realtime Translation
- #7 Implement language support and fallback routing
- #8 Add privacy-preserving transcript Q&A
- #9 Implement local encrypted storage
- #10 Write security and privacy threat model
- #11 Document Android emulator workflow for Codex
- #12 Create MVP test strategy
- #13 Implement microphone permissions and live session lifecycle
- #14 Harden realtime connection resilience and token refresh
- #15 Implement privacy-safe logging and diagnostics controls
- #16 Add CI quality gates for docs, Flutter, backend, and secret safety
- #17 Add accessibility and responsive text verification
- #18 Define Flutter design tokens and reusable mockup components
- #19 Maintain README and agent handoff docs during implementation

## Supplied Mockups

All supplied mockups are 720x1280 Android portrait JPGs:

- [01-welcome-sign-in.jpg](assets/mockups/01-welcome-sign-in.jpg)
- [02-live-listening-teal.jpg](assets/mockups/02-live-listening-teal.jpg)
- [03-transcript-assistant.jpg](assets/mockups/03-transcript-assistant.jpg)
- [04-speaking-paused-amber.jpg](assets/mockups/04-speaking-paused-amber.jpg)

## Implementation Guardrails

- Never embed a standard OpenAI API key in mobile code, mobile config, assets, tests, or build outputs.
- Preserve the privacy architecture: AWS is a token broker only and must never receive transcript or audio content.
- Keep transcript Q&A on a direct OpenAI or equivalent privacy-preserving path that avoids AWS seeing transcript content.
- Store transcript history and sensitive local data only in encrypted device storage for the MVP.
- Keep logs, crash reports, analytics, and diagnostics free of speech, transcript payloads, prompts, translations, bearer tokens, client secrets, and API keys.
- Verify current OpenAI Realtime Translation target language support during implementation and keep fallback routing explicit for unsupported target languages.

## Documentation Maintenance

Every future change should update this README when setup, architecture, product behavior, issue status, verification steps, or known risks change. Product or architecture decision changes should also update [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).

## Development Notes

Tom's Fedora machine has an Android SDK and boot-tested emulator available:

```bash
android-pixel9-headless
```

Use that instead of `emulator -no-window`, which segfaults on this machine.
