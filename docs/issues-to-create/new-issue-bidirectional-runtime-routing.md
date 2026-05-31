# New issue: Design and implement bidirectional runtime routing for the two-party interpreter

Label suggestions: `mvp`, `architecture`, `realtime`, `openai`, `privacy`

## Problem

The product requires automatic two-party bidirectional interpretation after two languages are detected. The active runtime starts one dedicated realtime translation session with one configured output language, defaulting new meetings to English. A single `/v1/realtime/translations` session configured with `audio.output.language: en` does not establish how English speech gets translated back to Italian after Italian is detected.

This is an architecture blocker, not just a parser bug.

## Evidence

- `docs/CURRENT_REQUIREMENTS.md` lines 47-53 require language discovery, pair lock, and A-to-B/B-to-A later turns without manual direction switching.
- `docs/CURRENT_REQUIREMENTS.md` line 183 leaves Italian output/fallback behavior unresolved.
- `lib/main.dart` lines 495-499 default new live meetings to target English.
- `lib/main.dart` lines 543-564 starts one realtime session using `_selectedTargetLanguage.code`.
- `lib/src/openai/openai_realtime_translation.dart` lines 176-184 sends a dedicated translation session update with a single `audio.output.language`.
- `docs/architecture.md` lines 59-68 say endpoint behavior and realtime target languages must be verified during implementation.

## Acceptance Criteria

- A short architecture note or ADR documents the chosen phone-only bidirectional runtime design.
- The design explicitly handles an English/Italian pair where Italian may be source-only for realtime output until proven otherwise.
- The design preserves direct phone-to-OpenAI only; no backend, AWS, Lambda, token broker, cloud sync, or server-side transcript handling is introduced.
- Implementation supports translating both directions after pair lock, or the active UI honestly constrains/labels the unsupported direction until the fallback is implemented.
- Tests prove that after English and Italian are detected, English turns produce Italian-visible translations and Italian turns produce English-visible translations through the selected design.
- Privacy tests or checks prove no transcript/audio/prompt/translation payload is routed to app-owned infrastructure or unsafe diagnostics.

## Recommended Files / Areas

- `docs/architecture.md`
- `docs/decision-log.md`
- `docs/live-translate-build-spec.md`
- `docs/CURRENT_REQUIREMENTS.md`
- `lib/src/openai/openai_realtime_translation.dart`
- `lib/src/session/realtime_translation_coordinator.dart`
- `lib/src/session/realtime_transcript_committer.dart`
- `lib/src/language/language_support.dart`
- `lib/main.dart`
- `test/realtime_translation_coordinator_test.dart`
- `test/language_support_test.dart`
- `scripts/live_openai_smoke.dart`

## Verification Expected

- `flutter analyze`
- `flutter test`
- `bash scripts/check-docs.sh`
- `bash scripts/check-supply-chain.sh`
- `git diff --check`
- Live or redacted smoke evidence for the selected route where feasible, without printing sensitive payloads.
