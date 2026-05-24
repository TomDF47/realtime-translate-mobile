# Cybersecurity Report

Report date/time: 2026-05-24 13:43:59 AWST (Australia/Perth, UTC+08:00)

Scope: Flutter scaffold dependency baseline, Android microphone-permission lifecycle update, encrypted local meeting storage, centralized language support/fallback routing, phone-local OpenAI credential setup, privacy-safe diagnostics controls, direct realtime WebSocket and resilience scaffolding, scoped AI chat Responses API request scaffolding, direct meeting summary Responses API request scaffolding, Transcript/Summary/Both export with Android native share handoff, and local dependency/security gate for the phone-only MVP. The repo now contains Flutter Android/iOS scaffold files, package manifests, a lockfile, Android Gradle build files, placeholder-only environment config, local signing placeholders, native Android MethodChannels for runtime microphone permission and share-sheet launch, a platform-backed secure storage repository, a local OpenAI credential store, a local language support table, a no-op-by-default diagnostics allowlist/redaction helper, direct OpenAI realtime, resilience, AI chat, and summary gateway seams, a local transcript/summary export composer, and a repeatable local supply-chain script.

## Executive Summary

The Flutter scaffold introduces pinned Dart package versions in `pubspec.lock`, Android Gradle build tooling, and a local signing placeholder. The app declares Android `RECORD_AUDIO` permission and requests it at runtime through app-owned native Android code before opening the mock live-session surface. The storage implementation adds `flutter_secure_storage` for encrypted local meeting, transcript/history, summary text/metadata, recent language route, recipient preference, sensitive preference, and credential/session material storage. Android app backup is disabled in the manifest for the MVP data boundary. Language support now uses a local conservative realtime-target table and marks broader targets as direct-OpenAI fallback credential routes. OpenAI setup now stores/removes user-provided credential material only through encrypted local storage and does not redisplay the saved value. Direct realtime scaffolding now builds tested WebSocket session messages for the primary `gpt-realtime-2` profile and dedicated `gpt-realtime-translate` fallback/profile, keeps credentials in the Authorization header only, parses audio/transcript/error events without logging payloads, classifies direct credential/session expiry or rejection, unsupported-language, retryable network/socket, rate-limit, transient OpenAI, lifecycle-interruption, and fatal failures, and plans bounded jittered reconnect decisions. Retryable realtime decisions close microphone capture, realtime, and playback resources while the session is `reconnecting`; credential, offline, unsupported-language, and fatal decisions fail closed. Scoped AI chat now builds `This meeting` or `All meetings` transcript context locally and uses a direct OpenAI Responses request seam with `store: false` when a saved credential is available. Summary generation now builds a direct phone-to-OpenAI Responses request with `gpt-5.5`, `reasoning.effort: xhigh`, and `store: false`, keeps credentials in the Authorization header only, records only privacy-safe metadata diagnostics, and stores generated summary text/metadata only in encrypted local storage. Privacy-safe diagnostics are no-op by default and can only pass allowlisted state/configuration fields after redaction or omission. Transcript, Summary, and Both exports are composed locally and handed to the Android share sheet through an `ACTION_SEND` intent after a user tap. No app backend, AWS/Lambda token broker, cloud identity, cloud sync, server mailer, live OpenAI smoke result, real microphone capture, decoded translated-audio playback, analytics, crash reporting sink, or server-side diagnostics transport has been added.

Current result: no known vulnerabilities or GitHub advisory hits were found for the introduced Pub packages or checked Maven packages during this pass. `bash scripts/check-supply-chain.sh` checks for obvious credential leaks, validates the Android permission allowlist, and queries OSV for hosted Pub and Gradle/Maven runtime package versions; `.github/workflows/flutter.yml` now runs that gate with Flutter analysis/tests on pull requests and pushes to `main`. OpenAI Realtime credential verification found that official client-safe Realtime client secrets for web/mobile are minted by a developer-controlled server using a standard API key, but #23 closed with Tom's MVP decision to proceed phone-to-OpenAI directly using user-provided OpenAI credential/session material stored only in encrypted local device storage. Official docs verified on 2026-05-24 list `gpt-realtime-2` as the most capable realtime voice model and `gpt-realtime-translate` as a dedicated streaming speech-to-speech translation model; endpoint/API testing must decide the final runtime path without adding a backend. The OpenAI setup, realtime WebSocket and resilience scaffolding, diagnostics, AI chat request scaffolding, summary request scaffolding, and export slices added no new package dependencies and no live OpenAI API-key smoke. Realtime language support verification for #7 found no official target-language enum, so unsupported target fallback remains local UI/planning until direct OpenAI calls are implemented. The repo still must rerun this report whenever package versions or build tooling change.

