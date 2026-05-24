# Live Translate Build Spec

This is the canonical build spec for the Realtime Translate Mobile repo. Future implementation, issue triage, README updates, and UI work should use this document as the first source of truth.

## Product Goal

Build an Android-first, iOS-compatible Flutter app for continuous live speech translation using OpenAI Realtime Translation. The MVP is phone-only except for direct OpenAI API calls. It should feel premium, clean, and executive-grade, with live translation and meeting history as usable product surfaces rather than a technical dashboard.

## Fixed MVP Decisions

| Area | Decision |
| --- | --- |
| Mobile framework | Flutter |
| Platform order | Android first, iOS-compatible later |
| MVP backend | None |
| Routine network path | Phone app connects directly to the OpenAI API only |
| Live model | `gpt-realtime-translate` |
| AI chat | Direct OpenAI path scoped explicitly to `This meeting` or `All meetings` |
| Storage | Encrypted local device storage only |
| Meetings | Local meeting history, transcript/history, and summary metadata stored on phone |
| Email export | User-initiated device-native mail/share composer where practical; no outbound mail backend |
| Cloud/backend/auth scope | Deferred to [docs/v2-future-scope.md](v2-future-scope.md) |
| Mockups | Supplied Android mockups in `assets/mockups/`, interpreted through [docs/mockup-ux-spec.md](mockup-ux-spec.md) |

## Source Documents And Assets

- README and repo status: [README.md](../README.md)
- Agent operating instructions: [AGENTS.md](../AGENTS.md)
- UX interpretation: [docs/mockup-ux-spec.md](mockup-ux-spec.md)
- High-level product spec: [docs/product-spec.md](product-spec.md)
- Architecture handoff: [docs/architecture.md](architecture.md)
- V2/future scope: [docs/v2-future-scope.md](v2-future-scope.md)
- Cybersecurity report: [docs/cybersecurity-report.md](cybersecurity-report.md)
- Development workflow: [docs/development-workflow.md](development-workflow.md)
- Environment setup: [docs/environment.md](environment.md)
- Testing strategy: [docs/testing-strategy.md](testing-strategy.md)
- Decision log: [docs/decision-log.md](decision-log.md)
- Starter prompt for first implementation: [docs/codex-starter-prompt.md](codex-starter-prompt.md)

Supplied mockups:

- [assets/mockups/01-welcome-sign-in.jpg](../assets/mockups/01-welcome-sign-in.jpg)
- [assets/mockups/02-live-listening-teal.jpg](../assets/mockups/02-live-listening-teal.jpg)
- [assets/mockups/03-transcript-assistant.jpg](../assets/mockups/03-transcript-assistant.jpg)
- [assets/mockups/04-speaking-paused-amber.jpg](../assets/mockups/04-speaking-paused-amber.jpg)

## MVP User Flow

1. User opens the app and sees a premium phone-local welcome/start surface.
2. User starts a new meeting or selects an old meeting and continues from it.
3. User chooses source auto-detect or a known input language.
4. User chooses a supported output language.
5. App starts a direct OpenAI Realtime Translation session from the phone.
6. App streams microphone audio directly to OpenAI and receives translated audio plus transcript deltas while the speaker is still talking.
7. User can pause/resume read-aloud, skip queued audio to live, switch direction, and jump to the latest transcript.
8. App stores meeting transcript/history/summary metadata in encrypted local device storage.
9. User can open AI chat from a meeting with `This meeting` scope or from a global/history surface with `All meetings` scope.
10. User can export Transcript, Summary, or Both through a user-initiated mail/share flow with locally remembered recipients.

## Mobile App Requirements

- Scaffold a Flutter project that builds for Android now and does not block iOS later.
- Keep platform-specific code isolated behind clear interfaces.
- Use Android runtime microphone permission flows before recording.
- Never start recording before explicit permission is granted.
- Handle permission denied, permanently denied, and permission revoked states.
- Model live session state explicitly, including at least:
  - `localSetup`
  - `meetingSelection`
  - `connecting`
  - `listening`
  - `speaking`
  - `readAloudPaused`
  - `reconnecting`
  - `offline`
  - `credentialInvalid`
  - `error`
- Handle app lifecycle transitions such as backgrounding, foregrounding, audio focus changes, headset/speaker route changes, network loss, and session teardown.
- Keep transcript rows structured by meeting ID, language, original text, translated text, timestamp, speaker ownership, confidence/status, accent, and playback state.
- Store preferences, recent languages, meetings, transcript history, summary metadata, remembered export recipients, and last selected recipients locally with encryption.
- Provide retention and delete controls for meeting and transcript history.
- Do not add app backend, AWS, server-side transcript handling, or cloud transcript sync in the MVP.

## UI Requirements

Use [docs/mockup-ux-spec.md](mockup-ux-spec.md) and the four image files as the visual source of truth. The revised MVP should adapt any cloud sign-in affordances into phone-local setup/start-meeting controls unless a future decision restores cloud identity to MVP scope.

