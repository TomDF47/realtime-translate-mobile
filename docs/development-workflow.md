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

- Use existing issues #2-#22 for MVP work unless a new gap is genuinely not covered.
- Treat #4 and #5 as V2/future unless a later accepted decision restores cloud identity or backend scope to MVP.
- Link implementation changes to the issue they complete or advance.
- Do not duplicate setup, docs, emulator, test, CI, privacy, cybersecurity, meeting, export, or mockup work already covered by existing issues.
- Update issue comments or acceptance criteria when scope changes.
- Close issues only after the matching verification has run, or after skipped verification is documented with the exact blocker.

## Change Control

- Keep product and architecture decisions in [docs/live-translate-build-spec.md](live-translate-build-spec.md).
- Keep durable decision rationale in [docs/decision-log.md](decision-log.md).
- Keep deferred cloud/backend/auth ideas in [docs/v2-future-scope.md](v2-future-scope.md).
- Do not drift from mockups or accepted architecture without recording a decision.
- Prefer narrow, reviewable changes over broad refactors.
- Preserve unrelated dirty files.

## Implementation Boundaries

Mobile app:

- Flutter, Android-first, iOS-compatible later.
- Phone-only MVP aside from direct OpenAI API calls.
- Explicit microphone permission and app lifecycle state handling.
- Local encrypted meeting, transcript, summary, recipient, preference, and credential/session storage only for MVP.
- User-initiated email export through device-native mail/share composer semantics where practical.

Backend/cloud:

- No app backend in MVP.
- No AWS API Gateway, Lambda, token broker, cloud sync, cloud identity gate, server mailer, or server-side transcript handling in MVP.
- V2/future backend/auth work must update source-of-truth docs and issues before implementation.

OpenAI:

- Live translation model: `gpt-realtime-translate`.
- Direct phone-to-OpenAI API calls only.
- Verify current Realtime Translation language support, direct mobile credential/session support, and summary model/reasoning support during implementation.
- Keep AI chat scoped explicitly to `This meeting` or `All meetings`.

Cybersecurity:

- Treat cybersecurity as an acceptance criterion, not a post-implementation cleanup.
- Minimize mobile permissions.
- Pin dependencies through lockfiles once implementation exists.
- Check dependency advisories before merging package changes.
- Keep logs, analytics, crash reports, screenshots, and test output free of transcript, audio, prompt, summary, recipient, and OpenAI credential/session material.

## Documentation Update Matrix

- Update [../README.md](../README.md) when setup, architecture, behavior, issue status, verification, or risks change.
- Update [docs/live-translate-build-spec.md](live-translate-build-spec.md) for product or architecture decisions.
- Update [docs/mockup-ux-spec.md](mockup-ux-spec.md) only for mockup interpretation, supplied asset changes, or accepted UI behavior changes.
- Update [docs/architecture.md](architecture.md) for runtime boundary or data-flow changes.
- Update [docs/v2-future-scope.md](v2-future-scope.md) when deferred cloud/backend/auth scope changes.
- Update [docs/cybersecurity-report.md](cybersecurity-report.md) when dependency state, package versions, vulnerability checks, or security baseline findings change.
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
