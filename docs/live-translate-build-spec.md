# Live Translate Build Spec

This is the canonical build spec for the Realtime Translate Mobile repo. Future implementation, issue triage, README updates, and UI work should use this document as the first source of truth.

## Product Goal

Build an Android-first, iOS-compatible Flutter app for continuous live speech translation using OpenAI Realtime Translation. The app should feel premium, clean, and executive-grade, with live translation as the first usable surface rather than a technical dashboard.

## Fixed Decisions

| Area | Decision |
| --- | --- |
| Mobile framework | Flutter |
| Platform order | Android first, iOS-compatible later |
| Backend | Minimal AWS API Gateway + Lambda token broker |
| OpenAI access | Mobile app connects directly to OpenAI using short-lived client secrets |
| Live model | `gpt-realtime-translate` |
| Transcript Q&A | Prefer a direct OpenAI path that avoids AWS seeing transcript content |
| Storage | Encrypted local device storage only |
| Identity | Microsoft personal, Microsoft work/school organizational accounts, and Google sign-in |
| Mockups | Supplied Android mockups in `assets/mockups/` |

## Source Documents And Assets

- README and repo status: [README.md](../README.md)
- Agent operating instructions: [AGENTS.md](../AGENTS.md)
- UX interpretation: [docs/mockup-ux-spec.md](mockup-ux-spec.md)
- High-level product spec: [docs/product-spec.md](product-spec.md)
- Starter prompt for first implementation: [docs/codex-starter-prompt.md](codex-starter-prompt.md)

Supplied mockups:

- [assets/mockups/01-welcome-sign-in.jpg](../assets/mockups/01-welcome-sign-in.jpg)
- [assets/mockups/02-live-listening-teal.jpg](../assets/mockups/02-live-listening-teal.jpg)
- [assets/mockups/03-transcript-assistant.jpg](../assets/mockups/03-transcript-assistant.jpg)
- [assets/mockups/04-speaking-paused-amber.jpg](../assets/mockups/04-speaking-paused-amber.jpg)

## MVP User Flow

1. User opens the app and sees the premium sign-in/welcome surface.
2. User signs in with Microsoft personal, Microsoft work/school, or Google identity.
3. App requests a short-lived OpenAI client secret from the AWS token broker after identity validation.
4. User chooses source auto-detect or a known input language.
5. User chooses a supported output language.
6. App starts a direct OpenAI Realtime Translation session from the mobile app.
7. App streams microphone audio to OpenAI and receives translated audio plus transcript deltas while the speaker is still talking.
8. User can pause/resume read-aloud, skip queued audio to live, switch direction, and jump to the latest transcript.
9. User can review encrypted local transcript history.
10. User can ask Q&A about the transcript without sending transcript content through AWS.

## Mobile App Requirements

- Scaffold a Flutter project that builds for Android now and does not block iOS later.
- Keep platform-specific code isolated behind clear interfaces.
- Use Android runtime microphone permission flows before recording.
- Never start recording before explicit permission is granted.
- Handle permission denied, permanently denied, and permission revoked states.
- Model live session state explicitly, including at least:
  - `signedOut`
  - `signedIn`
  - `requestingClientSecret`
  - `connecting`
  - `listening`
  - `speaking`
  - `readAloudPaused`
  - `reconnecting`
  - `expired`
  - `error`
- Handle app lifecycle transitions such as backgrounding, foregrounding, audio focus changes, headset/speaker route changes, network loss, and session teardown.
- Keep transcript rows structured by language, original text, translated text, timestamp, speaker ownership, confidence/status, accent, and playback state.
- Store preferences, recent languages, and transcript history locally with encryption.
- Provide retention and delete controls for transcript history.
- Do not add cloud transcript sync in the MVP.

## UI Requirements

Use [docs/mockup-ux-spec.md](mockup-ux-spec.md) and the four image files as the visual and interaction source of truth.

Required first-pass surfaces:

- Welcome/sign-in screen.
- Main live translation screen in teal listening mode.
- Transcript assistant bottom sheet over a dimmed live screen.
- Main live translation screen in amber speaking/read-aloud-paused mode.

Required UI foundations:

- Small design token layer for colors, spacing, radii, typography, shadows/elevation, and state colors.
- Reusable components for app shell, header, status card, language selectors, direction switch, feature toggles, transcript cards, queue banner, jump-to-live chip, bottom controls, auth provider buttons, assistant sheet, prompt chips, input, and privacy notes.
- Safe-area handling for Android status/navigation bars.
- Bottom transcript padding equal to fixed controls plus safe-area inset.
- Large-text and small-device handling so labels, buttons, transcript rows, and bottom controls do not overlap or clip.
- Semantic labels for icon-only controls and accessibility coverage for auth, live controls, language selection, playback, assistant, and transcript actions.

## Backend Requirements

The backend is deliberately narrow.

- Use AWS API Gateway + Lambda as a token broker.
- Validate signed-in caller identity/session before issuing any OpenAI client secret.
- Store the standard OpenAI API key only in backend secret storage/config.
- Request short-lived OpenAI client secrets for the mobile app.
- Return only the short-lived secret and required metadata, including expiry information.
- Do not provide any endpoint that ingests transcript or audio content.
- Do not log transcript content, audio content, full request bodies, bearer tokens, client secrets, standard OpenAI API keys, or identity tokens.
- Document token expiry, refresh, and error behavior.