Required first-pass surfaces:

- Welcome/local setup screen.
- Meeting history or meeting selector entry point.
- Main live translation screen in teal listening mode.
- Scoped AI chat bottom sheet over a dimmed live screen.
- Main live translation screen in amber speaking/read-aloud-paused mode.
- Email export sheet/dialog with export type selector and recipient checklist.

Required UI foundations:

- Small design token layer for colors, spacing, radii, typography, shadows/elevation, and state colors.
- Reusable components for app shell, header, status card, language selectors, direction switch, feature toggles, transcript cards, queue banner, jump-to-live chip, bottom controls, local setup actions, meeting selector/history rows, AI chat sheet, prompt chips, input, email export controls, recipient checklist, and privacy notes.
- Safe-area handling for Android status/navigation bars.
- Bottom transcript padding equal to fixed controls plus safe-area inset.
- Large-text and small-device handling so labels, buttons, transcript rows, export controls, and bottom controls do not overlap or clip.
- Semantic labels for icon-only controls and accessibility coverage for local setup, meeting management, live controls, language selection, playback, AI chat, export, and transcript actions.

## No MVP Backend

The MVP must not include an app backend.

- Do not add AWS API Gateway, Lambda, token broker endpoints, backend auth validation, backend-held OpenAI keys, server mailers, cloud transcript storage, or cloud sync.
- Do not send transcript text, translated text, prompts, microphone audio, audio chunks, audio-derived payloads, summaries, recipient lists, or meeting metadata to an app-owned backend.
- If a future backend is introduced, it must be treated as V2/future scope and reconciled through [docs/v2-future-scope.md](v2-future-scope.md), [docs/decision-log.md](decision-log.md), and the GitHub issue map before implementation.

## OpenAI Requirements

- Use `gpt-realtime-translate` as the primary live translation model.
- Connect from the phone app directly to OpenAI.
- Stream microphone audio directly to OpenAI.
- Receive translated audio and transcript deltas while the speaker is still talking.
- Recover from direct credential/session expiry, network drops, transient OpenAI errors, and app lifecycle interruption with bounded reconnect/backoff behavior.
- Keep user-facing state clear during connecting, reconnecting, credential-invalid, unsupported-language, offline, permission-denied, and model/API error states.
- Verify current OpenAI Realtime Translation language support during implementation rather than hard-coding stale external assumptions.
- Verify the current OpenAI API authentication/session approach for direct mobile use before coding. Never bundle, hard-code, or commit a standard OpenAI API key in mobile source, config, assets, tests, screenshots, or build outputs.
- If implementation uses user-provided OpenAI credential material, store it only in encrypted local storage, redact it from logs/screenshots/test output, and provide a clear removal/reset path.

## Language Support And Fallback

OpenAI Realtime Translation is expected to have broad input language coverage and narrower target output language coverage. The app must plan for unsupported target output languages.

Implementation requirements:

- Keep a centralized, easy-to-update language support table.
- Show only valid realtime target languages by default.
- Detect when a requested target language is unsupported by realtime output.
- Provide a clear direct-OpenAI fallback path for broader target language support when product-approved.
- Make fallback behavior explicit in the UI rather than failing silently.
- Keep fallback AI chat and translation routes phone-only except for direct OpenAI calls.

## Meeting Management Requirements

- User can start a new meeting.
- User can select an old meeting and continue from it.
- Meetings have local transcript/history/summary metadata stored on the phone.
- Meeting metadata should include at least meeting ID, title or generated label, created/updated timestamps, language route, transcript count, summary availability, and last activity.
- Continuing a meeting appends new transcript/history entries without losing prior local history.
- Deleting a meeting removes its local transcript/history/summary metadata.
- Meeting data must remain encrypted on device for the MVP.

## AI Chat Requirements

- Document and implement this feature as AI chat.
- Do not call it `air chat`.
- AI chat answers must be based on local meeting transcript context.
- AI chat can operate over:
  - `This meeting` when invoked from a meeting.
  - `All meetings` when invoked from a global/history surface.
- The active scope must be explicit in the UI, request construction, tests, and errors.
- AI chat uses a direct OpenAI path from the phone app.
- Answers should cite local transcript timestamps when possible.
- AI chat must handle empty transcript, no selected meeting, offline, unsupported, credential-invalid, and model/API error states.

## Email Export Requirements

- User can choose `Transcript`, `Summary`, or `Both` from a dropdown/select before exporting.
- On send, the app presents a checklist of email addresses.
- User can add/remove recipients and check/select recipients at send time.
- App remembers the recipient list and the last selected recipients locally.
- Email export should use device-native mail/share composer semantics where practical.
- The MVP must not operate an outbound mail backend.
- If `Summary` or `Both` is selected, product intent is GPT-5.5 with extra-high reasoning to summarize the transcript.
- Implementation must verify current OpenAI API model and reasoning-parameter support before coding summary generation.
- Summary output must include:
  - brief executive summary paragraph
  - all critical talking points and outcomes as bullet points
  - actions listed at the bottom
  - transcript below the summary if `Both` was selected