## MVP Security Posture

- Phone-only MVP aside from future direct OpenAI API calls.
- No AWS, Lambda, token broker, app backend, cloud sync, server mailer, or server-side transcript handling.
- Android runtime microphone permission is gated before live translation surfaces; no real microphone capture implementation exists yet.
- Local encrypted storage now exists for meetings, transcripts, summaries, recipient preferences, sensitive preferences, and future credential/session material through `flutter_secure_storage`.
- OpenAI setup gates live-session start before microphone permission, stores credential material only in encrypted local storage, and supports reset/removal.
- Direct realtime scaffolding keeps credential material in the WebSocket Authorization header only, has no app-owned backend route, and has tests asserting the credential is absent from session update/audio/close message bodies.
- Direct realtime resilience scaffolding classifies failure categories, applies bounded backoff/jitter decisions, drives fail-closed session states, and logs only sanitized operation/result/error-code/retry/backoff fields.
- Scoped AI chat keeps prompt/request context local until a user sends it directly to OpenAI from the phone; request construction sets `store: false` and never routes through an app backend.
- Local diagnostics are no-op by default and must pass through field allowlisting, secret redaction, and payload omission before any sink records them.
- Transcript, Summary, and Both export is user initiated, composed locally, and handed to the Android native share sheet. Recipient preferences and generated summary text/metadata remain in encrypted local storage. Summary/Both uses the direct OpenAI Responses path only when a saved local credential is available.
- Direct OpenAI API calls are the only routine product network path.
- Email export is user initiated and should use device-native mail/share composer semantics where practical.
- Logs, analytics, crash reports, screenshots, diagnostics, and tests must exclude transcript, audio, prompt, summary, recipient, export, and OpenAI credential/session payloads.

## Repository Dependency State

Dependency manifests and build files now present:

