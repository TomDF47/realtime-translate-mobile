# Regression Testing Checklist

Use this checklist before publishing APKs after UI, realtime, storage, export, or release-handoff changes. Keep live OpenAI and microphone use brief; prefer fake gateways, widget tests, local storage tests, and installed no-live E2E where possible.

## Non-Live Automated Gate

- Run `export PATH=/home/tom/.local/share/flutter/bin:$PATH`.
- Run `flutter pub get`.
- Run `flutter analyze`.
- Run `flutter test`.
- Run `bash scripts/check-docs.sh`.
- Run `bash scripts/check-supply-chain.sh`.
- Run `git diff --check`.
- Run `flutter build apk --debug`.
- Run `scripts/final_qa_gate.sh`.

## Main Screen And Navigation

- Start from a clean app data state.
- Verify the local setup screen shows `Start interpreter`, `Open meeting history`, `OpenAI setup`, and the on-device privacy note.
- Tap `Start interpreter` without a saved credential and verify `OpenAI setup required` appears before microphone permission.
- Save only a placeholder or current test credential through `OpenAI setup`; verify the saved value is not displayed.
- Start an interpreter session with fake or valid local credential and granted microphone permission.
- Verify the live screen starts with `Listening for languages...`, live status, elapsed timer, transcript area, `Translate Text`, and `Stop Listening`.
- Verify the active live screen does not show source picker, target picker, direction switch, read-aloud controls, speaker/headphone chips, or `Resume read-aloud meeting`.
- Feed or fake a first detected language and verify `Heard <language>. Waiting for the other language...`.
- Feed or fake a second distinct detected language and verify `<A> <-> <B>`.
- Open the menu and verify `Meeting history`, `Generate export`, and `Open generated exports` respond.
- Open AI chat from the header and close it with the close button and drag/back dismissal.

## Language Discovery

- Verify no manual language picker is available in the active interpreter flow.
- Verify first-language detection does not translate until a second distinct language is known.
- Verify the first turn can show a delayed translation or detected-language status without leaving a blank transcript card.
- Verify the second distinct language locks the pair.
- Verify later A-to-B and B-to-A fake text turns produce translated text and encrypted local transcript rows.

## Buttons And Toggles

- Tap `Translate Text` off and on; verify visual state and semantics change.
- With `Translate Text` off, verify translation transcript deltas are ignored and translated output is not stored.
- Verify read-aloud, pause/resume read-aloud, speaker/headphone state, and switch-direction controls are hidden in the active interpreter flow.
- Tap `Stop Listening`; verify capture/realtime/playback resources close and the setup screen returns.
- If `Jump to Live` is visible, tap it and verify the list returns to the latest transcript entry or shows the latest-state confirmation.
- In AI chat, tap prompt chips, send, helpful, not helpful, regenerate, and close; verify no control is inert.

## Realtime Session Smoke

- Prefer fake gateway/widget tests for repeated checks.
- For installed no-live E2E, run `scripts/android_emulator_e2e.sh --apk /tmp/<debug-apk>.apk --verify-credential-reset`.
- For invalid credential recovery, run `scripts/android_emulator_e2e.sh --apk /tmp/<debug-apk>.apk --verify-invalid-credential-recovery`.
- Before any live microphone or audible speaker claim, run `scripts/android_emulator_e2e.sh --require-device-audio --audio-preflight-only`.
- If a currently accepted OpenAI credential is available, run one brief `scripts/android_emulator_e2e.sh --require-device-audio --with-live-credential --apk /tmp/<debug-apk>.apk` smoke and clear app data afterward.
- Do not print, commit, screenshot, or log credential, transcript, prompt, audio, summary, recipient, or export payloads.

## Transcript Chunking And Timer

- Latest Tom feedback regression: start a live meeting from setup and verify the app immediately moves to the live surface with a `Connecting` or microphone-permission state instead of looking stalled on the start screen.
- Verify the elapsed timer starts at `00:00` for a new active meeting.
- Verify the timer advances only while microphone capture is open.
- Verify the timer pauses during stopped/offline/reconnecting/backgrounded states.
- Verify the timer resumes after listening resumes and resets when returning to setup or starting a new meeting.
- Feed translation transcript deltas before matching source/original deltas and verify the late source text appears in the same visible transcript card as the existing translation.
- Feed streaming transcript deltas with three or more spoken sentences.
- Verify partial live rows appear before final completion and refresh on screen without leaving the live surface.
- Verify each visible transcript card shows both an `Original` section for spoken source text and a `Translation` section for translated text; pending halves should show a pending placeholder, not a blank card.
- Verify roughly every two completed spoken sentences rolls into a separate transcript block.
- Verify partial text updates the current visible block before final completion.
- Verify transcript rows are not duplicated across fake reconnect.

## Generated Share And Export

- Open `Generate export` with no active meeting and verify it asks for a meeting first.
- With an active meeting, generate `Transcript`; verify it saves encrypted local generated export metadata and opens in the in-app browser/detail view.
- Generate `Summary` and `Both` through a fake summary gateway; verify the request uses direct OpenAI path with `store: false` in tests.
- Verify no recipient input, recipient checklist, or outbound mail backend appears in the active MVP export flow.
- Open generated exports, open a detail view, and press `Copy generated export`; verify copy is explicit and user-triggered.

## APK Release Sanity

- Build a fresh debug artifact with `scripts/build_debug_apk_artifact.sh`.
- Verify the APK installs and reaches the no-credential setup gate with `scripts/android_emulator_e2e.sh --apk /tmp/<debug-apk>.apk`.
- If publishing a debug APK to GitHub Releases, use a unique tag such as `debug-YYYYMMDD-HHMMSS-<shortsha>`.
- Upload the APK and `.sha256` sidecar.
- Verify the release asset URL opens.
- Run `git status --short --branch` and confirm only intentional committed changes remain.
