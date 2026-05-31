# New issue: Prevent hidden route-translation controls from reappearing after screenshot or overlays

Label suggestions: `mvp`, `ui`, `android`, `regression`, `accessibility`

## Problem

The current requirements report that after screenshotting, other options appear. The active interpreter must not leak old route-translation controls or secondary workflow controls after Android screenshot overlays, lifecycle pause/resume, app menus, debug overlays, or bottom sheets.

## Evidence

- `docs/CURRENT_REQUIREMENTS.md` lines 91-95 require the active live interpreter to hide source picker, target picker, direction switch, `Translate Text`, read-aloud controls, speaker/headphone chips, live-header AI chat, and live-screen export controls.
- `docs/CURRENT_REQUIREMENTS.md` lines 150-151 list the screenshot/other-options defect.
- `docs/CURRENT_REQUIREMENTS.md` lines 170-171 include acceptance criteria that hidden controls stay hidden before and after screenshot/overlay/menu interactions.
- `docs/mockup-ux-spec.md` documents the original mockup controls as visual heritage, while active issue #30 hides them for the text-first interpreter.

## Acceptance Criteria

- Reproduce or explicitly narrow the trigger: Android screenshot overlay, app lifecycle pause/resume, navigation drawer/menu, setup sheet, meeting history sheet, debug overlay, or another path.
- Active live interpreter still hides source picker, target picker, direction switch, `Translate Text`, read-aloud, speaker/headphone, live-header AI chat, and live-screen export controls after the trigger.
- A widget or installed-app regression test covers the identified trigger where practical.
- Large text and compact viewport checks still pass for the simplified active controls.

## Recommended Files / Areas

- `lib/main.dart`
- `lib/src/ui/live_translate_components.dart`
- `test/widget_test.dart`
- `test/accessibility_responsive_test.dart`
- `scripts/android_emulator_e2e.sh`
- `docs/regression-testing-checklist.md`

## Verification Expected

- `flutter analyze`
- `flutter test`
- `bash scripts/check-docs.sh`
- `git diff --check`
- Installed APK smoke evidence with screenshot/overlay/lifecycle reproduction notes.
