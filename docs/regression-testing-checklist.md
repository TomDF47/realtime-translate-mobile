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
- Tap `Start interpreter` without a saved live credential and verify `Gemini setup required` appears before microphone permission.
- Save only a placeholder or current test credential through `OpenAI setup`; verify the saved value is not displayed.
- Start an interpreter session with fake or valid local credential and granted microphone permission.
- Verify the live screen starts with the selected manual pair such as `Italian <-> English`, source/target language selectors, live status, elapsed timer, transcript area, `Stop Listening`, and `Pause Listening`.
- Verify the active live screen does not show direction switch, `Translate Text`, read-aloud controls, speaker/headphone chips, live-header AI chat, live-screen export controls, or `Resume read-aloud meeting`.
- Open both language selectors, verify `Auto-detect` is not offered as a source choice, choose a different supported source/target, and verify the status card and stored meeting route update to the new pair.
- Feed or fake source turns in both selected languages and verify transcript rows keep original and translated text in separate fields.
- Open the live menu and verify `Meeting history` responds while `Generate export` and `Open generated exports` remain absent from the active live menu.
- Open AI chat from meeting history or another non-live-header entry point and close it with the close button and drag/back dismissal.

## Language Discovery

- Verify the manual language pair is available in the active interpreter flow.
- Verify the selected pair is treated as locked before any source transcript event arrives.
- Verify the first turn can show a pending translation or source-language status without leaving a blank transcript card.
- Verify source-row labels still resolve from OpenAI metadata or deterministic local detection when available.
- Verify later A-to-B and B-to-A fake text turns produce translated text and encrypted local transcript rows.

## Buttons And Toggles

- Verify `Translate Text` is absent from the active interpreter flow before and after menu, sheet, screenshot, and lifecycle pause/resume interactions.
- Verify read-aloud, pause/resume read-aloud, speaker/headphone state, and switch-direction controls are hidden in the active interpreter flow before and after menu, sheet, screenshot, and lifecycle pause/resume interactions.
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

- Open generated export controls from meeting history or another non-live-screen entry point; do not expect generated export controls on the active interpreter surface.
- With an active meeting, generate `Transcript`; verify it saves encrypted local generated export metadata and opens in the in-app browser/detail view.
- Generate `Summary` and `Both` through a fake summary gateway; verify the request uses direct OpenAI path with `store: false` in tests.
- Verify no recipient input, recipient checklist, or outbound mail backend appears in the active MVP export flow.
- Open generated exports, open a detail view, and press `Copy generated export`; verify copy is explicit and user-triggered.

## APK Release Sanity

- Run the repeatable, offline-by-default release smoke with `scripts/android_release_smoke.sh` (or `scripts/android_release_smoke.sh --apk /tmp/<apk>.apk` for an already-built artifact, or `--release` for a release-mode build). This verifies APK metadata and signing before install, cold-boots the emulator resiliently, installs the APK, clears app state, launches it, and asserts startup reaches the offline `Gemini setup required` bounded state and never remains on `Preparing live session`. The default path reads no Gemini/OpenAI credential and makes no Gemini/OpenAI network request; `--verify-invalid-credential-recovery` (live auth-rejection request with a non-secret placeholder) and `--with-live-credential` (real secret) are explicit opt-ins.
- Confirm the printed result block under `/tmp/realtime-translate-mobile-release-smoke/release-smoke-result.md` shows each check as `pass`.
- If the emulator cannot cold-boot on this host, confirm the smoke fails fast with a captured log tail under the artifact directory rather than hanging, then retry or attach a physical device.
- For a metadata/signing-only check without an emulator, run `scripts/check_apk_metadata.sh --apk /tmp/<apk>.apk`.
- Confirm the metadata preflight lists both `android.permission.RECORD_AUDIO` and `android.permission.INTERNET`; the gate fails if either product-critical permission is missing, so a release build cannot ship without the direct phone-to-OpenAI network path (#41).
- If publishing a debug APK to GitHub Releases, use a unique tag such as `debug-YYYYMMDD-HHMMSS-<shortsha>`.
- Upload the APK and `.sha256` sidecar.
- Verify the release asset URL opens.
- Record the validation result in the release notes or an issue comment. The smoke can do this with `--record-to-release <tag>` or `--record-to-issue <number>` (sanitized block, secret-pattern guarded), or paste the printed block manually.
- Run `git status --short --branch` and confirm only intentional committed changes remain.