```bash
pubspec.yaml
pubspec.lock
.github/workflows/docs.yml
.github/workflows/flutter.yml
android/settings.gradle.kts
android/build.gradle.kts
android/app/build.gradle.kts
android/gradle/wrapper/gradle-wrapper.properties
scripts/check-supply-chain.py
scripts/check-supply-chain.sh
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
| `flutter_secure_storage` | 10.3.0 | `pubspec.lock` |
| `flutter_secure_storage_android` | 4.1.0 | `pubspec.lock` |
| `flutter_secure_storage_darwin` | 0.3.2 | `pubspec.lock` |
| `com.google.crypto.tink:tink-android` | 1.21.0 | transitive Android dependency from `flutter_secure_storage_android` |
| `flutter_lints` | 6.0.0 | `pubspec.lock` |

`pubspec.lock` pins 56 hosted Pub packages after the secure-storage dependency addition. SDK packages `flutter`, `flutter_test`, `flutter_web_plugins`, and `sky_engine` come from the Flutter SDK rather than pub.dev hosted packages.

## Vulnerability Check Log

| Date conducted | Source | Target | Result |
| --- | --- | --- | --- |
| 2026-05-24 AWST | `flutter pub get` | Pub dependency resolution after adding `flutter_secure_storage` | Completed with no advisory warning in command output. |
| 2026-05-24 AWST | `flutter pub outdated` | Current Pub dependency graph | Direct dependencies and dev dependencies are up to date. SDK-pinned transitive packages `meta`, `matcher`, `test_api`, and `vector_math` have newer latest versions but are not currently resolvable/upgradable outside the SDK graph. |
| 2026-05-24 AWST | OSV query batch API | All 56 hosted Pub packages from `dart pub deps --json` | `vulnerable_count: 0`. |
| 2026-05-24 AWST | GitHub Advisory Database REST API | All hosted Pub packages from `dart pub deps --json` using `ecosystem=pub&affects=<package>` | 0 advisory hits for each hosted package. |
| 2026-05-24 AWST | OSV query batch API | Maven build tooling and secure-storage native dependency: `com.android.tools.build:gradle` 9.0.1, plugin buildscript AGP 8.13.2, Kotlin Gradle plugin 2.3.20, `com.google.crypto.tink:tink-android` 1.21.0 | `vulnerable_count: 0`. |
| 2026-05-24 AWST | GitHub Advisory Database REST API | Maven build tooling and `com.google.crypto.tink:tink-android` | 0 advisory hits. |
| 2026-05-24 AWST | `bash scripts/check-supply-chain.sh` | Secret patterns, Android permissions, 56 hosted Pub packages, and 51 Gradle/Maven runtime/build packages | Passed. No secret-like values found, `android.permission.RECORD_AUDIO` is the only Android permission, and OSV returned no vulnerabilities for 107 pinned package versions. |
| 2026-05-24 AWST | `.github/workflows/flutter.yml` | Pull requests and pushes to `main` | Added CI gate for `flutter pub get`, `flutter analyze`, `flutter test`, and `bash scripts/check-supply-chain.sh`. |
| 2026-05-24 AWST | NVD | Dart/Flutter package graph | Not mapped because Pub package advisories are better covered by OSV/GitHub Advisory Database and no credible CPE mapping exists for the locked Pub packages. |
| 2026-05-24 AWST | Manual review | Microphone permission lifecycle change | No third-party package added. Android `RECORD_AUDIO` is the only new mobile permission, requested at runtime through `MainActivity` before live-session UI opens. |
| 2026-05-24 AWST | Manual review | Encrypted local storage change | Storage uses `flutter_secure_storage` with Android KeyStore/iOS Keychain backing, app data backup disabled through `android:allowBackup="false"`, and no backend/cloud persistence path. |
| 2026-05-24 AWST | Manual review | OpenAI credential setup scaffolding | No dependency added. User-provided credential material is stored only through encrypted local storage, saved values are not redisplayed, live start is gated before microphone permission when missing, and tests use non-secret placeholder strings. |
| 2026-05-24 AWST | Manual review | Direct realtime WebSocket scaffolding | No dependency or permission added. The primary `gpt-realtime-2` profile and dedicated `gpt-realtime-translate` fallback/profile are configured without a backend route, credentials stay in the WebSocket Authorization header only, audio append bodies contain base64 PCM16 payloads without credential material, and tests use a local fake WebSocket server rather than a real OpenAI key. |
| 2026-05-24 AWST | Manual review | Direct realtime resilience scaffolding | No dependency, permission, backend route, or live OpenAI key added. Failure classification and reconnect planning use sanitized state/error labels only, bounded retry/backoff numbers are diagnostics-allowlisted, resources fail closed while reconnecting/offline/credential-invalid/error, and tests assert unsafe error codes are redacted from diagnostics. |
| 2026-05-24 AWST | Manual review | Privacy-safe diagnostics controls | No dependency added. Diagnostics are no-op by default, use explicit allowed fields, redact credential/session/email-like values, omit unapproved fields, and tests assert that credentials, prompts, transcript text, translated text, recipient emails, and request bodies do not appear in diagnostic records. |
| 2026-05-24 AWST | Manual review | Scoped AI chat Responses API request scaffolding | No dependency or permission added. AI chat context is assembled from encrypted local meetings for explicit `This meeting` or `All meetings` scope, the direct Responses request body uses `store: false`, credentials stay in the authorization header only, and tests use local fake HTTP/placeholder credentials rather than a real OpenAI key. |
| 2026-05-24 AWST | Manual review | Transcript export native share handoff | No dependency or permission added. Transcript export is user initiated, recipient preferences are stored through encrypted local storage, and Android launches a local `ACTION_SEND` chooser. |
| 2026-05-24 AWST | Manual review | Direct meeting summary Responses API request scaffolding and Summary/Both export | No dependency or permission added. Official OpenAI docs confirm [`gpt-5.5`](https://developers.openai.com/api/docs/models/gpt-5.5/) and `xhigh` reasoning support, and the [Responses API reference](https://platform.openai.com/docs/api-reference/responses/retrieve) supports `store: false`. Summary requests use the direct phone-to-OpenAI Responses path, credentials stay in the authorization header only, diagnostics log only model/operation/result metadata, generated summary text/metadata is stored only in encrypted local storage, and tests use local fake HTTP/placeholder credentials rather than a real OpenAI key. |

## Dependency And Supply-Chain Notes

- `android/key.properties.example` contains placeholders only.
- `android/key.properties` is ignored and must remain local/uncommitted.
- No standard OpenAI API key, client secret, token broker URL, AWS config, Google/Microsoft sign-in config, keystore, or certificate has been added.
- The Flutter scaffold includes Android and iOS platform code only; there is no app-owned network endpoint.
- Microphone permission handling uses platform code and does not add a supply-chain dependency. Real audio capture remains unimplemented and should be reviewed again when capture code or audio packages are introduced.
- Encrypted local storage uses `flutter_secure_storage` 10.3.0. Android storage is backed by Android KeyStore/Tink through the plugin; iOS storage is backed by Keychain with `first_unlock_this_device` accessibility.
- Android backup is disabled for the app manifest to avoid backup/restore copying secure-storage ciphertext outside the phone-only MVP boundary.
- `scripts/check-supply-chain.sh` is now the required local supply-chain gate. It fails on obvious OpenAI/AWS/private-key secret patterns, unexpected Android permissions, OSV query errors, or OSV vulnerabilities in pinned hosted Pub and Gradle/Maven package versions.
- CI now runs docs validation plus Flutter analysis/tests and the supply-chain gate on pull requests and pushes to `main`. Emulator smoke remains a local/manual gate through `android-pixel9-headless`.
- Language fallback routing, OpenAI credential setup, direct realtime WebSocket and resilience scaffolding, privacy-safe diagnostics, AI chat request scaffolding, direct summary request scaffolding, and transcript/summary export handoff do not introduce dependencies. Unsupported realtime targets are marked as requiring the phone-only direct OpenAI fallback credential path, with no AWS, app backend, cloud sync, or server-side transcript path.
- The current storage repository writes one encrypted local document. Large long-running transcript volume should be reassessed before production-scale retention or import/export features expand beyond the MVP test data shape.
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
2. Run `bash scripts/check-supply-chain.sh` to query OSV where ecosystem mapping exists and to enforce secret and Android-permission checks.
3. Query GitHub Advisory Database, especially for Dart/Flutter `pub` packages, when package versions change.
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
- App diagnostics use an allowlist/redaction helper and must not record transcript, audio, prompt, summary, recipient, export, credential, token, or raw request/response payloads.

## Open Security Risks To Resolve During Implementation

- User-provided OpenAI credential/session material in a mobile app is accepted for MVP only because Tom chose a phone-local no-backend path. Implementation must minimize exposure with encrypted local storage, no logging/screenshots/test output, and a clear reset/removal path.
- Direct Realtime endpoint testing must determine whether `gpt-realtime-2` or the dedicated `gpt-realtime-translate` profile is the final runtime fit.
- Native secure-storage behavior should be smoke-tested on real Android and iOS devices before production release, especially for long transcript volume and backup/restore edge cases.
- Any crash reporting or analytics SDK should be deferred unless a strong need and redaction/consent model are documented.
- Native email/share composer behavior must continue to be tested as export features expand, especially once live summary generation and iOS share handoff are validated.
- Direct summary generation still needs live OpenAI API-key smoke before #21 can close.
- Direct realtime scaffolding still needs live OpenAI API-key smoke, real microphone PCM16 capture, decoded translated-audio playback, live reconnect/expiry validation, and transcript de-duplication validation before #6/#14 can close.
