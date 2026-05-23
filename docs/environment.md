# Environment

This repo does not yet contain a Flutter scaffold or Lambda implementation. Use this document as the setup contract for future implementation work and keep it current as commands become real.

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
- AWS CLI or deployment tooling for the token broker.
- A GitHub CLI session for issue and PR maintenance.

Expected Android environment variables:

```bash
ANDROID_HOME=/path/to/android-sdk
ANDROID_SDK_ROOT=/path/to/android-sdk
JAVA_HOME=/path/to/jdk
```

Document the exact known-good values or discovery commands here once the Flutter scaffold is created.

## Environment Placeholders

Use [.env.example](../.env.example) as a placeholder contract only. It must never contain real credentials.

Mobile-safe values may include public client IDs, package names, issuer URLs, broker base URLs, and model names. Backend-only secrets must stay in backend secret storage or uncommitted local env files.

Important placeholders:

- `OPENAI_REALTIME_MODEL`: expected default is `gpt-realtime-translate`.
- `TOKEN_BROKER_BASE_URL`: API Gateway or local broker endpoint.
- `MICROSOFT_CLIENT_ID`: public app registration client ID placeholder.
- `GOOGLE_ANDROID_CLIENT_ID`: public Android OAuth client ID placeholder.
- `BACKEND_OPENAI_API_KEY`: backend/Lambda local-only placeholder. Never copy this into mobile code.

## Auth Configuration Notes

Microsoft:

- App registration must support Microsoft personal accounts and work/school organizational accounts.
- Final tenant/account-type values are still open and must be documented before auth implementation closes.

Google:

- Android credentials must match package name and signing certificate.
- Final package name and signing certificate are still open.

## Secret Handling Rules

- Do not commit `.env`, `.env.*`, local AWS credentials, keystores, signing certificates, tokens, cookies, or real API keys.
- Do not include a standard OpenAI API key in Flutter source, assets, tests, build outputs, or mobile config.
- Use backend secret storage/config for the standard OpenAI API key.
- Use short-lived OpenAI client secrets for the mobile app.
- Redact tokens and client secrets from logs and screenshots.
