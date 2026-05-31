# Update existing issue #14: Validate reconnect and recovery on the real installed live stream

Label suggestions: `mvp`, `realtime`, `resilience`, `android`, `privacy`

## Problem

Realtime resilience is well scaffolded with fake gateway tests and generated-speech host smoke, but the docs still list live app-coordinator de-duplication under real streaming, credential-expiry validation, network/rate-limit validation, and audible Android speaker recovery as unresolved. This should be addressed after #6 establishes a trustworthy installed live speech path.

## Evidence

- `docs/CURRENT_REQUIREMENTS.md` lines 127-136 define realtime startup and recovery requirements.
- `docs/CURRENT_REQUIREMENTS.md` line 157 lists physical microphone translation, installed-app committed transcript validation, app-coordinator de-duplication under real live reconnect, credential-expiry/network/rate-limit validation, and audible speaker recovery as still requiring validation.
- `docs/testing-strategy.md` lines 28-30 state the current generated/debug paths do not prove those live installed recovery behaviors.
- `lib/src/session/realtime_translation_coordinator.dart` contains reconnect handling and resource teardown/restart logic, but the remaining question is live-path evidence rather than isolated control flow.

## Acceptance Criteria

- With the same installed live path used for #6, a controlled reconnect or network interruption preserves local meeting state and does not duplicate finalized transcript rows.
- Credential rejection/expiry moves to credential setup/recovery and closes capture/realtime/playback resources without leaking credential material.
- Rate-limit/transient OpenAI failures show sanitized recovery labels and bounded retry/backoff.
- Audible translated-audio recovery is validated where the target device/emulator supports audio, or the exact audio-output blocker is documented.
- Diagnostics remain payload-safe: no transcript, translated text, audio bytes, prompts, response bodies, or credentials in logs/artifacts.

## Recommended Files / Areas

- `lib/src/session/realtime_translation_coordinator.dart`
- `lib/src/session/live_session_controller.dart`
- `lib/src/openai/openai_realtime_resilience.dart`
- `lib/src/session/realtime_transcript_committer.dart`
- `lib/src/session/translated_audio_playback.dart`
- `scripts/android_emulator_e2e.sh`
- `scripts/live_openai_smoke.dart`
- `test/realtime_translation_coordinator_test.dart`
- `test/openai_realtime_resilience_test.dart`
- `docs/testing-strategy.md`
- `docs/cybersecurity-report.md`

## Verification Expected

- `flutter analyze`
- `flutter test`
- `bash scripts/check-docs.sh`
- `bash scripts/check-supply-chain.sh`
- `git diff --check`
- Installed live-path reconnect/recovery run after #6 live speech proof exists.
