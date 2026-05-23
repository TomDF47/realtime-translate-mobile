# Realtime Translate Mobile

Android-first Flutter app for live speech translation, designed to stay iOS-compatible.

## Decision Record

- Mobile app: Flutter, Android-first, iOS-compatible later
- Backend: Minimal AWS API Gateway + Lambda token broker
- OpenAI connection: App connects directly to OpenAI using short-lived client secrets
- Main translation model: `gpt-realtime-translate`
- Transcript Q&A: Prefer a direct OpenAI path that avoids AWS seeing transcript content
- Data storage: Local encrypted device storage only

## Product Direction

The app should feel premium, clean, and executive-grade. The first usable surface should be the live translation experience, not a technical dashboard. Treat the backend as a narrow security component whose only job is issuing short-lived OpenAI client secrets after identity checks.

## Current Status

Planning repo created. Mockups are pending before frontend implementation starts.

## Development Notes

Tom's Fedora machine has an Android SDK and boot-tested emulator available:

```bash
android-pixel9-headless
```

Use that instead of `emulator -no-window`, which segfaults on this machine.

