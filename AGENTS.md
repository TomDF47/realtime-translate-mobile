# AGENTS.md

This repo is a planning and implementation workspace for an Android-first Flutter app for live translation. Every Codex job in this repository must start from the canonical build spec and preserve the phone-only MVP privacy architecture.

## Required Reading Order

1. Read [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md) first. Treat it as the canonical product, architecture, privacy, security, and implementation spec.
2. Read [README.md](README.md) next. Keep it accurate whenever setup, architecture, product behavior, issue status, verification steps, or known risks change.
3. Read the relevant handoff docs before editing:
   - [docs/development-workflow.md](docs/development-workflow.md) for agent workflow, issue handling, and handoff rules.
   - [docs/architecture.md](docs/architecture.md) for Flutter, OpenAI, storage, email export, and privacy boundaries.
   - [docs/v2-future-scope.md](docs/v2-future-scope.md) before touching cloud/backend/auth ideas.
   - [docs/cybersecurity-report.md](docs/cybersecurity-report.md) before dependency, package, permission, logging, diagnostics, or security-sensitive work.
   - [docs/environment.md](docs/environment.md) for local setup and secret handling.
   - [docs/testing-strategy.md](docs/testing-strategy.md) for validation expectations.
   - [docs/decision-log.md](docs/decision-log.md) before changing product or architecture decisions.
4. For any UI, Flutter, design-system, accessibility, or interaction work, read [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md) and inspect every file in [assets/mockups](assets/mockups).
5. Check the relevant GitHub issues and keep implementation aligned to issue scope and acceptance criteria.

Do not start implementation, refactors, or repo-contract edits until the relevant pre-read is complete.

## Operating Workflow

- Run `git status --short --branch` before editing and again before handoff.
- Inspect existing docs, code, and issue context before changing files.
- Keep changes narrow and reviewable. Do not replace specific planning docs with generic boilerplate.
- Preserve unrelated user changes in the working tree. Never revert, delete, reformat, stage, or commit unrelated files.
- Do not scaffold Flutter, cloud auth, AWS, backend, or OpenAI integration unless the active issue asks for it.
- If a task uncovers a new implementation gap, update an existing focused issue or create one instead of burying it in an unrelated change.
- Commit only the intentional files for the completed task.

## Source Of Truth

- Canonical build spec: [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md)
- Mockup UX interpretation: [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md)
- Supplied Android mockups: [assets/mockups](assets/mockups)
- Current repo status and issue map: [README.md](README.md)
- Architecture boundaries: [docs/architecture.md](docs/architecture.md)
- V2/future scope: [docs/v2-future-scope.md](docs/v2-future-scope.md)
- Cybersecurity baseline: [docs/cybersecurity-report.md](docs/cybersecurity-report.md)
- Durable decisions: [docs/decision-log.md](docs/decision-log.md)

If the spec, README, mockup spec, decision log, and issue scope disagree, stop and reconcile the source-of-truth docs before implementing.

## Non-Negotiable Architecture Rules

- Mobile app: Flutter, Android-first, structured to remain iOS-compatible later.
- MVP backend: none.
- Routine network path: the phone app connects directly to the OpenAI API only.
- Preferred realtime voice/translation model: `gpt-realtime-2`, with `gpt-realtime-translate` kept as a dedicated translation fallback/profile if endpoint testing shows it is the better fit.
- AI chat scope must be explicit: `This meeting` or `All meetings`.
- Never embed a standard OpenAI API key in mobile code, mobile config, assets, build outputs, screenshots, or tests.
- User-provided OpenAI credential/session material may be stored only in encrypted local device storage; ask Tom for an API key only at the first real OpenAI network smoke/integration test.
- Do not add AWS API Gateway, Lambda, token broker, app backend, cloud sync, cloud identity gate, server mailer, or server-side transcript handling to the MVP.
- User meeting transcripts, summaries, recipient lists, sensitive preferences, and credential/session material must stay in encrypted local device storage only for the MVP.
- Logs, analytics, crashes, screenshots, diagnostics, and tests must redact secrets and exclude audio/transcript/prompt/summary/export payloads.
- Cybersecurity is a first-class acceptance criterion for every implementation change.

## Privacy And Security Gate

Every change must protect these boundaries:

- No standard OpenAI API keys in mobile source, config, assets, build outputs, tests, logs, screenshots, or committed docs.
- No transcript, prompt, translated text, summary, microphone audio, audio-derived payload, recipient list, or export payload may be sent to app-owned backend infrastructure.
- Direct OpenAI API calls are the only routine network path for product behavior.
- Email export must be user initiated and should use device-native mail/share composer semantics where practical; do not add an outbound mail backend.
- Local meeting history, transcript history, summaries, recipient preferences, sensitive preferences, and credential/session material must be encrypted on device when implementation exists.
- Mobile permissions must be minimized and justified.
- Dependency/package changes must include advisory and supply-chain checks once package versions exist.
- Tests should include negative assertions for transcript routing, secret leakage, and logging/diagnostics leakage when code exists.
- Documentation examples must use placeholders only. Do not commit real credentials, tokens, account IDs that grant access, cookies, local secrets, or screenshots containing sensitive content.

## Mockup And UX Discipline

- Treat the four supplied Android mockups and [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md) as the UI visual source of truth for the first Flutter pass.
- The MVP behavior is now phone-only. Provider sign-in buttons in the welcome mockup are V2/future unless a later accepted decision restores cloud identity to MVP.
- Do not drift from the mockups or product spec without recording the decision in [docs/decision-log.md](docs/decision-log.md).
- Update [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md) for product or architecture decision changes.
- Update [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md) only when mockup interpretation, supplied assets, or accepted UI behavior changes.
- Keep the first screen focused on starting or resuming live translation meetings, not a technical dashboard.

## Documentation Maintenance

- Update `README.md` in the same change whenever setup commands, app architecture, product behavior, issue status, verification commands, or known risks change.
- Update `docs/live-translate-build-spec.md` whenever a product or architecture decision changes.
- Update `docs/architecture.md` when module boundaries, runtime data flow, or privacy boundaries change.
- Update `docs/v2-future-scope.md` when deferred cloud/backend/auth scope changes.
- Update `docs/cybersecurity-report.md` when dependency/package state, vulnerability checks, security findings, or rerun triggers change.
- Update `docs/environment.md` when setup commands, required SDKs, environment placeholders, or emulator guidance change.
- Update `docs/testing-strategy.md` when verification commands, test gates, or manual smoke expectations change.
- Update `docs/decision-log.md` for durable decisions that future agents should not re-litigate.
- Keep GitHub issues current: close completed work only after matching verification has run or the skipped verification reason is documented.

## Verification Expectations

- Run `git status --short --branch` before and after changes.
- For docs-only changes, run `bash scripts/check-docs.sh` when the script is present.
- For docs-only changes, run `git diff --check`.
- Once Flutter exists, run `flutter analyze` and `flutter test` for app changes.
- Once dependencies exist, run the documented dependency/advisory checks.
- For Android emulator checks on Tom's Fedora machine, use `android-pixel9-headless`.
- Do not use `emulator -no-window`; it is known to segfault on this machine.
- Document any verification command that could not be run and why.

## Handoff

Final handoff notes should include:

- Files changed.
- Issues created, updated, or intentionally left open.
- Validation commands and results.
- Commit hash if a commit was created.
- Push result if pushing was requested.
- Follow-up work or blockers.
