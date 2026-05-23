# Codex Starter Prompt

Use this for the first implementation pass after the supplied mockup UX spec is committed.

```text
You are working in /home/tom/projects/realtime-translate-mobile.

Build the first implementation of an Android-first Flutter app for live speech translation.

Product decisions:
- Flutter mobile app, Android-first, iOS-compatible later.
- Minimal AWS API Gateway + Lambda backend as a token broker only.
- Mobile app connects directly to OpenAI using short-lived client secrets.
- Main translation model: gpt-realtime-translate.
- Transcript Q&A should avoid AWS seeing transcript content.
- Storage is local encrypted device storage only.
- Sign-in must support Microsoft personal, Microsoft organisational, and Google accounts.

Important machine detail:
- Use `android-pixel9-headless` for emulator testing.
- Do not use `emulator -no-window`; it segfaults on this Fedora/KDE/Wayland setup.

Implementation expectations:
- Use docs/mockup-ux-spec.md as the visual and interaction source of truth.
- Implement the four supplied surfaces: welcome/sign-in, teal listening live translation, transcript assistant bottom sheet, and amber speaking/paused read-aloud mode.
- Keep the UI clean, premium, and executive-grade.
- Do not turn the first screen into a technical control panel.
- Create a pragmatic Flutter project structure suitable for Android now and iOS later.
- Add clear setup docs and environment placeholders.
- Add tests appropriate for the implemented scope.
- Verify with Flutter analysis/tests and an Android emulator smoke check where feasible.
```
