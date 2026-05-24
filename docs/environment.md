# Environment

This repo now contains a Flutter scaffold, Android/iOS project shells, a package manifest, and a lockfile. Use this document as the setup contract and keep it current as commands change.

## Current Local Setup

Flutter SDK installed for this workspace:

```bash
/home/tom/.local/share/flutter
```

Current verified versions:

- Flutter 3.44.0 stable
- Dart 3.12.0
- Android SDK 37.0.0 at `/home/tom/Android/Sdk`
- Android Build Tools 36.0.0 installed during first debug build
- Android NDK 28.2.13676358 installed during first debug build
- CMake 3.22.1 installed during first debug build
- Java Temurin 21 at `/home/tom/.local/share/jdks/temurin-21`
- Android Gradle Plugin 9.0.1
- Kotlin Android Gradle plugin 2.3.20
- Gradle wrapper 9.1.0

Set Flutter on `PATH` for local commands:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
```

Validation:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
flutter pub get
flutter analyze
flutter test
bash scripts/check-docs.sh
bash scripts/check-supply-chain.sh
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

Android environment variables verified by `flutter doctor -v`:

```bash
ANDROID_HOME=/home/tom/Android/Sdk
ANDROID_SDK_ROOT=/home/tom/Android/Sdk
JAVA_HOME=/home/tom/.local/share/jdks/temurin-21
```

Flutter doctor still reports missing Chrome and Linux desktop dependencies. Those do not block the Android-first MVP workflow.

## Android Smoke Sequence

Use Tom's emulator launcher:

```bash
android-pixel9-headless
```

Then, in a second shell:

```bash
export PATH=/home/tom/.local/share/flutter/bin:$PATH
adb devices
flutter devices
flutter run -d <android-emulator-id>
```

For a screenshot artifact during issue closure, write it outside the repo unless the issue explicitly asks for committed evidence:

```bash
adb exec-out screencap -p > /tmp/live-translate-mobile-smoke.png
```

Expected current smoke result: the `Live Translate` phone-local start surface renders with `Start new meeting`, `Open meeting history`, `OpenAI setup`, the on-device privacy note, and the `Secure & Private` / `Android MVP` footer badges. Starting a meeting without a saved credential shows `OpenAI setup required` before microphone permission or live resources open. The OpenAI setup sheet accepts a user-provided credential, stores it through encrypted local storage, does not redisplay the saved value, and supports removal. After a local credential is configured, starting a meeting requests Android microphone permission before showing the mock live session; denied permission shows the `Microphone access needed` state and no live session opens. After permission is granted, the mock meeting is written through the encrypted local repository, appears in meeting history with stored metadata, can be reopened to append local history, can be deleted locally, can open AI chat for `This meeting` or `All meetings`, and can prepare a Transcript export for Android native share handoff. Summary/Both export remains visibly pending until direct OpenAI summary generation exists.

UI smoke checks should additionally cover the teal listening screen after local credential setup, scoped AI chat sheet for both scopes, amber read-aloud-paused screen, meeting history continue/delete controls, email export recipient preference surface, and transcript share intent launch when safe to do without capturing export payload screenshots. Real microphone capture, direct OpenAI realtime streaming, live OpenAI API-key smoke, real summary generation, production-volume storage behavior, and iOS share handoff remain future implementation checks.

## Environment Placeholders

Use [.env.example](../.env.example) as a placeholder contract only. It must never contain real credentials.

Mobile-safe values may include app environment names, package names, model intent names, and local feature flags. Do not add standard OpenAI API keys, cloud identity secrets, cookies, signing keys, keystores, or tokens to committed config.

Important placeholders:

- `OPENAI_REALTIME_MODEL`: expected default is `gpt-realtime-2`.
- `OPENAI_TRANSLATION_FALLBACK_MODEL`: dedicated translation fallback/profile is `gpt-realtime-translate`.
- `OPENAI_SUMMARY_MODEL_INTENT`: product intent is GPT-5.5 for meeting summaries.
- `OPENAI_SUMMARY_REASONING_INTENT`: product intent is `xhigh` reasoning for meeting summaries.
- `ANDROID_PACKAGE_NAME`: current scaffold value is `com.tomdf47.realtime_translate_mobile`.

Implementation must verify current OpenAI API model, reasoning parameter, and realtime endpoint behavior before coding against these intent values. #23 accepted user-provided OpenAI credential/session material stored only in encrypted local device storage; no key may be committed, bundled, logged, or captured in screenshots.

## Android Signing Placeholders

Debug builds use the standard local Android debug signing flow.

For local release-signing experiments only, copy:

```bash
cp android/key.properties.example android/key.properties
```

Then fill `android/key.properties` with local, uncommitted values. Do not commit `android/key.properties`, keystores, signing passwords, or certificates.

## Deferred V2 Configuration

The MVP does not use AWS, Lambda, token broker endpoints, Google/Microsoft sign-in, cloud sync, or backend OpenAI key storage. Do not add active MVP setup requirements for those systems. If future work reintroduces them, update [docs/v2-future-scope.md](v2-future-scope.md), [docs/decision-log.md](decision-log.md), this file, and the GitHub issue map first.

## Secret Handling Rules

- Do not commit `.env`, `.env.*`, OpenAI credentials, local AWS credentials, keystores, signing certificates, tokens, cookies, real account IDs that grant access, or real API keys.
- Do not include a standard OpenAI API key in Flutter source, assets, tests, screenshots, build outputs, or mobile config.
- If implementation uses user-provided OpenAI credential material, store it only in encrypted local storage and provide a clear remove/reset path.
- Redact OpenAI credential/session material, tokens, recipient lists, transcript content, prompts, summaries, and translated text from logs, screenshots, analytics, crash reports, and test output.