- Transcript, summary, recipient addresses, and export payloads must not be logged, sent to app-owned backend infrastructure, or included in analytics/crash reports.

## Privacy, Security, And Logging Requirements

Target users include very high-level executives. Cybersecurity is a first-class acceptance criterion.

- No standard OpenAI API keys in mobile source, committed config, assets, logs, tests, screenshots, or app bundles.
- No app backend, AWS, cloud sync, server mailer, or server-side transcript handling in the MVP.
- Direct OpenAI API calls are the only routine network path for app product behavior.
- User-initiated device mail/share export may hand content to the user's chosen local OS/provider composer; the app must not run an outbound mail backend.
- Local meeting transcript history, summary metadata, sensitive preferences, remembered recipients, and credential/session material must be encrypted on device when implementation exists.
- Use least-privilege mobile permissions. Microphone access is required; any additional permission needs product/security justification.
- Logs and diagnostics must exclude speech, transcript payloads, full prompts, translated content, summaries, recipient lists, raw auth/session tokens, OpenAI credential material, and API keys.
- Crash reporting or analytics, if added later, must use redaction and opt-in/notice appropriate to the product.
- Dependencies must be pinned through lockfiles once implementation exists and checked against credible advisory sources before merge.
- Tests should include negative assertions for transcript routing, secret leakage, and logging/diagnostics leakage.

## Verification Requirements

Minimum verification plan once implementation exists:

- `flutter analyze`
- `flutter test`
- Android emulator smoke check using `android-pixel9-headless`
- Secret scanning or equivalent check that no standard OpenAI API key appears in mobile code/config/assets/tests/build outputs
- Dependency/advisory check for pinned Flutter/Dart/native package versions
- UI smoke checks for supplied mockup-derived surfaces plus meeting management and email export surfaces
- Accessibility checks for labels, focus order, large text, recipient checklist, and contrast-sensitive states
- Privacy routing test showing no transcript/audio/prompt/summary/export content is sent to an app backend
- Logging/diagnostics tests showing transcript, summary, recipients, prompts, microphone audio, and OpenAI credential material are redacted or absent

Tom's Fedora machine has an Android SDK and boot-tested emulator available:

```bash
android-pixel9-headless
```

Do not use:

```bash
emulator -no-window
```

It is known to segfault on this Fedora/KDE/Wayland setup.

## README And Issue Maintenance

- Update [README.md](../README.md) whenever setup, architecture, behavior, issue status, verification steps, or known risks change.
- Keep GitHub issue scope aligned with this build spec and acceptance criteria.
- Close completed issues only after matching verification has run or the reason for skipped verification is documented.
- If a new implementation gap appears, create or update a focused issue instead of burying it in an unrelated task.

## GitHub Issue Map

Closed planning and implementation intake:

- #1 Finalize product spec and mockup intake.
- #2 Scaffold Flutter mobile app.
- #11 Document Android emulator workflow for Codex.

Open MVP/planning work:

- #3 Implement Flutter UI from supplied mockups for phone-only MVP.
- #6 Integrate direct OpenAI Realtime Translation.
- #7 Implement language support and fallback routing.
- #8 Add scoped AI chat over local meetings.
- #9 Implement local encrypted meeting storage.
- #10 Maintain cybersecurity threat model and report.
- #12 Create phone-only MVP test strategy.
- #13 Implement microphone permissions and live session lifecycle.
- #14 Harden direct OpenAI realtime resilience.
- #15 Implement privacy-safe local logging and diagnostics controls.
- #16 Add CI quality gates for docs, Flutter, and secret safety.
- #17 Add accessibility and responsive text verification.
- #18 Define Flutter design tokens and reusable mockup components.
- #19 Maintain README and agent handoff docs during implementation.
- #20 Implement local meeting management.
- #21 Add email export for transcripts and summaries.
- #22 Implement dependency and supply-chain cybersecurity controls.

Deferred V2/future issues:

- #4 V2: Implement Google and Microsoft sign-in.
- #5 V2: Build AWS Lambda token broker.

## Initial Non-Goals

- Full iOS release.
- Organization/team admin console.
- App backend.
- AWS API Gateway or Lambda.
- Token broker.
- Google/Microsoft cloud identity as an MVP gate.
- Cloud transcript storage or sync.
- Server-side transcript, audio, summary, or email handling.
- Outbound mail backend.
- Human interpreter marketplace.
- Heavy backend business logic.

## Open Questions To Resolve During Implementation

- Final Android package name and signing certificate details.
- Current OpenAI-supported direct mobile credential/session approach.
- Current OpenAI Realtime Translation target output language support list and fallback route details.
- Current OpenAI API support for GPT-5.5 and extra-high reasoning parameters for summary generation.
- Whether the MVP uses user-provided OpenAI credential material or another currently supported direct OpenAI approach.
- Whether diagnostics/crash reporting is included in MVP or deferred.
