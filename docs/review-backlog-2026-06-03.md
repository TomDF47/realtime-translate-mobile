# Deep Review And UI/UX Backlog - 2026-06-03

Scope: repo-wide code, architecture, privacy, testing, and UI/UX pass after the manual live interpreter pair restoration.

Updated 2026-06-04 after Samsung spoken-output testing.

## Review Inputs

- Canonical spec, README, architecture, workflow, security, environment, testing, decision log, and mockup UX docs.
- Shared OpenClaw skills: planning/delivery, development quality, testing/verification, documentation/handover, git/GitHub workflow, solution-architect review, and architecture standard.
- Current Flutter code under `lib/`, focused tests under `test/`, scripts, and supplied mockups in `assets/mockups/`.
- Prior phone evidence: Tom's Samsung report that language changes did not create new cards, and the requirement to keep the manual two-language pair visible.

## Fix In This Pass

| ID | Priority | Status | Finding | Remediation |
| --- | --- | --- | --- | --- |
| DR-01 | High | Fixed | `docs/architecture.md` still contains stale auto-detect and "Italian is fallback-only" language that conflicts with the accepted manual pair and 13-language realtime target table. | Rewrote the stale architecture sections to match manual pair selection, the corrected realtime output list, and direct text fallback semantics. |
| DR-02 | High | Fixed | Fallback-only targets such as Arabic are selectable and labeled in the sheet, but the active realtime config still tries to output that unsupported target through `/v1/realtime/translations`. | Routed the primary realtime session to the realtime-capable language in the pair when the selected target is fallback-only, while keeping transcript/text fallback routing keyed to the user-selected pair. |
| DR-03 | Medium | Fixed | After choosing a fallback-only target, the active live surface no longer visibly reminds the user which direction is text fallback. | Added a compact live route notice for fallback-only targets. |
| DR-04 | Medium | Fixed | Supplied mockup filenames do not match the visible screens, which makes UI review easy to misread. | Renamed the JPGs to match their contents and updated docs links. |
| DR-08 | High | Fixed | With both `Output voice` checkboxes checked, the app could produce two voices because spoken output was tied to primary/reverse realtime audio producers instead of one serialized turn output. | Routed active spoken output through one phone-local Android TextToSpeech gateway fed by finalized translated card text; normal active UI runtime options keep primary/reverse realtime audio playback closed. |
| DR-09 | High | Fixed | App speaker output could be captured by the microphone and re-translated, creating duplicate/contaminated transcript cards. | Suppress outgoing mic chunks while local TTS is speaking, stop TTS on loud PCM16 speech interrupt, and enable Android acoustic echo cancellation/noise suppression when available. |
| DR-10 | High | Fixed | Persisted spoken-output checkbox state restored visually but did not reliably activate audio until the boxes were cycled. | Apply restored per-side spoken-output state directly to the coordinator before the first turn and add a widget regression for first-translation speech after route restore. |
| DR-11 | High | Fixed | Italian-to-English turns could show correct original text but incomplete/bad translated output when reverse audio competed with text routing. | Keep transcript cards text-first, speak only finalized card translations, and leave reverse-direction text on the direct OpenAI fallback path when needed. |

## Keep Open For Follow-Up

| ID | Priority | Status | Finding | Next Step |
| --- | --- | --- | --- | --- |
| DR-05 | High | Open | This Windows checkout still lacks `flutter`, `dart`, and `adb`, so analyzer, Flutter tests, APK build, and installed-app Android QA cannot be completed locally. `gh` is now available through Scoop for GitHub operations. | Run the full documented Flutter/Android gates through GitHub Actions, Fedora, or another machine with the Flutter/Android toolchain after these commits land. |
| DR-06 | High | Open | The live realtime path still needs physical-device `LIVE_TX_EVENT` evidence or Tom-confirmed on-device pass for #6/#31 before closing realtime correctness. | Build a debug APK with `--dart-define=LIVE_TRANSLATE_DEBUG_EVENTS=true`, capture `adb logcat | grep LIVE_TX_EVENT`, and reconcile the fixture. |
| DR-07 | Medium | Open | Generated exports and AI chat are intentionally hidden from the active live loop, but still need periodic end-to-end UI review from meeting history and generated export surfaces. | Include those sheets in the next Android emulator/phone UI regression pass. |
| DR-12 | Medium | Open | Physical Samsung validation is still needed for audible TTS quality, echo handling in a real room, and two-turn EN/IT behavior with a real OpenAI credential. | Use a debug APK/release artifact after CI validation, test English then Italian with both checkbox combinations, and capture `LIVE_TX_EVENT` if transcript routing still misbehaves. |

## Architecture Review Result

- Architecture standard result: blocked for live realtime closure until physical-device/live-wire evidence exists.
- Merge readiness for this local pass: proceed with narrow fixes that do not add dependencies, permissions, backend routes, credential handling, or logging surfaces.
- Privacy/security impact: no new backend, no new mobile permission, no transcript/audio/prompt/export payload logging, and no credential material added.
