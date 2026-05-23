# Cybersecurity Report

Report date/time: 2026-05-24 07:40:46 AWST (Australia/Perth, UTC+08:00)

Scope: pre-implementation baseline for the phone-only MVP. The repo currently contains planning docs, issue templates, mockup assets, and docs validation only.

## Executive Summary

No Flutter scaffold, app package manifest, lockfile, backend code, or runtime dependency versions exist yet. This report is therefore a pre-dependency cybersecurity baseline, not a package-specific vulnerability attestation.

Current result: no package/version vulnerabilities can be mapped because there are no package versions to check. The next security review must run as soon as a `pubspec.yaml`, `pubspec.lock`, Android Gradle files, iOS dependency files, JavaScript package manifests, or any other dependency manifest/lockfile is introduced.

## MVP Security Posture

- Phone-only MVP aside from direct OpenAI API calls.
- No AWS, Lambda, token broker, app backend, cloud sync, server mailer, or server-side transcript handling.
- Local encrypted storage is required for meetings, transcripts, summaries, recipient preferences, sensitive preferences, and credential/session material once implementation exists.
- Direct OpenAI API calls are the only routine product network path.
- Email export is user initiated and should use device-native mail/share composer semantics where practical.
- Logs, analytics, crash reports, screenshots, diagnostics, and tests must exclude transcript, audio, prompt, summary, recipient, export, and OpenAI credential/session payloads.

## Repository Dependency State

Command basis:

```bash
find . -maxdepth 2 -name '*lock*' -o -name 'pubspec.yaml' -o -name 'package.json' -o -name 'package-lock.json' -o -name 'yarn.lock' -o -name 'pnpm-lock.yaml' -o -name 'build.gradle' -o -name 'settings.gradle' -o -name 'Podfile.lock' -o -name 'requirements*.txt' | sort
```

Result: no dependency manifests or lockfiles were present at the time of this report.

Implication: there are no Flutter/Dart, Gradle, CocoaPods, npm, Python, or backend package versions to query against vulnerability databases yet.

## Vulnerability Check Log

| Date conducted | Source | Target | Result |
| --- | --- | --- | --- |
| 2026-05-24 AWST | Local repo dependency manifest scan | Repo state | No app runtime package manifests or lockfiles found. No package versions exist yet. |
| 2026-05-24 AWST | OSV API documentation: <https://google.github.io/osv.dev/post-v1-query/> | Repo state | Package/version query methodology recorded. Package-specific query not applicable until versions exist. |
| 2026-05-24 AWST | GitHub Advisory Database REST docs: <https://docs.github.com/en/rest/security-advisories/global-advisories> | Repo state | Advisory source recorded, including `pub` ecosystem support. Package-specific query not applicable until versions exist. |
| 2026-05-24 AWST | NVD CVE API docs: <https://nvd.nist.gov/developers/vulnerabilities> | Repo state | CVE/CPE source recorded. No native/platform package versions or CPEs exist yet. |
| 2026-05-24 AWST | Dart pub security advisories: <https://dart.dev/tools/pub/security-advisories> | Repo state | Dart/Flutter advisory handling recorded. No `pubspec.yaml` or `pubspec.lock` exists yet. |
| 2026-05-24 AWST | pub.dev security page: <https://pub.dev/security> | Repo state | Pub package advisory/reporting source recorded. No Pub packages exist yet. |

## Required Rerun Trigger

Rerun this report and record package-specific results when any of these appear:

- `pubspec.yaml`
- `pubspec.lock`
- Android Gradle files or version catalogs
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
4. Check Dart/pub advisory output from dependency resolution when Flutter exists.
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
