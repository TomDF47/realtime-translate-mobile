# AGENTS.md

This repo is a planning and implementation workspace for an Android-first Flutter app for live translation. Every Codex job in this repository must start by reading the canonical build spec.

## Required Reading Order

1. Read [docs/live-translate-build-spec.md](docs/live-translate-build-spec.md) first. Treat it as the canonical product, architecture, privacy, and implementation spec.
2. Read [README.md](README.md) next. Keep it accurate whenever setup, architecture, product behavior, issue status, or verification steps change.
3. For any UI, Flutter, design-system, or interaction work, read [docs/mockup-ux-spec.md](docs/mockup-ux-spec.md) and inspect all files in [assets/mockups](assets/mockups).
4. Check the relevant GitHub issues and keep implementation aligned to issue scope and acceptance criteria.

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

## Documentation Maintenance

- Update `README.md` in the same change whenever setup commands, app architecture, product behavior, issue status, verification commands, or known risks change.
- Update `docs/live-translate-build-spec.md` whenever a product or architecture decision changes.
- Update `docs/mockup-ux-spec.md` only when the mockup interpretation or supplied assets change.
- Keep GitHub issues current: close completed work, update acceptance criteria when scope changes, and create focused issues for newly discovered implementation gaps.

## Verification Expectations

- Run `git status --short --branch` before and after changes.
- For Android emulator checks on Tom's Fedora machine, use `android-pixel9-headless`.
- Do not use `emulator -no-window`; it is known to segfault on this machine.
- Document any verification command that could not be run and why.
