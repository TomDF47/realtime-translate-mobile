# Codex Starter Prompt

Use this for the first implementation pass after the supplied mockup UX spec is committed.

```text
You are working in /home/tom/projects/realtime-translate-mobile.

Build the first implementation of an Android-first Flutter app for live speech translation.

Required first reads:
- AGENTS.md
- docs/live-translate-build-spec.md
- README.md
- docs/development-workflow.md
- docs/architecture.md
- docs/v2-future-scope.md
- docs/cybersecurity-report.md
- docs/environment.md
- docs/testing-strategy.md
- docs/decision-log.md
- docs/mockup-ux-spec.md
- all four files in assets/mockups/

Product decisions:
- Flutter mobile app, Android-first, iOS-compatible later.
- MVP is phone-only aside from direct OpenAI API calls.
- No AWS, Lambda, token broker, app backend, cloud identity gate, cloud sync, server mailer, or server-side transcript handling in MVP.
- Preferred realtime voice/translation model: `gpt-realtime-translate` on `/v1/realtime/translations` for normal live translation; keep `gpt-realtime-2` only as an explicit compatibility/experimental voice-agent profile.
- AI chat must be scoped explicitly to This meeting or All meetings.
- Meetings, transcripts, summaries, generated exports, recipient preferences, sensitive preferences, and credential/session material are local encrypted device storage only.
- Generated exports stay in app until explicit Copy; no outbound mail backend.
- Summary export product intent is GPT-5.5 with xhigh reasoning; verify current OpenAI API support before coding.

Important machine detail:
- Use `android-pixel9-headless` for emulator testing.
- Do not use `emulator -no-window`; it segfaults on this Fedora/KDE/Wayland setup.

Implementation expectations:
- Use docs/mockup-ux-spec.md as the visual and interaction source of truth.
- Adapt the welcome/sign-in mockup to the revised phone-only MVP; provider sign-in is V2/future.
- Implement the supplied mockup-derived surfaces plus phone-local meeting management and generated export controls.
- Keep the UI clean, premium, and executive-grade.
- Do not turn the first screen into a technical control panel.
- Create a pragmatic Flutter project structure suitable for Android now and iOS later.
- Add clear setup docs and environment placeholders.
- Add tests appropriate for the implemented scope.
- Verify with Flutter analysis/tests and an Android emulator smoke check where feasible.
- Add dependency/advisory and secret-safety checks once package versions exist.
- Update README and relevant docs in the same change when setup, behavior, architecture, verification, risks, or issue status change.
```
