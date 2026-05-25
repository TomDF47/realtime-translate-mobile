# Supplied Mockup UX Spec

This document is the visual and interaction source of truth for the first Android Flutter implementation. The supplied mockups define four required visual surfaces: welcome/local setup, live translation in teal listening mode, scoped AI chat bottom sheet, and live translation in amber speaking or paused read-aloud mode.

The product architecture changed after mockup intake. The MVP is phone-only aside from direct OpenAI API calls, so Microsoft/Google sign-in behavior shown in the welcome mockup is V2/future. Preserve the visual quality and hierarchy, but adapt sign-in affordances into phone-local setup, start-meeting, and meeting-history actions for the MVP.

## UX Direction

- Use a premium, executive-grade dark navy Android UI.
- Keep the first usable screen focused on live translation, not technical setup.
- Treat audio status, transcript confidence, and privacy as first-class signals.
- Prefer dense, calm controls with clear hierarchy over decorative marketing layouts.
- Preserve iOS-compatible Flutter structure, but optimize visual sizing and spacing for Android first.

## Visual System

### Color

- Base background: dark navy, near-black blue.
- Primary listening accent: teal for live capture, Spanish/source language borders, active toggles, and audio-wave branding.
- Secondary translation accent: blue for English/target-language transcript cards and read-aloud actions.
- Speaking/paused accent: amber or orange for English to Japanese speaking state, queue banner, and resume read-aloud action.
- Destructive action: red for Stop Listening.
- Surfaces: slightly lifted navy cards and bottom sheets with subtle borders.
- Text: high-contrast white for primary labels, muted blue-gray for supporting copy, and accent-tinted badges for language/status markers.

### Typography

- Use clean sans-serif system typography.
- Main screen title is centered and medium weight.
- Transcript original text is smaller and quieter.
- Translated text is larger and bolder.
- Timers, badges, and queue metadata should use compact, readable numerals.

### Shape And Elevation

- Cards use restrained radius, around 8 to 12 px equivalent in Flutter.
- Bottom sheet has larger top corner radius and a visible drag handle.
- Primary controls use circular icon buttons where the mockups show round controls.
- Chips and pills are rounded but compact.
- Avoid nested decorative cards; card surfaces should represent actual functional groups.

### Iconography

- Header: hamburger menu left, centered `Live Translate`, transcript/chat assistant icon right.
- Session status: waveform icon.
- Language cards: waveform icon for detected/source speech, speaker icon for target audio.
- Transcript rows: per-line speaker, play, or waveform icon depending on state.
- Assistant: sparkle icon, close X, thumbs up/down, refresh/regenerate, send up-arrow, lock privacy icon.
- Local setup: primary start-meeting action, meeting-history action, OpenAI setup/status affordance if implementation requires it, plus right chevrons where the mockup uses row buttons.

## Screen C: Welcome / Local Setup

### Layout

- Full-screen dark navy onboarding screen.
- Android status bar should feel native and unobtrusive.
- Centered teal waveform logo near the upper-middle.
- H1: `Live Translate`.
- Subtitle: `Live conversation translation for meetings and face-to-face moments`.
- Teal audio wave graphic spans the middle of the screen.
- MVP actions are stacked full-width buttons adapted from the mockup:
  - `Start new meeting`
  - `Open meeting history`
- If implementation requires a visible OpenAI setup/status action, keep it phone-local and avoid exposing raw credential text.
- V2 sign-in actions may reuse the same row-button visual treatment later.
- Privacy reassurance block uses lock icon and text: `Transcripts are stored on device only. Your conversations stay private.`
- Footer badges:
  - `Secure & Private`
  - `Android MVP`

### Interaction Notes

- Primary setup buttons should have pressed and disabled states.
- The screen should not mention backend internals or API keys.
- Preserve enough bottom padding for Android gesture navigation.

## Screen A: Main Live Translation, Teal Listening Mode

### Layout

- Dark navy main app shell with Android status bar showing `10:42` and `82%` in the mockup.
- Header:
  - Hamburger menu on the left.
  - Centered title: `Live Translate`.
  - Transcript/chat assistant icon on the right.
- Session status card:
  - Waveform icon.
  - Text: `Auto-detect Spanish -> English`.
  - Status pill: `Listening`.
  - Elapsed timer: `00:05:23`.
- Language controls:
  - From card: `Auto-detect` / `Spanish`, waveform icon, dropdown affordance.
  - Center switch button for direction swap.
  - To card: `English (US)`, speaker icon, dropdown affordance.
- Feature toggles row:
  - `Translate Text` on.
  - `Read Aloud` on.
  - `Headphones Active` chip.
- Transcript list:
  - Card per utterance or translation pair.
  - Language badge: `ES` or `EN`.
  - Original text smaller.
  - Translated text larger and bolder.
  - Timestamp.
  - Per-line speaker or play icon.
  - Spanish/source cards use teal accent border.
  - English/target cards use blue accent border.
  - Include sample meeting content around Tuesday at 10 AM, deliverables, and project timeline.
- Bottom live affordance:
  - Dotted divider.
  - `Jump to Live` chip.
- Fixed bottom control bar:
  - Large circular `Stop Listening` red button.
  - `Pause Read Aloud` blue button.
  - `Switch Direction` dark button.

### Required States

- Listening status is visually active and calm, not alarming.
- Toggle states must be clear without requiring explanatory text.
- Transcript list should support scrolling behind the fixed bottom control bar with safe bottom padding.
- `Jump to Live` appears when the list is not pinned to the latest transcript entry.

