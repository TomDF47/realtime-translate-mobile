# Deep Review And UI/UX Backlog - 2026-06-03

Scope: repo-wide code, architecture, privacy, testing, and UI/UX pass after the manual live interpreter pair restoration.

## Review Inputs

- Canonical spec, README, architecture, workflow, security, environment, testing, decision log, and mockup UX docs.
- Shared OpenClaw skills: planning/delivery, development quality, testing/verification, documentation/handover, git/GitHub workflow, solution-architect review, and architecture standard.
- Current Flutter code under `lib/`, focused tests under `test/`, scripts, and supplied mockups in `assets/mockups/`.
- Prior phone evidence: Tom's Samsung report that language changes did not create new cards, and the requirement to keep the manual two-language pair visible.

## Fix In This Pass

| ID | Priority | Status | Finding | Remediation |
| --- | --- | --- | --- | --- |
| DR-01 | High | Planned | `docs/architecture.md` still contains stale auto-detect and "Italian is fallback-only" language that conflicts with the accepted manual pair and 13-language realtime target table. | Rewrite the stale architecture sections to match manual pair selection, the corrected realtime output list, and direct text fallback semantics. |
| DR-02 | High | Planned | Fallback-only targets such as Arabic are selectable and labeled in the sheet, but the active realtime config still tries to output that unsupported target through `/v1/realtime/translations`. | Route the primary realtime session to the realtime-capable language in the pair when the selected target is fallback-only, while keeping transcript/text fallback routing keyed to the user-selected pair. |
| DR-03 | Medium | Planned | After choosing a fallback-only target, the active live surface no longer visibly reminds the user which direction is text fallback. | Add a compact live route notice for fallback-only targets. |
| DR-04 | Medium | Planned | Supplied mockup filenames do not match the visible screens, which makes UI review easy to misread. | Rename the four JPGs to match their contents and update docs links. |

## Keep Open For Follow-Up

| ID | Priority | Status | Finding | Next Step |
| --- | --- | --- | --- | --- |
| DR-05 | High | Open | This Windows checkout still lacks `flutter`, `dart`, `adb`, and `gh`, so analyzer, Flutter tests, APK build, installed-app Android QA, PR creation, and GitHub release automation cannot be completed here. | Run the full documented gates on Tom's Fedora/Android toolchain after these commits land. |
| DR-06 | High | Open | The live realtime path still needs physical-device `LIVE_TX_EVENT` evidence or Tom-confirmed on-device pass for #6/#31 before closing realtime correctness. | Build a debug APK with `--dart-define=LIVE_TRANSLATE_DEBUG_EVENTS=true`, capture `adb logcat | grep LIVE_TX_EVENT`, and reconcile the fixture. |
| DR-07 | Medium | Open | Generated exports and AI chat are intentionally hidden from the active live loop, but still need periodic end-to-end UI review from meeting history and generated export surfaces. | Include those sheets in the next Android emulator/phone UI regression pass. |

## Architecture Review Result

- Architecture standard result: blocked for live realtime closure until physical-device/live-wire evidence exists.
- Merge readiness for this local pass: proceed with narrow fixes that do not add dependencies, permissions, backend routes, credential handling, or logging surfaces.
- Privacy/security impact: no new backend, no new mobile permission, no transcript/audio/prompt/export payload logging, and no credential material added.
