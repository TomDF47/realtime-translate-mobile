# Update existing issue #31: Prove live header pair state and block splitting on the real realtime path

Label suggestions: `mvp`, `ui`, `realtime`, `transcripts`, `android`

## Problem

The source and tests contain improvements for pause listening, startup indicator, nested language parsing, local fallback detection, and transcript block rolling. Tom's report still says Italian was not detected at the top, Italian appended into an existing `11:24` block, and translation failed. The remaining work is to prove this behavior in the active live UI path, not only in unit tests.

## Evidence

- `docs/CURRENT_REQUIREMENTS.md` lines 50-53 require Italian detection and bidirectional translation after pair lock.
- `docs/CURRENT_REQUIREMENTS.md` lines 101-110 require original+translation fields and block rolling on source item/language changes.
- `lib/main.dart` lines 174-201 derives the header pair label from stored transcript entry language codes.
- `lib/main.dart` lines 606-638 refreshes visible transcript state asynchronously after storage commits.
- `lib/src/session/realtime_transcript_committer.dart` lines 47-61 and 74-104 parse source language and upsert commits.
- `lib/src/session/realtime_transcript_committer.dart` lines 226-249 roll segments on source item or source language changes.
- `test/realtime_translation_coordinator_test.dart` lines 839-910 cover English then Italian splitting, but the Italian row is asserted before translated text exists.

## Acceptance Criteria

- The active installed live UI shows `Heard Italian. Waiting for the other language...` when Italian is the first detected language.
- The active installed live UI shows `English <-> Italian` or `Italian <-> English` after both languages are detected.
- English then Italian speech creates separate visible transcript cards/blocks in the installed UI.
- Final transcript cards have non-empty original speech and non-empty translation. Translation-first partial cards may show `Original speech pending`, but must backfill before final.
- Header pair state is not dependent on stale storage refresh timing in a way that can miss the second language.
- Tests include a full English/Italian two-turn sequence where both rows end with original and translation populated.

## Recommended Files / Areas

- `lib/main.dart`
- `lib/src/session/realtime_translation_coordinator.dart`
- `lib/src/session/realtime_transcript_committer.dart`
- `lib/src/openai/openai_realtime_translation.dart`
- `lib/src/ui/live_translate_components.dart`
- `test/widget_test.dart`
- `test/realtime_translation_coordinator_test.dart`
- `scripts/android_emulator_e2e.sh`

## Verification Expected

- `flutter analyze`
- `flutter test`
- `bash scripts/check-docs.sh`
- `git diff --check`
- Installed APK evidence for English/Italian header and block behavior, ideally folded into the #6 live-path proof.
