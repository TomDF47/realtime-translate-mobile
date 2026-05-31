# Architecture Review: Translator Live-Path Gaps

Date: 2026-05-31

Reviewer stance: solution architect review only. No application source code was changed.

Inputs read:

- `docs/live-translate-build-spec.md`
- `README.md`
- `docs/CURRENT_REQUIREMENTS.md`
- `docs/development-workflow.md`
- `docs/architecture.md`
- `docs/testing-strategy.md`
- `docs/cybersecurity-report.md`
- `docs/decision-log.md`
- `docs/mockup-ux-spec.md`
- All supplied mockups in `assets/mockups/`
- Relevant implementation and test seams under `lib/src/session`, `lib/src/openai`, `lib/main.dart`, `test/`, and `scripts/`

GitHub issue inspection result: `gh issue list --state all --limit 80 --json number,title,state,labels,updatedAt,url` failed because this sandbox could not connect to `api.github.com`. Existing issue state was inferred from the repo issue maps in `README.md` and `docs/live-translate-build-spec.md`. Issue-ready markdown was written under `docs/issues-to-create/` as the fallback.

## Merge-Blocking / Product Blockers

1. The current live runtime architecture does not yet prove the real installed live path that Tom is testing.

   The requirements say the product must show original speech and translation, detect language changes such as Italian, split blocks on language/source changes, show a visible startup indicator, and provide pause listening. The testing docs explicitly say current generated-speech and debug-event paths do not prove Android physical microphone capture, installed-app live speech persistence, credential-expiry recovery with real credential material, or audible speaker output. The current operator report says the translate app is still not working.

   Evidence:
   - `docs/CURRENT_REQUIREMENTS.md` lines 148-157 list the active defects and remaining physical/live validation gap.
   - `docs/testing-strategy.md` lines 28-30 distinguish fake/debug/generated-event proof from real installed microphone/live-path proof.
   - `docs/architecture.md` line 105 keeps physical microphone translation smoke and live app-coordinator de-duplication open.

   Required action: prioritize wired installed live-path proof over additional isolated `LiveTextInterpreter` or fake coordinator tests.

2. The active realtime architecture has a bidirectional interpretation mismatch.

   The requirements demand A-to-B and B-to-A without manual direction switching. The app starts a single `gpt-realtime-translate` session with one configured output language, defaulting the new meeting target to English. A single dedicated translation session configured with `audio.output.language: en` can translate other speech into English, but it does not establish how English speech is translated back into Italian after Italian is detected.

   Evidence:
   - `docs/CURRENT_REQUIREMENTS.md` lines 47-53 require pair lock and bidirectional later turns.
   - `lib/main.dart` lines 495-499 default the live target to English on start.
   - `lib/main.dart` lines 543-564 starts one realtime session using `_selectedTargetLanguage.code`.
   - `lib/src/openai/openai_realtime_translation.dart` lines 176-184 configures the dedicated translation session with a single `audio.output.language`.
   - `docs/CURRENT_REQUIREMENTS.md` line 183 leaves Italian output support/fallback as an open question.

   Required action: decide and implement a phone-only bidirectional runtime design before declaring the live interpreter fixed.

3. The currently tested text interpreter path is not the installed live speech path.

   `LiveTextInterpreter` has a coherent text-first state machine for language discovery and delayed translation backfill, but the app live start path wires `LiveRealtimeTranslationCoordinator`, microphone capture, realtime WebSocket events, and `LiveRealtimeTranscriptCommitter`. The Cursor gap analysis warning is valid: isolated text interpreter tests can pass while Tom's installed app remains broken.

   Evidence:
   - `lib/src/session/live_text_interpreter.dart` lines 5-38 define the isolated text interpreter route label state.
   - `lib/main.dart` lines 543-564 starts `LiveRealtimeTranslationCoordinator` for the active live meeting.
   - `docs/testing-strategy.md` lines 28-30 state the installed E2E/debug proof does not prove physical microphone speech injection or committed live speech deltas.

   Required action: stop using `LiveTextInterpreter` coverage as evidence for installed live translation unless the active UI is explicitly rewired to it.

## Architecture / Runtime-Path Gaps

1. Header language detection is derived from stored transcript language codes, not an explicit live pair model.

   The active header label is inferred from persisted transcript entries. That can work after source transcript rows commit, but it is brittle for translation-first events, missing language metadata, late local detection, and pair-lock ordering. The product needs a runtime model that tracks first detected source language, second distinct language, and locked pair independently of storage refresh timing.

   Evidence:
   - `lib/main.dart` lines 174-201 builds the interpreter label from transcript entry language codes.
   - `lib/main.dart` lines 606-638 refresh stored meetings asynchronously after commits.
   - `lib/src/session/realtime_transcript_committer.dart` lines 201-223 falls back to target language if source language is not detected.

