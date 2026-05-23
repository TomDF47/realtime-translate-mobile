# Testing Strategy

This is the MVP verification plan. Keep commands concrete as implementation lands.

## Current Docs-Only Gate

```bash
bash scripts/check-docs.sh
```

This checks local Markdown links and scans for likely committed OpenAI secret patterns.

## Flutter App Gates

Once the Flutter scaffold exists, app changes should run:

```bash
flutter analyze
flutter test
```

Expected coverage areas:

- Session state model transitions: signed out, requesting client secret, connecting, listening, speaking, read-aloud paused, reconnecting, expired, and error.
- Microphone permission states: granted, denied, permanently denied, and revoked.
- Language support table and unsupported-target fallback behavior.
- Local encrypted storage read/write/delete behavior.
- Transcript Q&A empty, offline, expired-secret, and model-error states.
- Widget tests for the four supplied mockup surfaces.
- Accessibility checks for icon-only controls, auth buttons, language selectors, playback controls, assistant controls, and transcript actions.

## Backend Token Broker Gates

Once backend code exists, broker tests should cover:

- Identity/session validation before issuing client secrets.
- Short-lived OpenAI client-secret request and response metadata.
- Expiry and refresh metadata.
- Error responses for unauthenticated, unauthorized, upstream failure, and malformed request cases.
- Logging redaction for bearer tokens, identity tokens, OpenAI client secrets, standard API keys, and request bodies.
- Negative assertion that transcript or audio fields are rejected or never accepted by broker endpoints.

## Privacy And Secret Gates

Every implementation change touching auth, OpenAI, logging, storage, or transcript handling should include negative tests for:

- No standard OpenAI API key in mobile code/config/assets/tests/build outputs.
- No transcript/audio/prompt payload routed through AWS.
- No transcript/audio/prompt payload in logs, analytics, diagnostics, or crash reports.
- Transcript Q&A uses direct OpenAI or another privacy-preserving path where AWS cannot see transcript content.

## Android Emulator Smoke

Use Tom's boot-tested emulator command:

```bash
android-pixel9-headless
```

Do not use `emulator -no-window`.

Once Flutter exists, smoke checks should cover:

- Welcome/sign-in surface.
- Teal live listening surface.
- Transcript assistant bottom sheet over dimmed live screen.
- Amber speaking/read-aloud-paused surface.
- Large text and small device handling without clipped labels or overlapping bottom controls.
- Safe-area behavior around Android status and navigation bars.

Record emulator command output, screenshot notes, or exact blockers in the issue before closing UI or Android verification work.

## CI Direction

The first committed CI gate should run docs validation without requiring Flutter. After implementation lands, expand CI to include Flutter analysis/tests, backend tests, and secret-safety checks.