## Screen B: Scoped AI Chat Bottom Sheet

### Entry

- Open from the header AI chat icon on the main live translation screen or from meeting history.
- Main screen remains visible but dimmed behind the modal.

### Bottom Sheet Layout

- Rounded bottom sheet begins around the lower half of the screen.
- Dark navy sheet surface with subtle top border and drag handle.
- Header:
  - Sparkle icon.
  - Title: `AI Chat`.
  - Close X.
- Scope selector or visible scope label:
  - `This meeting` when opened from a meeting.
  - `All meetings` when opened from a global/history surface.
- Subtitle should reinforce the selected scope without using backend terminology.

### Chat Content

- User prompt: `What did they agree about the timeline?`
- Assistant answer uses only the selected local meeting scope and cites inline timestamps, including `10:37 AM` and `10:38 AM`.
- Include thumbs up/down feedback controls under the assistant answer.
- Suggested prompt chips:
  - `Summarise action items`
  - `What do they need from me?`
  - Refresh/regenerate icon chip.
- Input field placeholder:
  - `Ask about this meeting...` for `This meeting`.
  - `Ask across meetings...` for `All meetings`.
- Send button uses an up-arrow icon.
- Privacy note with lock icon should state that responses are based on the selected local meeting scope.

### Interaction Notes

- Sheet should support drag-dismiss and close-button dismiss.
- AI chat must be visually scoped to `This meeting` or `All meetings`.
- The input should remain reachable above the Android keyboard.
- Suggested chips populate the input or send immediately, depending on implementation scope; pick one behavior and keep it consistent.

## Screen D: Main Live Translation, Amber Speaking / Paused Read-Aloud Mode

### Differences From Screen A

- Uses the same main layout and component structure.
- Accent shifts to amber/orange for English to Japanese speaking and paused read-aloud state.
- Session status card:
  - Text: `English -> Japanese`.
  - Status pill: `Speaking`.
  - Elapsed timer: `00:06:12`.
- Language controls:
  - From: `English (US)`.
  - To: `Japanese (JP)`.
- Feature chip:
  - `Speaker Active`.
- Queue banner:
  - Primary text: `Read aloud is paused`.
  - Detail: `Queued: 4 lines (00:12 behind)`.
  - Actions: `Resume` and `Skip to Live`.
- Transcript list:
  - Alternating `EN` and `JA` cards.
  - Japanese output text for translated lines.
  - User-originated English lines are marked `You`.
  - Per-line waveform or speaker icons.
- Fixed bottom control bar:
  - `Stop Listening` red.
  - `Resume Read Aloud` amber play button.
  - `Switch Direction` dark.

### Interaction Notes

- The paused read-aloud queue banner must be prominent but not destructive.
- `Resume` continues queued audio from the current queue point.
- `Skip to Live` drops queued audio and resumes at the latest translated line.
- The bottom control label and icon must change from pause to resume when read-aloud is paused.

## Component Inventory

- App shell with Android safe areas and dark navy background.
- Header bar with menu, title, and assistant launcher.
- Session status card with mode icon, route label, state pill, and timer.
- Language selector cards with dropdown state.
- Direction switch button.
- Feature toggle row with binary toggles and passive device/output chips.
- Transcript card with language badge, optional speaker marker, source text, translated text, timestamp, and playback control.
- Queue/warning banner with two actions.
- Jump-to-live chip and dotted divider.
- Fixed bottom control bar with three primary actions.
- Local setup action button.
- Meeting history row or selector.
- Generated export controls with Transcript/Summary/Both selector, generated export browser, in-app detail view, and explicit Copy action. Active MVP UI does not show the deferred email recipient checklist.
- Footer privacy/badge row.
- Scoped AI chat bottom sheet.
- AI chat message bubbles, citations, feedback controls, prompt chips, input, send button, scope label/control, and privacy note.

## Flutter Implementation Notes

- Do not implement Flutter until the planning issue is complete and implementation issue is unblocked.
- Build the first Flutter pass against this document as the visual source of truth.
- Start with a small design token layer for colors, spacing, radii, and text styles.
- Keep mock data local for the first UI pass; do not block visual implementation on realtime integration.
- Model the live screen state explicitly:
  - `listening`
  - `speaking`
  - `readAloudPaused`
  - `aiChatOpen`
  - `aiChatScope`
  - `hasQueuedAudio`
  - `isAtLiveEdge`
- Keep transcript row data structured with meeting ID, source language, target language, original text, translated text, timestamp, speaker ownership, accent, and playback state.
- Ensure the transcript list has bottom inset equal to the fixed control bar height plus safe-area padding.
- Use semantic labels for icon-only controls.
- Keep privacy language consistent with local-only encrypted meeting storage and direct OpenAI AI chat direction from the product spec.

## Acceptance Criteria For First UI Implementation

- Welcome/local setup screen matches Screen C visual direction and dark teal audio branding while reflecting phone-only MVP behavior.
- Main screen can render teal listening mode matching Screen A.
- AI chat launcher opens a dimmed main screen plus scoped bottom sheet matching Screen B.
- Main screen can render amber speaking/paused read-aloud mode matching Screen D.
- Bottom controls, queue banner, toggles, language cards, and transcript rows have the correct labels and state-dependent colors.
- No source transcript content is routed through app-owned backend infrastructure in implementation architecture.
- Android emulator smoke check shows all four surfaces without overlapping text or clipped bottom controls.