2. The committer block rolling behavior is locally tested but not proven with real dedicated translation event ordering.

   Unit tests cover source item changes, language change, translation-first backfill, and Italian fallback. However, the test that simulates English then Italian leaves the Italian row without a translated text at the assertion point, which is not a full product pass. The current issue is not only "split blocks"; it is split blocks plus translated output in the real live path.

   Evidence:
   - `test/realtime_translation_coordinator_test.dart` lines 839-910 verifies English then Italian split, but the Italian entry has empty `translatedText`.
   - `test/realtime_translation_coordinator_test.dart` lines 914-980 verifies translation-first backfill for Italian in a fake event sequence.
   - `docs/CURRENT_REQUIREMENTS.md` lines 103-110 require every visible card to show original and translation and to split on language changes.

3. Existing debug/live smokes validate useful seams but not Tom's reported failure mode.

   The live smoke validates generated host speech through OpenAI and the debug E2E validates generated events through the installed coordinator. Neither proves that Android microphone audio from the installed app produces committed original+translation transcript rows for English and Italian.

   Evidence:
   - `scripts/live_openai_smoke.dart` reports event counts without printing payloads, which is correct for privacy but not an installed-app UI assertion.
   - `scripts/android_emulator_e2e.sh` has `--debug-live-events` and `--require-device-audio`, but the docs say this still does not prove physical microphone speech or live OpenAI app-coordinator reconnect.

## Requirements Mismatches

1. Bidirectional pair lock is specified, but runtime target selection remains one target language.

   The app must either run a documented dual-session/direct-fallback architecture or explicitly constrain the first live slice to one-way source-to-English until pair routing is solved. Current docs say the product is bidirectional; current runtime config is single-target.

2. Italian is required as a detected spoken source, but Italian output support is unresolved.

   Requirements say Italian must be detected and translated, while the conservative realtime target table remains English, Spanish, and French. If the pair is English/Italian, English-to-Italian cannot be assumed on the dedicated realtime route without accepted fallback design.

3. Pause/loading controls appear in source and tests, but Tom's app report may be against an older or different installed artifact.

   The review found source-level evidence for `Pause Listening` and `Connecting to OpenAI`; the next agent must prove those controls in the exact APK/install path Tom is using, not only widget tests.

## Verification Gaps

1. No current pass/fail artifact proves: start installed app, save live credential, connect, inject or speak English then Italian, observe `English <-> Italian`, observe separate transcript blocks, observe original and translation on both final blocks, pause/resume, and confirm no hidden old controls after screenshot/overlay/lifecycle.

2. No current automated gate fails if the real live path never receives source/original transcript events from OpenAI for the dedicated translation session.

3. No current automated gate proves bidirectional translation for an English/Italian pair through the chosen runtime design.

4. GitHub issue state could not be inspected live because `gh` could not reach GitHub from this environment.

## Recommended Sequencing

1. Issue #6 update: build a wired installed live-path proof and make it the release-blocking gate for the translator. This is the top priority.
2. New architecture issue: resolve bidirectional two-language runtime routing for a single-target realtime translation API, including Italian output/fallback behavior.
3. Issue #31 update: wire header language-pair state and transcript block rolling to real realtime source metadata/item IDs, with installed-path proof for English then Italian.
4. New UI regression issue: reproduce and prevent hidden old route controls after screenshot/overlay/lifecycle.
5. Issue #14 update: validate reconnect/credential/rate-limit behavior in the installed live path after #6 establishes trustworthy live speech evidence.

## Issue Artifacts Created Locally

Because GitHub was unreachable, issue-ready markdown files were written to:

- `docs/issues-to-create/update-issue-6-wired-installed-live-path-proof.md`
- `docs/issues-to-create/new-issue-bidirectional-runtime-routing.md`
- `docs/issues-to-create/update-issue-31-live-header-block-splitting.md`
- `docs/issues-to-create/new-issue-hidden-controls-overlay-regression.md`
- `docs/issues-to-create/update-issue-14-live-reconnect-validation.md`

Architecture standard result: blocked until the bidirectional runtime design and wired live-path evidence exist.

Recommendation: block "translator fixed" claims and max-agent implementation convergence until the issue sequence above is addressed.
