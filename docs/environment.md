# Environment

This repo does not yet contain a Flutter scaffold, app package manifest, lockfile, or backend implementation. Use this document as the setup contract for future implementation work and keep it current as commands become real.

## Current Local Setup

Docs-only validation:

```bash
bash scripts/check-docs.sh
```

Android emulator available on Tom's Fedora machine:

```bash
android-pixel9-headless
```

Do not use:

```bash
emulator -no-window
```

It is known to segfault on this Fedora/KDE/Wayland setup.

## Expected Tooling Once Implementation Exists

- Flutter SDK, stable channel.
- Android SDK and platform tools.
- Java toolchain compatible with the chosen Android Gradle plugin.
- A GitHub CLI session for issue and PR maintenance.
- Dependency/advisory tooling for Dart/Flutter and native mobile package checks once lockfiles exist.

Expected Android environment variables:

```bash
ANDROID_HOME=/path/to/android-sdk
ANDROID_SDK_ROOT=/path/to/android-sdk
JAVA_HOME=/path/to/jdk
```

Document the exact known-good values or discovery commands here once the Flutter scaffold is created.

## Environment Placeholders

Use [.env.example](../.env.example) as a placeholder contract only. It must never contain real credentials.

Mobile-safe values may include app environment names, package names, model intent names, and local feature flags. Do not add standard OpenAI API keys, cloud identity secrets, cookies, signing keys, keystores, or tokens to committed config.

Important placeholders:

- `OPENAI_REALTIME_MODEL`: expected default is `gpt-realtime-translate`.
- `OPENAI_SUMMARY_MODEL_INTENT`: product intent is GPT-5.5 for meeting summaries.
- `OPENAI_SUMMARY_REASONING_INTENT`: product intent is extra-high reasoning for meeting summaries.

Implementation must verify current OpenAI API model, reasoning parameter, realtime, and direct mobile credential/session support before coding against these intent values.

## Deferred V2 Configuration

The MVP does not use AWS, Lambda, token broker endpoints, Google/Microsoft sign-in, cloud sync, or backend OpenAI key storage. Do not add active MVP setup requirements for those systems. If future work reintroduces them, update [docs/v2-future-scope.md](v2-future-scope.md), [docs/decision-log.md](decision-log.md), this file, and the GitHub issue map first.

## Secret Handling Rules

- Do not commit `.env`, `.env.*`, OpenAI credentials, local AWS credentials, keystores, signing certificates, tokens, cookies, real account IDs that grant access, or real API keys.
- Do not include a standard OpenAI API key in Flutter source, assets, tests, screenshots, build outputs, or mobile config.
- If implementation uses user-provided OpenAI credential material, store it only in encrypted local storage and provide a clear remove/reset path.
- Redact OpenAI credential/session material, tokens, recipient lists, transcript content, prompts, summaries, and translated text from logs, screenshots, analytics, crash reports, and test output.
