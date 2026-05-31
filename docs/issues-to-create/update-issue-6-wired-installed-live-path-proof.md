# Update existing issue #6: Prove the wired installed live translation path

Label suggestions: `mvp`, `realtime`, `android`, `verification`, `privacy`

## Problem

Tom reports the installed translate app is still not working, and the previous Cursor gap analysis concluded that the tested `LiveTextInterpreter` path may not be the real live UI path. The real user path appears to depend on `LiveRealtimeTranslationCoordinator`, Android microphone capture, `/v1/realtime/translations`, source/original transcript events, translation events, and encrypted meeting storage.

This issue should become the top-priority release blocker for #6: prove the installed app live path end to end before more isolated fixes are treated as product fixes.

## Evidence

- `docs/CURRENT_REQUIREMENTS.md` lines 148-157 record Tom's active defects and remaining live validation gaps.
- `docs/testing-strategy.md` lines 28-30 state current generated-speech/debug E2E proof does not prove Android physical microphone capture, installed-app live speech persistence, credential-expiry recovery with real credential material, or audible speaker output.
- `lib/main.dart` lines 543-564 show active live start uses `LiveRealtimeTranslationCoordinator`, not `LiveTextInterpreter`.
- `lib/src/session/live_text_interpreter.dart` lines 5-38 are an isolated text path and must not be used as live installed-app evidence.

## Acceptance Criteria

- A repeatable installed APK validation path proves the active app can start with a real local OpenAI credential, connect to `gpt-realtime-translate` on `/v1/realtime/translations`, and process live or controlled microphone speech through the same coordinator used by the UI.
- The proof covers at least two spoken turns across English and Italian.
- The live UI shows original speech and translation as separate visible fields for final blocks.
- The header shows first-language waiting state, then a bidirectional pair label after two languages are detected.
- Italian speech creates a new transcript block instead of appending to the previous English block.
- The validation artifact does not print credentials, audio bytes, transcript payloads, translated payloads, request bodies, or response bodies.
- App data is cleared after any run that stores a live credential in the emulator/device.

## Recommended Files / Areas

- `scripts/android_emulator_e2e.sh`
- `scripts/android_pixel9_host_audio.sh`
- `scripts/live_openai_smoke.dart`
- `lib/main.dart`
- `lib/src/session/realtime_translation_coordinator.dart`
- `lib/src/session/realtime_transcript_committer.dart`
- `lib/src/openai/openai_realtime_translation.dart`
- `test/realtime_translation_coordinator_test.dart`
- `docs/testing-strategy.md`

## Verification Expected

- `flutter analyze`
- `flutter test`
- `bash scripts/check-docs.sh`
- `bash scripts/check-supply-chain.sh`
- `git diff --check`
- Installed APK run with `scripts/android_emulator_e2e.sh --require-device-audio --with-live-credential` or an equivalent physical-device command.
- If a live credential or physical microphone path is unavailable, the issue must remain open with the exact blocker documented.
