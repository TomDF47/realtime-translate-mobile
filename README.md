# Realtime Translate Mobile

Android-first Flutter app for live speech translation, designed to stay iOS-compatible.

## Source Of Truth

- Canonical build spec: [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md)
- Mockup UX spec: [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md)
- Supplied mockups: [assets/mockups](assets/mockups)
- Codex agent instructions: [AGENTS.md](AGENTS.md)
- Development workflow: [docs/development-workflow.md](docs/development-workflow.md)
- Architecture handoff: [docs/architecture.md](docs/architecture.md)
- Environment setup: [docs/environment.md](docs/environment.md)
- Testing strategy: [docs/testing-strategy.md](docs/testing-strategy.md)
- Decision log: [docs/decision-log.md](docs/decision-log.md)

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

Agentic development handoff docs are in place for workflow, architecture, environment placeholders, testing strategy, and decision logging. The repo does not yet contain a Flutter scaffold or Lambda implementation.

Do not start Flutter implementation until the implementation issue is explicitly picked up. Keep work aligned to the GitHub issue acceptance criteria.

## Repository Map

- [AGENTS.md](AGENTS.md): required operating contract for future Codex jobs.
- [CONTRIBUTING.md](CONTRIBUTING.md): contribution and PR expectations.
- [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md): canonical product, architecture, privacy, and implementation spec.
- [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md): visual and interaction source of truth for the first Flutter UI pass.
- [docs/architecture.md](docs/architecture.md): mobile, AWS, OpenAI, storage, and prohibited data-flow boundaries.
- [docs/development-workflow.md](docs/development-workflow.md): issue workflow, doc update matrix, and handoff checklist.
- [docs/environment.md](docs/environment.md): local setup, emulator notes, env placeholders, and secret handling.
- [docs/testing-strategy.md](docs/testing-strategy.md): docs, Flutter, backend, privacy, and emulator verification plan.
- [docs/decision-log.md](docs/decision-log.md): durable decisions future agents should preserve.
- [docs/codex-starter-prompt.md](docs/codex-starter-prompt.md): starter prompt for the first Flutter implementation pass.
- [.env.example](.env.example): placeholder-only environment contract.
- [scripts/check-docs.sh](scripts/check-docs.sh): docs link and secret-pattern sanity check.

## Local Setup

For the current docs/planning repo:

```bash
bash scripts/check-docs.sh
```

Do not add real credentials to `.env.example` or any committed file. Use uncommitted local env files and backend secret storage for secrets.

Once Flutter and backend code exist, update this README with the exact install, analyze, test, run, and deployment commands.

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

## Verification

Current docs-only gate:

```bash
bash scripts/check-docs.sh
```

Expected gates once implementation exists:

- `flutter analyze`
- `flutter test`
- Backend token broker unit tests
- Secret scan or equivalent check for standard OpenAI API key leakage
- Android emulator smoke check using `android-pixel9-headless`
- UI smoke coverage for all four supplied mockup surfaces
- Privacy routing test showing transcript Q&A does not call AWS transcript endpoints

## Documentation Maintenance

Every future change should update this README when setup, architecture, product behavior, issue status, verification steps, or known risks change. Product or architecture decision changes should also update [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md).

## Development Notes

Tom's Fedora machine has an Android SDK and boot-tested emulator available:

```bash
android-pixel9-headless
```

Use that instead of `emulator -no-window`, which segfaults on this machine.
