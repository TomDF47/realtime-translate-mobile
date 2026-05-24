# Cybersecurity Report

Report date/time: 2026-05-24 08:15:01 AWST (Australia/Perth, UTC+08:00)

Scope: first Flutter scaffold dependency baseline for the phone-only MVP. The repo now contains Flutter Android/iOS scaffold files, package manifests, a lockfile, Android Gradle build files, placeholder-only environment config, and local signing placeholders.

## Executive Summary

The Flutter scaffold introduces pinned Dart package versions in `pubspec.lock`, Android Gradle build tooling, and a local signing placeholder. No app backend, AWS/Lambda token broker, cloud identity, cloud sync, server mailer, OpenAI integration, microphone permission, transcript storage, analytics, or crash reporting code has been added.

Current result: no known vulnerabilities or GitHub advisory hits were found for the introduced Pub packages or checked Maven build-tool packages during this pass. The repo still must rerun this report whenever package versions or build tooling change.

## MVP Security Posture

- Phone-only MVP aside from future direct OpenAI API calls.
- No AWS, Lambda, token broker, app backend, cloud sync, server mailer, or server-side transcript handling.
- Local encrypted storage is required for meetings, transcripts, summaries, recipient preferences, sensitive preferences, and credential/session material once implementation exists.
- Direct OpenAI API calls are the only routine product network path.
- Email export is user initiated and should use device-native mail/share composer semantics where practical.
- Logs, analytics, crash reports, screenshots, diagnostics, and tests must exclude transcript, audio, prompt, summary, recipient, export, and OpenAI credential/session payloads.

## Repository Dependency State

Dependency manifests and build files now present:

```bash
pubspec.yaml
pubspec.lock
android/settings.gradle.kts
android/build.gradle.kts
android/app/build.gradle.kts
android/gradle/wrapper/gradle-wrapper.properties
```

Primary versions introduced:

| Component | Version | Source |
| --- | --- | --- |
| Flutter SDK | 3.44.0 stable | local SDK at `/home/tom/.local/share/flutter` |
| Dart SDK | 3.12.0 | Flutter SDK |
| Android Gradle Plugin | 9.0.1 | `android/settings.gradle.kts` |
| Kotlin Android Gradle plugin | 2.3.20 | `android/settings.gradle.kts` |
| Gradle wrapper | 9.1.0 | `android/gradle/wrapper/gradle-wrapper.properties` |
| Android Build Tools | 36.0.0 | local Android SDK installed during first debug build |
| Android NDK | 28.2.13676358 | local Android SDK installed during first debug build |
| CMake | 3.22.1 | local Android SDK installed during first debug build |
| `cupertino_icons` | 1.0.9 | `pubspec.lock` |
| `flutter_lints` | 6.0.0 | `pubspec.lock` |

`pubspec.lock` also pins 23 hosted transitive Pub packages for Flutter and test tooling. SDK packages `flutter`, `flutter_test`, and `sky_engine` come from the Flutter SDK rather than pub.dev hosted packages.

## Vulnerability Check Log

| Date conducted | Source | Target | Result |
| --- | --- | --- | --- |
| 2026-05-24 AWST | `flutter pub get` | Pub dependency resolution | Completed with no advisory warning in command output. |
| 2026-05-24 AWST | `flutter pub outdated` | Current Pub dependency graph | Direct dependencies and dev dependencies are up to date. SDK-pinned transitive packages `meta`, `matcher`, `test_api`, and `vector_math` have newer latest versions but are not currently resolvable/upgradable outside the SDK graph. |
| 2026-05-24 AWST | OSV query batch API | All hosted Pub packages from `dart pub deps --json` | `vulnerable_count: 0`. |
| 2026-05-24 AWST | GitHub Advisory Database REST API | All hosted Pub packages from `dart pub deps --json` using `ecosystem=pub&affects=<package>` | 0 advisory hits for each hosted package. |
| 2026-05-24 AWST | OSV query batch API | Maven build tooling: `com.android.tools.build:gradle` 9.0.1, Kotlin Gradle plugin 2.3.20 | `vulnerable_count: 0`. |
| 2026-05-24 AWST | GitHub Advisory Database REST API | Maven build tooling: Android Gradle Plugin and Kotlin Gradle plugin | 0 advisory hits. |
| 2026-05-24 AWST | NVD | Dart/Flutter package graph | Not mapped because Pub package advisories are better covered by OSV/GitHub Advisory Database and no credible CPE mapping exists for the locked Pub packages. |

## Dependency And Supply-Chain Notes

- `android/key.properties.example` contains placeholders only.
- `android/key.properties` is ignored and must remain local/uncommitted.
- No standard OpenAI API key, client secret, token broker URL, AWS config, Google/Microsoft sign-in config, keystore, or certificate has been added.
- The Flutter scaffold includes Android and iOS platform code only; there is no app-owned network endpoint.
- Future dependency additions must include lockfile updates, advisory checks, and this report update before issue closure.

## Required Rerun Trigger

Rerun this report and record package-specific results when any of these change:

- `pubspec.yaml`
- `pubspec.lock`
- Android Gradle plugin, Kotlin plugin, Gradle wrapper, or Android SDK target versions
- iOS `Podfile`, `Podfile.lock`, or Swift package files
- JavaScript/TypeScript package manifests or lockfiles
- Python, Ruby, Rust, Go, Java, or other dependency manifests
- CI workflow actions with pinned versions
- Any binary/mobile SDK added to the repo

## Future Check Methodology

For each package or tool version introduced:

1. Record package name, ecosystem, version, source file, and date checked.
2. Query OSV where ecosystem mapping exists.
3. Query GitHub Advisory Database, especially for Dart/Flutter `pub` packages.
4. Check Dart/pub advisory output from dependency resolution.
5. Check NVD for platform/native dependencies where CPE mapping is credible.
6. Review package changelog, release notes, and security page for manually disclosed issues not yet indexed.
7. Record result, severity, mitigation, owner, and next review trigger.

## MVP Cybersecurity Acceptance Criteria

- No committed or bundled standard OpenAI API key.
- No app backend or server-side transcript handling.
- Direct OpenAI API only for routine product network traffic.
- Encrypted local storage for meetings, transcripts, summaries, recipients, sensitive preferences, and credential/session material.
- Explicit AI chat scope: `This meeting` or `All meetings`.
- Email export avoids an app-operated outbound mail backend.
- Mobile permissions are minimized and justified.
- Dependency versions are pinned and checked before merge once implementation exists.
- Logs, analytics, crash reports, screenshots, diagnostics, and tests exclude sensitive content.

## Open Security Risks To Resolve During Implementation

- Current OpenAI-supported direct mobile credential/session approach must be verified before coding.
- The final summary model and reasoning parameter names must be verified against current OpenAI API docs before coding.
- Local encrypted storage package choice must be checked for maintenance, platform support, and advisories.
- Any crash reporting or analytics SDK should be deferred unless a strong need and redaction/consent model are documented.
- Native email/share composer behavior must be tested so transcript exports are user initiated and not silently sent by the app.
