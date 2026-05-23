# Development Workflow

Use this as the operational handoff for future Codex, Cursor, and human implementation work.

## Start Of Every Job

1. Read [docs/live-translate-build-spec.md](live-translate-build-spec.md).
2. Read [../README.md](../README.md).
3. Read [../AGENTS.md](../AGENTS.md).
4. Read the relevant docs in this folder.
5. For UI or Flutter work, read [docs/mockup-ux-spec.md](mockup-ux-spec.md) and inspect every file in [../assets/mockups](../assets/mockups).
6. Inspect the relevant GitHub issue and its acceptance criteria.
7. Run:

```bash
git status --short --branch
```

## Issue-Driven Work

- Use existing issues #2-#19 for MVP work unless a new gap is genuinely not covered.
- Link implementation changes to the issue they complete or advance.
- Do not duplicate setup, docs, emulator, test, CI, privacy, or mockup work already covered by existing issues.
- Update issue comments or acceptance criteria when scope changes.
- Close issues only after the matching verification has run, or after skipped verification is documented with the exact blocker.

## Change Control

- Keep product and architecture decisions in [docs/live-translate-build-spec.md](live-translate-build-spec.md).
- Keep durable decision rationale in [docs/decision-log.md](decision-log.md).
- Do not drift from mockups or accepted architecture without recording a decision.
- Prefer narrow, reviewable changes over broad refactors.
- Preserve unrelated dirty files.

## Implementation Boundaries

Mobile app:

- Flutter, Android-first, iOS-compatible later.
- Direct OpenAI Realtime Translation connection using short-lived client secrets.
- Explicit microphone permission and app lifecycle state handling.
- Local encrypted transcript storage only for MVP.

Backend:

- AWS API Gateway + Lambda token broker only.
- Validate identity/session before issuing short-lived OpenAI client secrets.
- Do not receive, log, persist, or proxy transcript/audio content.

OpenAI:

- Live translation model: `gpt-realtime-translate`.
- Verify current Realtime Translation language support during implementation.
- Keep transcript Q&A direct or otherwise privacy-preserving so AWS never sees transcript content.

## Documentation Update Matrix

- Update [../README.md](../README.md) when setup, architecture, behavior, issue status, verification, or risks change.
- Update [docs/live-translate-build-spec.md](live-translate-build-spec.md) for product or architecture decisions.
- Update [docs/mockup-ux-spec.md](mockup-ux-spec.md) only for mockup interpretation or supplied asset changes.
- Update [docs/architecture.md](architecture.md) for runtime boundary or data-flow changes.
- Update [docs/environment.md](environment.md) for setup, SDK, emulator, or environment contract changes.
- Update [docs/testing-strategy.md](testing-strategy.md) for test gates and smoke-check changes.
- Update [docs/decision-log.md](decision-log.md) for durable decisions.

## Handoff Checklist

Before finishing:

1. Run the appropriate validation commands.
2. Run `git status --short --branch`.
3. Inspect the diff for accidental product/spec drift or secrets.
4. Update relevant GitHub issues.
5. Commit the intentional files.
6. Push only when requested and when the branch is not behind `origin/main`.