## OpenAI Realtime Requirements

- Use `gpt-realtime-translate` as the primary live translation model.
- Connect from the mobile app directly to OpenAI with a short-lived client secret.
- Stream microphone audio to OpenAI.
- Receive translated audio and transcript deltas while the speaker is still talking.
- Proactively refresh or re-request client secrets before expiry when possible.
- Recover from expiry, network drops, transient OpenAI errors, and app lifecycle interruption with bounded reconnect/backoff behavior.
- Keep user-facing state clear during connecting, reconnecting, expired-token, unsupported-language, offline, and permission-denied states.
- Verify current OpenAI Realtime Translation language support during implementation rather than hard-coding stale external assumptions.

## Language Support And Fallback

OpenAI Realtime Translation is expected to have broad input language coverage and narrower target output language coverage. The app must plan for unsupported target output languages.

Implementation requirements:

- Keep a centralized, easy-to-update language support table.
- Show only valid realtime target languages by default.
- Detect when a requested target language is unsupported by realtime output.
- Provide a clear fallback path for broader target language support.
- Make fallback behavior explicit in the UI rather than failing silently.
- Keep fallback transcript Q&A and translation routes privacy-preserving; AWS must not see transcript content.

## Identity Requirements

Supported sign-in methods:

- Microsoft personal accounts.
- Microsoft work/school organizational accounts.
- Google sign-in.

Implementation requirements:

- Microsoft app registration must support both personal and work/school account types.
- Google Android credentials must match package name and signing certificate.
- Backend token broker must validate identity/session before issuing OpenAI client secrets.
- README setup docs must list required auth configuration values without committing real secrets.
- Sign-out must clear sensitive local session material and stop active realtime sessions.

## Transcript Q&A Requirements

- Q&A answers must be based on the current local transcript.
- AWS must not see transcript content.
- Prefer direct OpenAI access from the app with appropriate short-lived credentials or another direct privacy-preserving path.
- Assistant UI must be visually scoped to current transcript context.
- Answers should cite local transcript timestamps when possible.
- Q&A must handle empty transcript, offline, unsupported, expired secret, and model/API error states.

## Privacy And Logging Requirements

- No standard OpenAI API keys in mobile source, config, assets, logs, tests, or app bundles.
- No transcript/audio content through AWS.
- No cloud transcript sync for MVP.
- Local transcript storage must be encrypted.
- Logs and diagnostics must exclude speech, transcript payloads, full prompts, translated content, raw auth tokens, OpenAI client secrets, and standard API keys.
- Crash reporting or diagnostics, if added later, must use redaction and opt-in/notice appropriate to the product.
- Tests should include negative assertions for transcript routing and secret leakage.

## Verification Requirements

Minimum verification plan once implementation exists:

- `flutter analyze`
- `flutter test`
- Android emulator smoke check using `android-pixel9-headless`
- Backend unit tests for token broker request/response, identity validation, expiry metadata, and logging redaction
- Secret scanning or equivalent check that no standard OpenAI API key appears in mobile code/config
- UI smoke checks for all four mockup surfaces
- Accessibility checks for labels, focus order, large text, and contrast-sensitive states
- Privacy routing test showing transcript Q&A does not call AWS transcript endpoints

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

Closed planning intake:

- #1 Finalize product spec and mockup intake.

Open MVP/planning work:

- #2 Scaffold Flutter mobile app.
- #3 Implement Flutter UI from supplied mockups.
- #4 Implement Google and Microsoft sign-in.
- #5 Build AWS Lambda token broker.
- #6 Integrate OpenAI Realtime Translation.
- #7 Implement language support and fallback routing.
- #8 Add privacy-preserving transcript Q&A.
- #9 Implement local encrypted storage.
- #10 Write security and privacy threat model.
- #11 Document Android emulator workflow for Codex.
- #12 Create MVP test strategy.
- #13 Implement microphone permissions and live session lifecycle.
- #14 Harden realtime connection resilience and token refresh.
- #15 Implement privacy-safe logging and diagnostics controls.
- #16 Add CI quality gates for docs, Flutter, backend, and secret safety.
- #17 Add accessibility and responsive text verification.
- #18 Define Flutter design tokens and reusable mockup components.
- #19 Maintain README and agent handoff docs during implementation.

## Initial Non-Goals

- Full iOS release.
- Organization/team admin console.
- Cloud transcript storage.
- Human interpreter marketplace.
- Heavy backend business logic.
- AWS transcript processing or transcript persistence.

## Open Questions To Resolve During Implementation

- Final Android package name and signing certificate details.
- Exact Microsoft and Google app registration values.
- Final OpenAI client secret broker request/response schema.
- Current target output language support list and fallback route details.
- Whether transcript Q&A uses the same realtime short-lived secret flow or a separate direct OpenAI credential flow.
- Whether diagnostics/crash reporting is included in MVP or deferred.
