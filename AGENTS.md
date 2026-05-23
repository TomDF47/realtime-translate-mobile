# AGENTS.md

This repo is a planning and implementation workspace for an Android-first Flutter app for live translation. Every Codex job in this repository must start from the canonical build spec and preserve the privacy architecture.

## Required Reading Order

1. Read [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md) first. Treat it as the canonical product, architecture, privacy, and implementation spec.
2. Read [README.md](README.md) next. Keep it accurate whenever setup, architecture, product behavior, issue status, verification steps, or known risks change.
3. Read the relevant handoff docs before editing:
   - [docs/development-workflow.md](docs/development-workflow.md) for agent workflow, issue handling, and handoff rules.
   - [docs/architecture.md](docs/architecture.md) for Flutter, AWS, OpenAI, storage, and privacy boundaries.
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
- Do not scaffold Flutter, AWS, auth, or OpenAI integration unless the active issue asks for it.
- If a task uncovers a new implementation gap, update an existing focused issue or create one instead of burying it in an unrelated change.
- Commit only the intentional files for the completed task.

## Source Of Truth

- Canonical build spec: [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md)
- Mockup UX interpretation: [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md)
- Supplied Android mockups: [assets/mockups](assets/mockups)
- Current repo status and issue map: [README.md](README.md)
- Architecture boundaries: [docs/architecture.md](docs/architecture.md)
- Durable decisions: [docs/decision-log.md](docs/decision-log.md)

If the spec, README, mockup spec, and issue disagree, stop and reconcile the source-of-truth docs before implementing.

## Non-Negotiable Architecture Rules

- Mobile app: Flutter, Android-first, structured to remain iOS-compatible later.
- Backend: minimal AWS API Gateway + Lambda token broker only.
- OpenAI connection: the mobile app connects directly to OpenAI using short-lived client secrets.
- Main translation model: `gpt-realtime-translate`.
- Never embed a standard OpenAI API key in mobile code, mobile config, assets, build outputs, or tests.
- AWS must never receive, log, persist, or proxy transcript/audio content.
- Transcript Q&A must use a direct OpenAI path or another privacy-preserving path that avoids AWS seeing transcript content.
- User transcript data must stay in encrypted local device storage only for the MVP.
- Logs, analytics, crashes, and diagnostics must redact secrets and exclude audio/transcript payloads.

## Privacy And Security Gate

Every change must protect these boundaries:

- No standard OpenAI API keys in mobile source, mobile config, assets, build outputs, tests, logs, or screenshots.
- No transcript, prompt, translated text, microphone audio, or audio-derived payload may be sent to AWS.
- AWS token broker endpoints may validate identity and issue short-lived OpenAI client secrets only.
- Local transcript history and sensitive preferences must be encrypted on device when implementation exists.
- Tests should include negative assertions for transcript routing and secret leakage when code exists.
- Documentation examples must use placeholders only. Do not commit real credentials, tokens, account IDs that grant access, cookies, or local secrets.

## Mockup And UX Discipline

- Treat the four supplied Android mockups and [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md) as the UI source of truth for the first Flutter pass.
- Do not drift from the mockups or product spec without recording the decision in [docs/decision-log.md](docs/decision-log.md).
- Update [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md) for product or architecture decision changes.
- Update [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md) only when mockup interpretation, supplied assets, or accepted UI behavior changes.
- Keep the first screen focused on the usable live translation product, not a technical dashboard.

## Documentation Maintenance

- Update `README.md` in the same change whenever setup commands, app architecture, product behavior, issue status, verification commands, or known risks change.
- Update `docs/live-translate-build-spec.md` whenever a product or architecture decision changes.
- Update `docs/architecture.md` when module boundaries, runtime data flow, or privacy boundaries change.
- Update `docs/environment.md` when setup commands, required SDKs, environment placeholders, or emulator guidance change.
- Update `docs/testing-strategy.md` when verification commands, test gates, or manual smoke expectations change.
- Update `docs/decision-log.md` for durable decisions that future agents should not re-litigate.
- Keep GitHub issues current: close completed work only after matching verification has run or the skipped verification reason is documented.

## Verification Expectations

- Run `git status --short --branch` before and after changes.
- For docs-only changes, run `bash scripts/check-docs.sh` when the script is present.
- Once Flutter exists, run `flutter analyze` and `flutter test` for app changes.
- Once backend code exists, run the relevant Lambda/unit tests for broker changes.
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
