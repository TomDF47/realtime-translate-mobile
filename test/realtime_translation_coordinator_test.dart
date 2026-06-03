import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/diagnostics/privacy_safe_diagnostics.dart';
import 'package:realtime_translate_mobile/src/language/language_support.dart';
import 'package:realtime_translate_mobile/src/openai/openai_credential_store.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_resilience.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';
import 'package:realtime_translate_mobile/src/openai/openai_text_interpreter.dart';
import 'package:realtime_translate_mobile/src/session/live_session_controller.dart';
import 'package:realtime_translate_mobile/src/session/microphone_capture.dart';
import 'package:realtime_translate_mobile/src/session/microphone_permission.dart';
import 'package:realtime_translate_mobile/src/session/realtime_translation_coordinator.dart';
import 'package:realtime_translate_mobile/src/session/realtime_transcript_committer.dart';
import 'package:realtime_translate_mobile/src/session/translated_audio_playback.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';
import 'package:realtime_translate_mobile/src/storage/local_storage_models.dart';

void main() {
  const config = OpenAiRealtimeTranslationConfig(targetLanguageCode: 'en');

  test('missing credential blocks permission, realtime, and capture', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
      seedCredential: false,
    );

    final result = await harness.coordinator.start(config: config);

    expect(result, LiveRealtimeStartResult.missingCredential);
    expect(harness.controller.state.phase, LiveSessionPhase.credentialInvalid);
    expect(harness.permissionGateway.requestCount, 0);
    expect(harness.realtimeGateway.connectCount, 0);
    expect(harness.captureGateway.startCount, 0);
    expect(harness.captureGateway.isCapturing, isFalse);
  });

  test('denied microphone permission blocks realtime and capture', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.denied,
    );

    final result = await harness.coordinator.start(config: config);

    expect(result, LiveRealtimeStartResult.permissionNotGranted);
    expect(harness.controller.state.phase, LiveSessionPhase.microphoneDenied);
    expect(harness.realtimeGateway.connectCount, 0);
    expect(harness.captureGateway.startCount, 0);
    expect(harness.captureGateway.isCapturing, isFalse);
  });

  test('streams PCM16 microphone chunks into realtime gateway', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
    );

    final result = await harness.coordinator.start(config: config);
    harness.captureGateway.addChunk([0, 1, 2, 3]);
    await Future<void>.delayed(Duration.zero);

    expect(result, LiveRealtimeStartResult.started);
    expect(harness.controller.state.phase, LiveSessionPhase.listening);
    expect(harness.captureGateway.startCount, 1);
    expect(
      harness.captureGateway.lastConfig,
      isA<MicrophoneCaptureConfig>()
          .having((value) => value.sampleRateHz, 'sampleRateHz', 24000)
          .having(
            (value) => value.chunkDuration,
            'chunkDuration',
            const Duration(milliseconds: 200),
          ),
    );
    expect(harness.realtimeGateway.configs.single.targetLanguageCode, 'en');
    expect(
      harness.realtimeGateway.configs.single.profile,
      OpenAiRealtimeTranslationProfile.dedicatedTranslation,
    );
    expect(
      harness.realtimeGateway.credentials.single,
      'placeholder-credential',
    );
    expect(harness.realtimeGateway.session.appendedChunks.single, [0, 1, 2, 3]);
    expect(harness.realtimeGateway.session.commitInputAudioBufferCount, 0);
    expect(harness.realtimeGateway.session.createResponseCount, 0);
  });

  test(
    'initial realtime connect timeout enters visible reconnecting state',
    () async {
      final reconnectDelays = <Duration>[];
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        reconnectDelay: (delay) {
          reconnectDelays.add(delay);
          return Completer<void>().future;
        },
        connectionTimeout: const Duration(milliseconds: 1),
      );
      harness.realtimeGateway.hangNextConnect = true;

      final result = await harness.coordinator.start(config: config);
      await _drainAsync();

      expect(result, LiveRealtimeStartResult.failed);
      expect(harness.realtimeGateway.connectCount, 1);
      expect(harness.captureGateway.isCapturing, isFalse);
      expect(harness.playbackGateway.isOpen, isFalse);
      expect(harness.controller.state.phase, LiveSessionPhase.reconnecting);
      expect(harness.controller.state.realtimeRetryAttempt, 1);
      expect(reconnectDelays, hasLength(1));
    },
  );

  test(
    'hung microphone capture startup leaves connecting for bounded recovery',
    () async {
      final reconnectDelays = <Duration>[];
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        reconnectDelay: (delay) {
          reconnectDelays.add(delay);
          return Completer<void>().future;
        },
        startupStepTimeout: const Duration(milliseconds: 1),
      );
      harness.captureGateway.hangStart = true;

      final result = await harness.coordinator.start(config: config);
      await _drainAsync();

      // The connect succeeded; only the post-connect microphone bring-up hung.
      // The session must not stay pinned in connecting / "Preparing live
      // session"; it transitions into the bounded recovery state machine.
      expect(result, LiveRealtimeStartResult.failed);
      expect(harness.realtimeGateway.connectCount, 1);
      expect(harness.captureGateway.startCount, 1);
      expect(harness.captureGateway.isCapturing, isFalse);
      expect(harness.controller.state.phase, LiveSessionPhase.reconnecting);
      expect(harness.controller.state.realtimeRetryAttempt, 1);
      expect(reconnectDelays, hasLength(1));
    },
  );

  test(
    'hung translated-audio playback startup leaves connecting for bounded recovery',
    () async {
      final reconnectDelays = <Duration>[];
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        reconnectDelay: (delay) {
          reconnectDelays.add(delay);
          return Completer<void>().future;
        },
        startupStepTimeout: const Duration(milliseconds: 1),
      );
      harness.playbackGateway.hangStart = true;

      final result = await harness.coordinator.start(config: config);
      await _drainAsync();

      expect(result, LiveRealtimeStartResult.failed);
      expect(harness.realtimeGateway.connectCount, 1);
      expect(harness.playbackGateway.startCount, 1);
      // Microphone capture must never open if playback bring-up never finished.
      expect(harness.captureGateway.startCount, 0);
      expect(harness.captureGateway.isCapturing, isFalse);
      expect(harness.controller.state.phase, LiveSessionPhase.reconnecting);
    },
  );

  test(
    'persistently hung startup is bounded and ends in a terminal recovery state',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        reconnectPolicy: const OpenAiRealtimeReconnectPolicy(
          maxAttempts: 1,
          initialDelay: Duration.zero,
          maxDelay: Duration.zero,
          jitterRatio: 0,
        ),
        reconnectDelay: (_) => Future<void>.value(),
        startupStepTimeout: const Duration(milliseconds: 1),
      );
      harness.captureGateway.hangStart = true;

      final result = await harness.coordinator.start(config: config);
      // Bounded poll: every startup attempt hangs, so the coordinator must
      // exhaust its retries and settle in a terminal recovery state rather than
      // stalling on connecting forever.
      for (var i = 0;
          i < 40 &&
              harness.controller.state.phase != LiveSessionPhase.offline &&
              harness.controller.state.phase != LiveSessionPhase.error;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(result, LiveRealtimeStartResult.failed);
      expect(harness.controller.state.phase, LiveSessionPhase.offline);
      expect(harness.captureGateway.isCapturing, isFalse);
    },
  );

  test(
    'startup failure before session readiness does not start capture',
    () async {
      final reconnectDelays = <Duration>[];
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        reconnectDelay: (delay) {
          reconnectDelays.add(delay);
          return Completer<void>().future;
        },
      );
      harness.realtimeGateway.failNextConnect = true;

      final result = await harness.coordinator.start(config: config);
      await _drainAsync();

      expect(result, LiveRealtimeStartResult.failed);
      expect(harness.realtimeGateway.connectCount, 1);
      expect(reconnectDelays, hasLength(1));
      expect(harness.captureGateway.startCount, 0);
      expect(harness.captureGateway.isCapturing, isFalse);
      expect(harness.playbackGateway.isOpen, isFalse);
      expect(harness.controller.state.phase, LiveSessionPhase.reconnecting);
    },
  );

  test(
    'decodes realtime translated audio deltas into playback queue',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );

      final result = await harness.coordinator.start(config: config);
      harness.realtimeGateway.session.addEvent(
        OpenAiRealtimeAudioDelta(
          type: 'session.output_audio.delta',
          base64Audio: base64Encode([4, 5, 6, 7]),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(result, LiveRealtimeStartResult.started);
      expect(harness.playbackGateway.startCount, 1);
      expect(
        harness.playbackGateway.lastConfig,
        isA<TranslatedAudioPlaybackConfig>()
            .having((value) => value.sampleRateHz, 'sampleRateHz', 24000)
            .having((value) => value.channelCount, 'channelCount', 1),
      );
      expect(harness.playbackGateway.enqueuedChunks, hasLength(1));
      expect(harness.playbackGateway.enqueuedChunks.single.bytes, [4, 5, 6, 7]);
      expect(harness.playbackGateway.enqueuedChunks.single.sampleRateHz, 24000);
      expect(harness.playbackGateway.enqueuedChunks.single.channelCount, 1);
    },
  );

  test(
    'commits realtime transcript deltas into active meeting storage',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 4);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Live smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      final result = await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hola ',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Hola',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Hello',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: ' there',
          ),
        );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      var snapshot = await harness.repository.loadSnapshot();
      var entries = snapshot.meetings.single.transcriptEntries;
      expect(result, LiveRealtimeStartResult.started);
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Hola');
      expect(entries.single.translatedText, 'Hello there');
      // The Spanish source resolves to ES from local detection; it must not
      // default to the EN target language.
      expect(entries.single.languageCode, 'ES');
      expect(entries.single.status, 'partial');

      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.output_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.translation,
          transcript: 'Hello there.',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      snapshot = await harness.repository.loadSnapshot();
      entries = snapshot.meetings.single.transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.translatedText, 'Hello there.');
      expect(entries.single.status, 'final');

      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Second segment',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Second segment.',
          ),
        );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      snapshot = await harness.repository.loadSnapshot();
      entries = snapshot.meetings.single.transcriptEntries;
      expect(entries, hasLength(2));
      expect(entries.last.translatedText, 'Second segment.');
      expect(entries.last.status, 'partial');
    },
  );

  test('source transcript delta is visible before completion', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
    );
    final startedAt = DateTime.utc(2026, 5, 24, 4, 10);
    await harness.repository.upsertMeeting(
      StoredMeeting(
        id: 'meeting-1',
        title: 'Streaming source smoke',
        createdAt: startedAt,
        updatedAt: startedAt,
        sourceLanguageLabel: 'Auto-detect Spanish',
        targetLanguageLabel: 'English',
        transcriptEntries: const [],
        summaryMetadata: const StoredSummaryMetadata.empty(),
      ),
    );

    await harness.coordinator.start(
      config: config,
      transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
        repository: harness.repository,
        meetingId: 'meeting-1',
        sourceLanguageCode: 'auto',
        targetLanguageCode: 'en',
        now: () => startedAt,
      ),
    );
    harness.realtimeGateway.session.addEvent(
      const OpenAiRealtimeTranscriptDelta(
        type: 'session.input_transcript.delta',
        kind: OpenAiRealtimeTranscriptKind.source,
        itemId: 'source-live-1',
        delta: 'Estoy hablando',
      ),
    );
    await _drainAsync();

    final entries = (await harness.repository.loadSnapshot())
        .meetings
        .single
        .transcriptEntries;
    expect(entries, hasLength(1));
    expect(entries.single.originalText, 'Estoy hablando');
    expect(entries.single.translatedText, isEmpty);
    expect(entries.single.status, 'partial');
  });

  test(
    'suppresses translation transcript and read-aloud output when disabled',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 4);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Live smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      final result = await harness.coordinator.start(
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'en',
          translationOutputEnabled: false,
          readAloudOutputEnabled: false,
        ),
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hola.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Hello.',
          ),
        )
        ..addEvent(
          OpenAiRealtimeAudioDelta(
            type: 'session.output_audio.delta',
            base64Audio: base64Encode([4, 5, 6, 7]),
          ),
        );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(result, LiveRealtimeStartResult.started);
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Hola.');
      expect(entries.single.translatedText, isEmpty);
      expect(harness.playbackGateway.enqueuedChunks, isEmpty);
    },
  );

  test(
    'read-aloud off keeps translated text but suppresses audio chunks',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 4, 20);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Read aloud toggle smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      final result = await harness.coordinator.start(
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'en',
          readAloudOutputEnabled: false,
        ),
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Hello.',
          ),
        )
        ..addEvent(
          OpenAiRealtimeAudioDelta(
            type: 'session.output_audio.delta',
            base64Audio: base64Encode([4, 5, 6, 7]),
          ),
        );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(result, LiveRealtimeStartResult.started);
      expect(entries, hasLength(1));
      expect(entries.single.translatedText, 'Hello.');
      expect(harness.playbackGateway.enqueuedChunks, isEmpty);
    },
  );

  test(
    'dedicated translation source and output deltas commit into one paired card',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 4);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Dedicated translation smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      final result = await harness.coordinator.start(
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'en',
          profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
        ),
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Buenos dias.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Good morning.',
          ),
        );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(result, LiveRealtimeStartResult.started);
      expect(
        harness.realtimeGateway.configs.single.profile,
        OpenAiRealtimeTranslationProfile.dedicatedTranslation,
      );
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Buenos dias.');
      expect(entries.single.translatedText, 'Good morning.');
    },
  );

  test('rolls streaming transcript into one-sentence paired blocks', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
    );
    final startedAt = DateTime.utc(2026, 5, 24, 4);
    await harness.repository.upsertMeeting(
      StoredMeeting(
        id: 'meeting-1',
        title: 'Live smoke',
        createdAt: startedAt,
        updatedAt: startedAt,
        sourceLanguageLabel: 'Auto-detect Spanish',
        targetLanguageLabel: 'English',
        transcriptEntries: const [],
        summaryMetadata: const StoredSummaryMetadata.empty(),
      ),
    );

    await harness.coordinator.start(
      config: config,
      transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
        repository: harness.repository,
        meetingId: 'meeting-1',
        sourceLanguageCode: 'auto',
        targetLanguageCode: 'en',
        now: () => startedAt,
      ),
    );
    harness.realtimeGateway.session
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.input_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.source,
          itemId: 'source-1',
          delta: 'Primera frase.',
        ),
      )
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.output_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.translation,
          delta: 'First sentence.',
        ),
      )
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.input_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.source,
          itemId: 'source-2',
          delta: 'Segunda frase.',
        ),
      )
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.output_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.translation,
          delta: 'Second sentence.',
        ),
      );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final entries = (await harness.repository.loadSnapshot())
        .meetings
        .single
        .transcriptEntries;
    expect(entries, hasLength(2));
    expect(entries.first.originalText, 'Primera frase.');
    expect(entries.first.translatedText, 'First sentence.');
    expect(entries.last.originalText, 'Segunda frase.');
    expect(entries.last.translatedText, 'Second sentence.');
  });

  test(
    'keeps delayed source transcript on the same card as translation',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 4);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Live smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'One, two, three.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Uno, dos, tres.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Uno, dos, tres.',
          ),
        );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Uno, dos, tres.');
      expect(entries.single.translatedText, 'One, two, three.');
    },
  );

  test(
    'input transcription item events update original text on the active row',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 4, 30);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Input transcript smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'English',
          targetLanguageLabel: 'Spanish',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: const OpenAiRealtimeTranslationConfig(
          sourceLanguageCode: 'en',
          targetLanguageCode: 'es',
        ),
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'es',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'response.output_text.delta',
          kind: OpenAiRealtimeTranscriptKind.translation,
          delta: 'Amarillo, ',
        ),
      );
      await _drainAsync();

      var entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, isEmpty);
      expect(entries.single.translatedText, 'Amarillo,');

      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'conversation.item.input_audio_transcription.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'input-item-1',
            delta: "yellow what's ",
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'conversation.item.input_audio_transcription.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'input-item-1',
            delta: 'going on',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'conversation.item.input_audio_transcription.completed',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'input-item-1',
            transcript: "yellow what's going on",
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'response.output_text.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Amarillo, que esta pasando?',
          ),
        );
      await _drainAsync();

      entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, "yellow what's going on");
      expect(entries.single.translatedText, 'Amarillo, que esta pasando?');
      expect(entries.single.status, 'final');
    },
  );

  test(
    'new input transcription item id starts a new transcript block',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 4, 45);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Item id smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'English',
          targetLanguageLabel: 'Spanish',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: const OpenAiRealtimeTranslationConfig(
          sourceLanguageCode: 'en',
          targetLanguageCode: 'es',
        ),
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'es',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'conversation.item.input_audio_transcription.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'input-item-1',
            delta: 'First turn.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'response.output_text.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Primer turno.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'conversation.item.input_audio_transcription.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'input-item-2',
            delta: 'Second turn.',
          ),
        );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(2));
      expect(entries.first.id, endsWith('input-item-1'));
      expect(entries.first.originalText, 'First turn.');
      expect(entries.first.translatedText, 'Primer turno.');
      expect(entries.last.id, endsWith('input-item-2'));
      expect(entries.last.originalText, 'Second turn.');
      expect(entries.last.translatedText, isEmpty);
    },
  );

  test(
    'English then Italian source text creates separate language-coded blocks',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 28, 3);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Language roll smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hello, thank you.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Hello, thank you.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Ciao, grazie.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Ciao, grazie.',
          ),
        );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(2));
      expect(entries.first.languageCode, 'EN');
      expect(entries.first.originalText, 'Hello, thank you.');
      expect(entries.first.translatedText, 'Ciao, grazie.');
      expect(entries.first.status, 'final');
      expect(entries.last.languageCode, 'IT');
      expect(entries.last.originalText, 'Ciao, grazie.');
      expect(entries.last.translatedText, isEmpty);
    },
  );

  test(
    'live English paragraph then Italian turn splits blocks without item ids '
    'or language metadata',
    () async {
      // Reproduces Tom's 2026-06-01 installed-app report against the real
      // /v1/realtime/translations wire shape: source and translation deltas
      // arrive interleaved with NO item_id and NO language metadata. A long
      // English paragraph is spoken, then the Italian phrase meaning "Good
      // morning, how are you?". The first block must keep the English original
      // with its Italian translation, and the Italian turn must form a new
      // block whose original is Italian and translation is English. The header
      // language labels must not collapse both turns to the target language.
      final textGateway = _FakeTextInterpreterGateway();
      // English -> Italian is the direct OpenAI text fallback turn.
      textGateway.results.add(
        const TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
          translatedText: 'Buongiorno a tutti.',
        ),
      );
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        textInterpreterGateway: textGateway,
      );
      final startedAt = DateTime.utc(2026, 6, 1, 3, 10);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Live Italian block split',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );

      const englishParagraph =
          "Well, you've been on this trip for a full month, haven't you? "
          "Yes, a million hunters, a bit exaggerated, maybe. And now we've "
          "been here five months; that means we're in Australia. Good "
          'morning, how are you?';
      // English turn: input transcript (source) and a target-language output
      // transcript stream together. The dedicated endpoint sends no item_id
      // and no language field on either side.
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: englishParagraph,
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: englishParagraph,
          ),
        );
      await _drainAsync();

      // After only English is heard, the header must say it heard English.
      expect(
        harness.coordinator.interpreterRouteLabel,
        'Heard English. Waiting for the other language...',
      );

      // The Italian turn arrives next, again with no item_id and no language
      // metadata. The Italian source transcript leads and its English
      // translation streams alongside, matching OpenAI's documented event
      // flow where input_transcript updates as audio arrives.
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Buongiorno, come stai?',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Good morning, how are you?',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Buongiorno, come stai?',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Good morning, how are you?',
          ),
        );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(2));

      // Block 1: English original, Italian translation (direct fallback).
      expect(entries.first.languageCode, 'EN');
      expect(entries.first.originalText, englishParagraph);
      expect(entries.first.translatedText, 'Buongiorno a tutti.');
      expect(entries.first.originalText, isNotEmpty);

      // Block 2: Italian original, English translation.
      expect(entries.last.languageCode, 'IT');
      expect(entries.last.originalText, 'Buongiorno, come stai?');
      expect(entries.last.translatedText, 'Good morning, how are you?');

      // No completed/final row may remain with empty original speech once the
      // source transcript text is available.
      for (final entry in entries) {
        expect(entry.originalText, isNotEmpty);
      }

      // The header locks the pair as Italian/English (not target-only EN).
      expect(harness.coordinator.interpreterRouteLabel, 'English <-> Italian');

      // The English turn used the direct OpenAI text fallback (English ->
      // Italian) keyed off the locally detected source language.
      expect(textGateway.requests, hasLength(1));
      expect(textGateway.requests.single.sourceLanguageCode, 'en');
      expect(textGateway.requests.single.targetLanguageCode, 'it');
      expect(
        textGateway.requests.single.routeType,
        TranslationRouteType.directOpenAiFallback,
      );
    },
  );

  test(
    'bidirectional reverse session opens an audio-only B-to-A translation',
    () async {
      // English source turns are silent on the primary (English-output)
      // session, so the reverse direction's TEXT comes from the text path.
      final textGateway = _FakeTextInterpreterGateway()
        ..results.add(
          const TextInterpreterTurnResult(
            detectedLanguageCode: 'it',
            detectedLanguageLabel: 'Italian',
            translatedText: 'Ciao, cosa stai facendo?',
          ),
        );
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        textInterpreterGateway: textGateway,
        enableBidirectionalReverseSession: true,
      );
      final startedAt = DateTime.utc(2026, 6, 1, 5);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Bidirectional reverse',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );

      // Italian turn (detected locally from markers) establishes one language.
      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.input_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.source,
          transcript: 'Buongiorno, come stai?',
        ),
      );
      await _drainAsync();
      expect(harness.realtimeGateway.connectCount, 1);

      // English turn locks the pair and arms the reverse session.
      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.input_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.source,
          transcript: 'Hello, what are you going to do?',
        ),
      );
      await _drainAsync();

      // A second dedicated translation session opens for the reverse direction
      // (output = Italian), audio-only.
      expect(harness.realtimeGateway.connectCount, 2);
      final reverseConfig = harness.realtimeGateway.configs[1];
      expect(reverseConfig.targetLanguageCode, 'it');
      expect(reverseConfig.sourceLanguageCode, 'en');
      expect(reverseConfig.sourceTranscriptionEnabled, isFalse);
      expect(harness.coordinator.interpreterRouteLabel, 'Italian <-> English');

      // Reverse session translated audio plays through the shared queue.
      harness.realtimeGateway.sessions[1].addEvent(
        OpenAiRealtimeAudioDelta(
          type: 'session.output_audio.delta',
          base64Audio: base64Encode(const [9, 8, 7, 6]),
        ),
      );
      await _drainAsync();
      expect(harness.playbackGateway.enqueuedChunks, isNotEmpty);
    },
  );

  test(
    'manual source and target prelock route and start reverse audio session',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        enableBidirectionalReverseSession: true,
      );
      final startedAt = DateTime.utc(2026, 6, 2, 12);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Manual pair',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Italian (IT)',
          targetLanguageLabel: 'English (US)',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      final result = await harness.coordinator.start(
        config: const OpenAiRealtimeTranslationConfig(
          sourceLanguageCode: 'it',
          targetLanguageCode: 'en',
        ),
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'it',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      await _drainAsync();

      expect(result, LiveRealtimeStartResult.started);
      expect(harness.coordinator.interpreterRouteLabel, 'Italian <-> English');
      expect(harness.realtimeGateway.connectCount, 2);
      expect(harness.realtimeGateway.configs.first.sourceLanguageCode, 'it');
      expect(harness.realtimeGateway.configs.first.targetLanguageCode, 'en');
      final reverseConfig = harness.realtimeGateway.configs.last;
      expect(reverseConfig.sourceLanguageCode, 'en');
      expect(reverseConfig.targetLanguageCode, 'it');
      expect(reverseConfig.sourceTranscriptionEnabled, isFalse);
    },
  );

  group('realtime source-signal evidence', () {
    test(
      'translation-only completion with no source raises a privacy-safe '
      'translation_without_source signal',
      () async {
        // Reproduces Tom's installed-app symptom at the coordinator/diagnostic
        // boundary: the dedicated wire delivered only translated output for a
        // turn and never any source/original transcript. The runtime must
        // surface this as a content-free signal (so a release check can catch
        // it) instead of silently presenting a completed, sourceless card.
        final diagnosticsSink = MemoryPrivacySafeDiagnosticsSink();
        final harness = await _Harness.create(
          permissionStatus: MicrophonePermissionStatus.granted,
          diagnostics: PrivacySafeDiagnostics(sink: diagnosticsSink),
        );
        final startedAt = DateTime.utc(2026, 6, 1, 4);
        await harness.repository.upsertMeeting(
          StoredMeeting(
            id: 'meeting-1',
            title: 'Sourceless translation',
            createdAt: startedAt,
            updatedAt: startedAt,
            sourceLanguageLabel: 'Auto-detect',
            targetLanguageLabel: 'English',
            transcriptEntries: const [],
            summaryMetadata: const StoredSummaryMetadata.empty(),
          ),
        );
        await harness.coordinator.start(
          config: config,
          transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
            repository: harness.repository,
            meetingId: 'meeting-1',
            sourceLanguageCode: 'auto',
            targetLanguageCode: 'en',
            now: () => startedAt,
          ),
        );

        // Only translated output arrives and completes; no source transcript
        // events are ever delivered for this turn.
        harness.realtimeGateway.session
          ..addEvent(
            const OpenAiRealtimeTranscriptDelta(
              type: 'session.output_transcript.delta',
              kind: OpenAiRealtimeTranscriptKind.translation,
              delta: 'That is good. Okay, yes. What are you doing today?',
            ),
          )
          ..addEvent(
            const OpenAiRealtimeTranscriptCompleted(
              type: 'session.output_transcript.done',
              kind: OpenAiRealtimeTranscriptKind.translation,
              transcript: 'That is good. Okay, yes. What are you doing today?',
            ),
          );
        await _drainAsync();

        final snapshot = harness.coordinator.transcriptSignalSnapshot;
        expect(snapshot.hasOutputSignal, isTrue);
        expect(snapshot.hasSourceSignal, isFalse);
        expect(snapshot.translationArrivedWithoutSource, isTrue);
        expect(snapshot.sourcelessFinalCount, greaterThanOrEqualTo(1));

        final signalRecords = diagnosticsSink.records
            .where(
              (record) =>
                  record.event == 'live_realtime.translation_without_source',
            )
            .toList();
        expect(signalRecords, isNotEmpty);
        final record = signalRecords.first;
        expect(record.severity, DiagnosticSeverity.warning);
        expect(record.fields['signalState'], 'translation_without_source');
        expect(record.fields['hasSourceSignal'], 'false');
        expect(record.fields['hasOutputSignal'], 'true');
        // The diagnostic must never carry transcript/translation content.
        for (final value in record.fields.values) {
          expect(value, isNot(contains('What are you doing today')));
        }
      },
    );

    test(
      'later source turn updates the signal snapshot and detects the second '
      'language without losing original text',
      () async {
        // A first English turn arrives with its source transcript, then a
        // later Italian source turn arrives. The runtime must record BOTH
        // source signals, detect the second language for the header, and keep
        // original text on both cards (no permanent "Original speech pending").
        final harness = await _Harness.create(
          permissionStatus: MicrophonePermissionStatus.granted,
        );
        final startedAt = DateTime.utc(2026, 6, 1, 5);
        await harness.repository.upsertMeeting(
          StoredMeeting(
            id: 'meeting-1',
            title: 'Second language from source',
            createdAt: startedAt,
            updatedAt: startedAt,
            sourceLanguageLabel: 'Auto-detect',
            targetLanguageLabel: 'English',
            transcriptEntries: const [],
            summaryMetadata: const StoredSummaryMetadata.empty(),
          ),
        );
        await harness.coordinator.start(
          config: config,
          transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
            repository: harness.repository,
            meetingId: 'meeting-1',
            sourceLanguageCode: 'auto',
            targetLanguageCode: 'en',
            now: () => startedAt,
          ),
        );

        harness.realtimeGateway.session.addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Hello everyone, welcome to the meeting.',
          ),
        );
        await _drainAsync();

        expect(
          harness.coordinator.interpreterRouteLabel,
          'Heard English. Waiting for the other language...',
        );

        harness.realtimeGateway.session.addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Buongiorno a tutti, benvenuti alla riunione.',
          ),
        );
        await _drainAsync();

        final snapshot = harness.coordinator.transcriptSignalSnapshot;
        expect(snapshot.sourceTurnCount, greaterThanOrEqualTo(2));
        expect(snapshot.translationArrivedWithoutSource, isFalse);
        expect(snapshot.sourcelessFinalCount, 0);

        // The second distinct language locks the bidirectional header.
        expect(
          harness.coordinator.interpreterRouteLabel,
          'English <-> Italian',
        );

        final entries = (await harness.repository.loadSnapshot())
            .meetings
            .single
            .transcriptEntries;
        expect(entries, hasLength(2));
        for (final entry in entries) {
          expect(entry.originalText, isNotEmpty);
        }
        expect(entries.first.languageCode, 'EN');
        expect(entries.last.languageCode, 'IT');
      },
    );

    test(
      'first source-backed turn then a later sourceless final exposes a '
      'release-checkable failure state',
      () async {
        // Architect blocker repro (PR #51): Tom's actual round-3 shape is a
        // FIRST card that has source + translation, then LATER cards that lose
        // the original while still translating. Once any source has arrived,
        // `hasSourceSignal` is permanently true, so a flag defined only as
        // `hasOutputSignal && !hasSourceSignal` can never catch this. The
        // snapshot must expose a failure state derived from
        // `sourcelessFinalCount > 0` so a release/smoke check can detect "first
        // source works, later source missing".
        final diagnosticsSink = MemoryPrivacySafeDiagnosticsSink();
        final harness = await _Harness.create(
          permissionStatus: MicrophonePermissionStatus.granted,
          diagnostics: PrivacySafeDiagnostics(sink: diagnosticsSink),
        );
        final startedAt = DateTime.utc(2026, 6, 1, 6);
        await harness.repository.upsertMeeting(
          StoredMeeting(
            id: 'meeting-1',
            title: 'First source then sourceless final',
            createdAt: startedAt,
            updatedAt: startedAt,
            sourceLanguageLabel: 'Auto-detect',
            targetLanguageLabel: 'English',
            transcriptEntries: const [],
            summaryMetadata: const StoredSummaryMetadata.empty(),
          ),
        );
        await harness.coordinator.start(
          config: config,
          transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
            repository: harness.repository,
            meetingId: 'meeting-1',
            sourceLanguageCode: 'auto',
            targetLanguageCode: 'en',
            now: () => startedAt,
          ),
        );

        // First turn arrives complete with both source and translation.
        harness.realtimeGateway.session
          ..addEvent(
            const OpenAiRealtimeTranscriptCompleted(
              type: 'session.input_transcript.done',
              kind: OpenAiRealtimeTranscriptKind.source,
              itemId: 'turn-1',
              transcript: 'Hello everyone, welcome to the meeting.',
            ),
          )
          ..addEvent(
            const OpenAiRealtimeTranscriptCompleted(
              type: 'session.output_transcript.done',
              kind: OpenAiRealtimeTranscriptKind.translation,
              itemId: 'turn-1',
              transcript: 'Ciao a tutti, benvenuti alla riunione.',
            ),
          );
        await _drainAsync();

        // After the first good turn, the all-output/no-source flag is false
        // because a source signal has now arrived.
        final afterFirstTurn = harness.coordinator.transcriptSignalSnapshot;
        expect(afterFirstTurn.hasSourceSignal, isTrue);
        expect(afterFirstTurn.sourcelessFinalCount, 0);
        expect(afterFirstTurn.hasSourcelessFinal, isFalse);
        expect(afterFirstTurn.translationArrivedWithoutSource, isFalse);

        // A LATER turn delivers only translated output and finalizes with no
        // source transcript for that turn.
        harness.realtimeGateway.session.addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            itemId: 'turn-2',
            transcript: 'That is good. Okay, yes.',
          ),
        );
        await _drainAsync();

        final snapshot = harness.coordinator.transcriptSignalSnapshot;
        // The release-checkable failure state trips on the later sourceless
        // final even though an earlier turn had source.
        expect(snapshot.sourcelessFinalCount, greaterThanOrEqualTo(1));
        expect(snapshot.hasSourcelessFinal, isTrue);
        expect(snapshot.translationArrivedWithoutSource, isTrue);
        // The earlier source signal is still recorded; we do not pretend it
        // never arrived.
        expect(snapshot.hasSourceSignal, isTrue);

        final signalRecords = diagnosticsSink.records
            .where(
              (record) =>
                  record.event == 'live_realtime.translation_without_source',
            )
            .toList();
        expect(signalRecords, isNotEmpty);
        final record = signalRecords.last;
        expect(record.severity, DiagnosticSeverity.warning);
        expect(record.fields['signalState'], 'translation_without_source');
        // Even though an earlier source arrived, the diagnostic reports the
        // sourceless-final count so the failure is detectable.
        expect(record.fields['hasSourceSignal'], 'true');
        expect(record.fields['sourcelessFinalCount'], '1');
        for (final value in record.fields.values) {
          expect(value, isNot(contains('That is good')));
          expect(value, isNot(contains('benvenuti')));
        }
      },
    );
  });

  test(
    'English Italian fallback runs after realtime translated text arrives first',
    () async {
      final textGateway = _FakeTextInterpreterGateway();
      textGateway.results.add(
        const TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
          translatedText: 'Possiamo confermare il piano.',
        ),
      );
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        textInterpreterGateway: textGateway,
      );
      final startedAt = DateTime.utc(2026, 5, 31, 1);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Fallback first order',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            itemId: 'source-en-1',
            transcript: 'We can confirm the plan.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'source-en-1',
            languageCode: 'en',
            transcript: 'We can confirm the plan.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'source-it-1',
            languageCode: 'it',
            transcript: 'Possiamo iniziare.',
          ),
        );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(2));
      expect(entries.first.languageCode, 'EN');
      expect(entries.first.originalText, 'We can confirm the plan.');
      expect(entries.first.translatedText, 'Possiamo confermare il piano.');
      expect(entries.last.languageCode, 'IT');
      expect(entries.last.originalText, 'Possiamo iniziare.');
      expect(textGateway.requests, hasLength(1));
      expect(textGateway.requests.single.sourceLanguageCode, 'en');
      expect(textGateway.requests.single.targetLanguageCode, 'it');
      expect(
        textGateway.requests.single.routeType,
        TranslationRouteType.directOpenAiFallback,
      );
    },
  );

  test(
    'English Italian fallback remains authoritative over later realtime output',
    () async {
      final textGateway = _FakeTextInterpreterGateway();
      textGateway.results.add(
        const TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
          translatedText: 'Possiamo confermare il piano.',
        ),
      );
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        textInterpreterGateway: textGateway,
      );
      final startedAt = DateTime.utc(2026, 5, 31, 1, 15);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Fallback overwrite order',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'source-en-1',
            languageCode: 'en',
            transcript: 'We can confirm the plan.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'source-it-1',
            languageCode: 'it',
            transcript: 'Possiamo iniziare.',
          ),
        );
      await _drainAsync();

      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.output_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.translation,
          itemId: 'source-en-1',
          transcript: 'We can confirm the plan.',
        ),
      );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(2));
      expect(entries.first.languageCode, 'EN');
      expect(entries.first.originalText, 'We can confirm the plan.');
      expect(entries.first.translatedText, 'Possiamo confermare il piano.');
      expect(entries.last.languageCode, 'IT');
      expect(entries.last.originalText, 'Possiamo iniziare.');
      expect(entries.last.translatedText, isEmpty);
      expect(textGateway.requests, hasLength(1));
      expect(
        textGateway.requests.single.routeType,
        TranslationRouteType.directOpenAiFallback,
      );
    },
  );

  test(
    'Italian realtime translation before source survives after English fallback',
    () async {
      final textGateway = _FakeTextInterpreterGateway();
      textGateway.results.add(
        const TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
          translatedText: 'Possiamo confermare il piano.',
        ),
      );
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        textInterpreterGateway: textGateway,
      );
      final startedAt = DateTime.utc(2026, 5, 31, 1, 30);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Realtime after fallback',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'source-it-1',
            languageCode: 'it',
            transcript: 'Possiamo iniziare.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            itemId: 'source-en-1',
            languageCode: 'en',
            transcript: 'We can confirm the plan.',
          ),
        );
      await _drainAsync();

      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.output_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.translation,
          itemId: 'source-it-2',
          transcript: 'We can begin.',
        ),
      );
      await _drainAsync();

      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.input_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.source,
          itemId: 'source-it-2',
          languageCode: 'it',
          transcript: 'Possiamo cominciare.',
        ),
      );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(3));
      expect(entries[0].languageCode, 'IT');
      expect(entries[0].originalText, 'Possiamo iniziare.');
      expect(entries[1].languageCode, 'EN');
      expect(entries[1].originalText, 'We can confirm the plan.');
      expect(entries[1].translatedText, 'Possiamo confermare il piano.');
      expect(entries[2].languageCode, 'IT');
      expect(entries[2].originalText, 'Possiamo cominciare.');
      expect(entries[2].translatedText, 'We can begin.');
      expect(entries[2].status, 'final');
      expect(textGateway.requests, hasLength(1));
      expect(
        textGateway.requests.single.routeType,
        TranslationRouteType.directOpenAiFallback,
      );
    },
  );

  test(
    'translation-first final stays partial until original speech backfills',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 28, 3, 15);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Backfill smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.output_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.translation,
          transcript: 'Hello.',
        ),
      );
      await _drainAsync();

      var entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, isEmpty);
      expect(entries.single.translatedText, 'Hello.');
      expect(entries.single.status, 'partial');

      // While the source has not yet backfilled, the translation-only
      // completion provisionally trips the sourceless-final signal.
      final beforeBackfill = harness.coordinator.transcriptSignalSnapshot;
      expect(beforeBackfill.sourcelessFinalCount, 1);
      expect(beforeBackfill.hasSourcelessFinal, isTrue);
      expect(beforeBackfill.translationArrivedWithoutSource, isTrue);

      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.input_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.source,
          itemId: 'source-it-1',
          languageCode: 'it',
          transcript: 'Ciao.',
        ),
      );
      await _drainAsync();

      entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.languageCode, 'IT');
      expect(entries.single.originalText, 'Ciao.');
      expect(entries.single.translatedText, 'Hello.');
      expect(entries.single.status, 'final');

      // After the valid backfill the same row is a complete turn, so the
      // release-checkable signal must NOT report Tom's failure mode (architect
      // blocker: the diagnostic was previously left tripped here).
      final afterBackfill = harness.coordinator.transcriptSignalSnapshot;
      expect(afterBackfill.sourcelessFinalCount, 0);
      expect(afterBackfill.hasSourcelessFinal, isFalse);
      expect(afterBackfill.translationArrivedWithoutSource, isFalse);
      expect(afterBackfill.hasSourceSignal, isTrue);
    },
  );

  test(
    'repeated translation-only completion before source backfill is counted '
    'once and fully cleared',
    () async {
      // Round-2 architect follow-up: a still-partial row can receive more than
      // one output `.done` (a refinement/re-emission) before its source
      // arrives. Each must count the row toward sourcelessFinalCount AT MOST
      // ONCE, otherwise a single source backfill could not zero the count and
      // the release-checkable signal would stay falsely tripped on a valid
      // turn.
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 6, 1, 7);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Repeated translation-only then backfill',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );

      // The same turn's translation finalizes twice (a refinement) before any
      // source transcript arrives. No item ids on this wire, so both land on
      // the same still-partial row.
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Hello.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Hello there.',
          ),
        );
      await _drainAsync();

      var entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, isEmpty);
      // Two output completions on one row must count the row only once.
      final beforeBackfill = harness.coordinator.transcriptSignalSnapshot;
      expect(beforeBackfill.sourcelessFinalCount, 1);
      expect(beforeBackfill.hasSourcelessFinal, isTrue);
      expect(beforeBackfill.translationArrivedWithoutSource, isTrue);

      // Source backfills into the same row: a single reversal must fully clear
      // the count.
      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.input_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.source,
          itemId: 'source-it-1',
          languageCode: 'it',
          transcript: 'Ciao.',
        ),
      );
      await _drainAsync();

      entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Ciao.');
      expect(entries.single.status, 'final');

      final afterBackfill = harness.coordinator.transcriptSignalSnapshot;
      expect(afterBackfill.sourcelessFinalCount, 0);
      expect(afterBackfill.hasSourcelessFinal, isFalse);
      expect(afterBackfill.translationArrivedWithoutSource, isFalse);
      expect(afterBackfill.hasSourceSignal, isTrue);
    },
  );

  test(
    'output transcript without any source never finalizes a sourceless row',
    () async {
      // Safety net for the exact failure mode Tom hit on the installed app: if
      // the dedicated translation endpoint streams only translated
      // (`session.output_transcript`) deltas and never any source
      // (`session.input_transcript`) events, the app must not present a
      // completed/"final" row with empty original speech. The row stays
      // non-final (partial), and on session end it is marked partial/interrupted
      // rather than final, so the UI never claims a finished turn whose original
      // is missing. With the session-config fix the endpoint now emits source
      // events; this guards against any future config/endpoint regression that
      // silently drops them.
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 6, 1, 4);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Output-only safety',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      // Two full translated turns arrive, each completed, but no source ever
      // does. This is what the broken (pre-fix) session config produced.
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Good morning everyone.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Good morning everyone.',
          ),
        );
      await _drainAsync();

      var entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, isEmpty);
      expect(entries.single.translatedText, 'Good morning everyone.');
      // Critically NOT final: a completed translation with no original speech
      // must not be presented as a finished turn.
      expect(entries.single.status, isNot('final'));
      expect(entries.single.status, 'partial');

      // Ending the session must not promote the sourceless row to final.
      await harness.coordinator.stop();
      await _drainAsync();

      entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, isEmpty);
      expect(entries.single.status, isNot('final'));
    },
  );

  test('pause and resume listening preserves transcript state', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
    );
    final startedAt = DateTime.utc(2026, 5, 28, 3, 30);
    await harness.repository.upsertMeeting(
      StoredMeeting(
        id: 'meeting-1',
        title: 'Pause smoke',
        createdAt: startedAt,
        updatedAt: startedAt,
        sourceLanguageLabel: 'Auto-detect',
        targetLanguageLabel: 'English',
        transcriptEntries: const [],
        summaryMetadata: const StoredSummaryMetadata.empty(),
      ),
    );

    await harness.coordinator.start(
      config: config,
      transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
        repository: harness.repository,
        meetingId: 'meeting-1',
        sourceLanguageCode: 'auto',
        targetLanguageCode: 'en',
        now: () => startedAt,
      ),
    );
    harness.realtimeGateway.session.addEvent(
      const OpenAiRealtimeTranscriptCompleted(
        type: 'session.input_transcript.done',
        kind: OpenAiRealtimeTranscriptKind.source,
        languageCode: 'en',
        transcript: 'Hello.',
      ),
    );
    await _drainAsync();

    await harness.coordinator.pauseListening();
    expect(harness.controller.state.phase, LiveSessionPhase.listeningPaused);
    expect(harness.captureGateway.isCapturing, isFalse);
    expect(harness.playbackGateway.isOpen, isFalse);

    final result = await harness.coordinator.resumeListening();
    expect(result, LiveRealtimeStartResult.started);
    expect(harness.controller.state.phase, LiveSessionPhase.listening);
    expect(harness.realtimeGateway.connectCount, 2);
    expect(
      (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries
          .single
          .originalText,
      'Hello.',
    );
  });

  test('pause during realtime startup prevents late listening state', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
    );
    harness.realtimeGateway.delayNextConnect = true;

    final startFuture = harness.coordinator.start(config: config);
    await _drainAsync();

    expect(harness.controller.state.phase, LiveSessionPhase.connecting);

    await harness.coordinator.pauseListening();
    expect(harness.controller.state.phase, LiveSessionPhase.listeningPaused);
    expect(harness.captureGateway.isCapturing, isFalse);
    expect(harness.playbackGateway.isOpen, isFalse);

    harness.realtimeGateway.completeDelayedConnect();
    expect(await startFuture, LiveRealtimeStartResult.failed);
    expect(harness.controller.state.phase, LiveSessionPhase.listeningPaused);
    expect(harness.captureGateway.isCapturing, isFalse);
    expect(harness.playbackGateway.isOpen, isFalse);
    expect(harness.realtimeGateway.session.closeImmediatelyCount, 1);
  });

  test('stop closes capture, realtime, and controller resources', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
    );

    await harness.coordinator.start(config: config);
    await harness.coordinator.stop();

    expect(harness.captureGateway.stopCount, greaterThanOrEqualTo(1));
    expect(harness.captureGateway.isCapturing, isFalse);
    expect(harness.playbackGateway.stopCount, greaterThanOrEqualTo(1));
    expect(harness.playbackGateway.isOpen, isFalse);
    expect(harness.realtimeGateway.session.closeGracefullyCount, 1);
    expect(harness.controller.state.phase, LiveSessionPhase.localSetup);
    expect(harness.controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(harness.controller.state.isRealtimeSessionOpen, isFalse);
  });

  test(
    'graceful stop commits final transcript events before finishing',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 27, 3);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Graceful close transcript',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.input_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.source,
          delta: 'Hol',
        ),
      );
      await _drainAsync();

      harness.realtimeGateway.session.eventsOnGracefulClose.addAll(const [
        OpenAiRealtimeTranscriptCompleted(
          type: 'session.input_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.source,
          transcript: 'Hola final',
        ),
        OpenAiRealtimeTranscriptCompleted(
          type: 'session.output_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.translation,
          transcript: 'Hello final.',
        ),
        OpenAiRealtimeSessionClosed(type: 'session.closed'),
      ]);

      await harness.coordinator.stop();
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Hola final');
      expect(entries.single.translatedText, 'Hello final.');
      expect(entries.single.status, 'final');
      expect(harness.realtimeGateway.session.closeGracefullyCount, 1);
      expect(harness.controller.state.phase, LiveSessionPhase.localSetup);
    },
  );

  test(
    'discard closes live resources without finalizing partial transcript',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 10);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Discard active meeting',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.input_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.source,
          delta: 'Hola',
        ),
      );
      await _drainAsync();

      await harness.coordinator.discardActiveSession();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.status, 'partial');
      expect(harness.captureGateway.isCapturing, isFalse);
      expect(harness.playbackGateway.isOpen, isFalse);
      expect(harness.realtimeGateway.session.closeImmediatelyCount, 1);
      expect(harness.realtimeGateway.session.closeGracefullyCount, 0);
      expect(harness.controller.state.phase, LiveSessionPhase.localSetup);
    },
  );

  test('realtime failure closes capture while reconnecting', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
      reconnectDelay: (_) => Future<void>.delayed(const Duration(days: 1)),
    );

    await harness.coordinator.start(config: config);
    harness.realtimeGateway.session.addEvent(
      const OpenAiRealtimeSessionClosed(type: 'socket.closed'),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.state.phase, LiveSessionPhase.reconnecting);
    expect(harness.controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(harness.controller.state.isRealtimeSessionOpen, isFalse);
    expect(harness.captureGateway.isCapturing, isFalse);
    expect(harness.captureGateway.stopCount, greaterThanOrEqualTo(1));
    expect(harness.playbackGateway.isOpen, isFalse);
    expect(harness.playbackGateway.stopCount, greaterThanOrEqualTo(1));
  });

  test(
    'credential rejection from realtime event closes live resources',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );

      await harness.coordinator.start(config: config);
      harness.realtimeGateway.session.addEvent(
        const OpenAiRealtimeError(
          type: 'error',
          code: 'invalid_api_key',
          eventId: null,
          param: null,
        ),
      );
      await _drainAsync();

      expect(
        harness.controller.state.phase,
        LiveSessionPhase.credentialInvalid,
      );
      expect(
        harness.controller.state.realtimeFailureKind,
        OpenAiRealtimeFailureKind.credentialRejected,
      );
      expect(harness.controller.state.isMicrophoneCaptureOpen, isFalse);
      expect(harness.controller.state.isRealtimeSessionOpen, isFalse);
      expect(harness.controller.state.isPlaybackQueueOpen, isFalse);
      expect(harness.captureGateway.isCapturing, isFalse);
      expect(harness.playbackGateway.isOpen, isFalse);
      expect(harness.realtimeGateway.session.closeImmediatelyCount, 1);
    },
  );

  test(
    'retryable realtime failure reconnects without duplicating transcript row',
    () async {
      final reconnectDelays = <Duration>[];
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        reconnectDelay: (delay) async {
          reconnectDelays.add(delay);
        },
      );
      final startedAt = DateTime.utc(2026, 5, 24, 5);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Reconnect smoke',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hola',
          ),
        )
        ..addEvent(const OpenAiRealtimeSessionClosed(type: 'socket.closed'));
      await _drainAsync();

      expect(reconnectDelays, hasLength(1));
      expect(harness.realtimeGateway.connectCount, 2);
      expect(harness.captureGateway.startCount, 2);
      expect(harness.playbackGateway.startCount, 2);
      expect(harness.playbackGateway.stopCount, greaterThanOrEqualTo(1));
      expect(harness.controller.state.phase, LiveSessionPhase.listening);
      expect(harness.controller.state.realtimeRetryAttempt, 0);

      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Hello',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Hello.',
          ),
        );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Hola');
      expect(entries.single.translatedText, 'Hello.');
      expect(entries.single.status, 'final');
    },
  );

  test(
    'generated-speech-style reconnect keeps one committed transcript row',
    () async {
      final reconnectDelays = <Duration>[];
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        reconnectDelay: (delay) async {
          reconnectDelays.add(delay);
        },
      );
      final startedAt = DateTime.utc(2026, 5, 24, 7);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Generated speech reconnect',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'en',
          profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
        ),
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Buenos ',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'dias',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Buenos dias',
          ),
        )
        ..addEvent(
          OpenAiRealtimeAudioDelta(
            type: 'session.output_audio.delta',
            base64Audio: base64Encode([1, 2, 3, 4]),
          ),
        )
        ..addEvent(const OpenAiRealtimeSessionClosed(type: 'socket.closed'));
      await _drainAsync();

      expect(reconnectDelays, hasLength(1));
      expect(harness.realtimeGateway.connectCount, 2);
      expect(harness.captureGateway.startCount, 2);
      expect(harness.playbackGateway.startCount, 2);
      expect(harness.playbackGateway.stopCount, greaterThanOrEqualTo(1));
      expect(harness.playbackGateway.enqueuedChunks, isEmpty);

      harness.realtimeGateway.session
        ..addEvent(
          OpenAiRealtimeAudioDelta(
            type: 'session.output_audio.delta',
            base64Audio: base64Encode([5, 6, 7, 8]),
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Good ',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'morning',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Good morning.',
          ),
        );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(harness.controller.state.phase, LiveSessionPhase.listening);
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Buenos dias');
      expect(entries.single.translatedText, 'Good morning.');
      expect(entries.single.status, 'final');
      expect(harness.playbackGateway.enqueuedChunks, hasLength(1));
      expect(harness.playbackGateway.enqueuedChunks.single.bytes, [5, 6, 7, 8]);
    },
  );

  test(
    'duplicate completed transcript events after reconnect do not create rows',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 9);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Duplicate completion',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Hola equipo.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Hello team.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Hello team.',
          ),
        )
        ..addEvent(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Hola equipo.',
          ),
        );
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Hola equipo.');
      expect(entries.single.translatedText, 'Hello team.');
      expect(entries.single.status, 'final');
    },
  );

  test(
    'debug generated-speech proof writes one realtime row and recovered audio',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
      );
      final startedAt = DateTime.utc(2026, 5, 24, 8);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Debug proof',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'en',
          profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
        ),
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );

      final result = await harness.coordinator
          .debugInjectGeneratedSpeechStyleReconnectProof();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(result.transcriptEventCount, 5);
      expect(result.playbackChunkCount, 1);
      expect(result.simulatedReconnectCount, 1);
      expect(entries, hasLength(1));
      expect(entries.single.id, contains('-realtime-'));
      expect(entries.single.originalText, 'Generated speech');
      expect(entries.single.translatedText, 'Generated translation.');
      expect(entries.single.status, 'final');
      expect(harness.playbackGateway.enqueuedChunks, hasLength(1));
      expect(harness.playbackGateway.enqueuedChunks.single.bytes, [5, 6, 7, 8]);
      expect(harness.playbackGateway.stopCount, greaterThanOrEqualTo(1));
    },
  );

  test(
    'failed reconnect exhausts policy and marks partial transcript interrupted',
    () async {
      final harness = await _Harness.create(
        permissionStatus: MicrophonePermissionStatus.granted,
        reconnectPolicy: const OpenAiRealtimeReconnectPolicy(maxAttempts: 1),
        reconnectDelay: (_) async {},
      );
      final startedAt = DateTime.utc(2026, 5, 24, 6);
      await harness.repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Reconnect exhausted',
          createdAt: startedAt,
          updatedAt: startedAt,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      await harness.coordinator.start(
        config: config,
        transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
          repository: harness.repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: 'auto',
          targetLanguageCode: 'en',
          now: () => startedAt,
        ),
      );
      harness.realtimeGateway.failNextConnect = true;
      harness.realtimeGateway.session
        ..addEvent(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hola',
          ),
        )
        ..addEvent(const OpenAiRealtimeSessionClosed(type: 'socket.closed'));
      await _drainAsync();

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(harness.realtimeGateway.connectCount, 2);
      expect(harness.controller.state.phase, LiveSessionPhase.offline);
      expect(harness.playbackGateway.isOpen, isFalse);
      expect(entries, hasLength(1));
      expect(entries.single.originalText, 'Hola');
      expect(entries.single.status, 'interrupted');
    },
  );

  test('background lifecycle closes capture and realtime resources', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
    );

    await harness.coordinator.start(config: config);
    harness.coordinator.handleAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.state.phase, LiveSessionPhase.listeningPaused);
    expect(harness.controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(harness.captureGateway.isCapturing, isFalse);
    expect(harness.playbackGateway.isOpen, isFalse);
    expect(harness.realtimeGateway.session.closeImmediatelyCount, 1);
  });

  test('foreground resume schedules lifecycle reconnect', () async {
    final reconnectDelays = <Duration>[];
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
      reconnectDelay: (delay) async {
        reconnectDelays.add(delay);
      },
    );

    await harness.coordinator.start(config: config);
    harness.coordinator.handleAppLifecycleState(AppLifecycleState.paused);
    await _drainAsync();
    harness.coordinator.handleAppLifecycleState(AppLifecycleState.resumed);
    await _drainAsync();

    expect(reconnectDelays, [Duration.zero]);
    expect(harness.realtimeGateway.connectCount, 2);
    expect(harness.captureGateway.startCount, 2);
    expect(harness.playbackGateway.startCount, 2);
    expect(harness.controller.state.phase, LiveSessionPhase.listening);
  });

  group('LiveRealtimeTranscriptCommitter language resolution', () {
    Future<LiveRealtimeTranscriptCommitter> committerFor(
      LocalMeetingRepository repository, {
      String sourceLanguageCode = 'auto',
      String targetLanguageCode = 'en',
    }) async {
      final now = DateTime.utc(2026, 6, 1, 2);
      await repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Committer unit',
          createdAt: now,
          updatedAt: now,
          sourceLanguageLabel: 'Auto-detect',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );
      return LiveRealtimeTranscriptCommitter(
        LiveRealtimeTranscriptCommitTarget(
          repository: repository,
          meetingId: 'meeting-1',
          sourceLanguageCode: sourceLanguageCode,
          targetLanguageCode: targetLanguageCode,
          now: () => now,
        ),
      );
    }

    test('unknown source language stays neutral, never the target', () async {
      final repository = LocalMeetingRepository(
        store: MemoryEncryptedLocalStore(),
      );
      final committer = await committerFor(repository);
      // A short, language-ambiguous source with a target-language translation
      // must not be mislabeled as the target language.
      await committer.commitCompleted(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.input_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.source,
          transcript: 'OK 42.',
        ),
      );
      await committer.commitCompleted(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.output_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.translation,
          transcript: 'OK 42.',
        ),
      );

      final entry = (await repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries
          .single;
      expect(entry.languageCode, 'auto');
      expect(entry.languageCode, isNot('EN'));
    });

    test(
      'manual source language is the fallback for ambiguous source text',
      () async {
        final repository = LocalMeetingRepository(
          store: MemoryEncryptedLocalStore(),
        );
        final committer = await committerFor(
          repository,
          sourceLanguageCode: 'it',
          targetLanguageCode: 'en',
        );
        await committer.commitCompleted(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'OK 42.',
          ),
        );

        final entry = (await repository.loadSnapshot())
            .meetings
            .single
            .transcriptEntries
            .single;
        expect(entry.languageCode, 'IT');
      },
    );

    test(
      'single distinctive Italian marker resolves to IT for short phrases',
      () async {
        final repository = LocalMeetingRepository(
          store: MemoryEncryptedLocalStore(),
        );
        final committer = await committerFor(repository);
        await committer.commitCompleted(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Buongiorno.',
          ),
        );

        final entry = (await repository.loadSnapshot())
            .meetings
            .single
            .transcriptEntries
            .single;
        expect(entry.languageCode, 'IT');
      },
    );

    test(
      'mixed English Italian English source deltas split into language cards',
      () async {
        final repository = LocalMeetingRepository(
          store: MemoryEncryptedLocalStore(),
        );
        final committer = await committerFor(repository);

        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hello. How are you? What are you up to? ',
          ),
        );
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Mi piace il calcio. Calcio e buono. ',
          ),
        );
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'I like soccer. Soccer is good.',
          ),
        );
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta:
                "Yeah, okay, so let's just continue on with the meeting then.",
          ),
        );
        await committer.commitCompleted(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript:
                "Hello. How are you? What are you up to? Mi piace il calcio. "
                "Calcio e buono. Yeah, okay, so let's just continue on with "
                'the meeting then.',
          ),
        );

        final entries = (await repository.loadSnapshot())
            .meetings
            .single
            .transcriptEntries;

        expect(entries, hasLength(3));
        expect(entries[0].languageCode, 'EN');
        expect(entries[0].originalText, 'Hello. How are you? What are you up to?');
        expect(entries[1].languageCode, 'IT');
        expect(
          entries[1].originalText,
          'Mi piace il calcio. Calcio e buono.',
        );
        expect(entries[1].translatedText, 'I like soccer. Soccer is good.');
        expect(entries[2].languageCode, 'EN');
        expect(
          entries[2].originalText,
          "Yeah, okay, so let's just continue on with the meeting then.",
        );
        expect(entries[2].originalText, isNot(contains('Mi piace')));
      },
    );

    test(
      'mixed supported-language source deltas split beyond Italian',
      () async {
        final repository = LocalMeetingRepository(
          store: MemoryEncryptedLocalStore(),
        );
        final committer = await committerFor(repository);

        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hello. How are you? ',
          ),
        );
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hola, gracias por venir. ',
          ),
        );
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta:
                '\u3053\u3093\u306b\u3061\u306f\u3001'
                '\u3042\u308a\u304c\u3068\u3046\u3054\u3056\u3044'
                '\u307e\u3059\u3002 ',
          ),
        );
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Okay, please continue the meeting.',
          ),
        );

        final entries = (await repository.loadSnapshot())
            .meetings
            .single
            .transcriptEntries;

        expect(entries, hasLength(4));
        expect([for (final entry in entries) entry.languageCode], [
          'EN',
          'ES',
          'JA',
          'EN',
        ]);
        expect(entries[1].originalText, 'Hola, gracias por venir.');
        expect(
          entries[2].originalText,
          '\u3053\u3093\u306b\u3061\u306f\u3001'
          '\u3042\u308a\u304c\u3068\u3046\u3054\u3056\u3044'
          '\u307e\u3059\u3002',
        );
      },
    );

    test(
      'English homograph marker does not falsely resolve to a foreign language',
      () async {
        final repository = LocalMeetingRepository(
          store: MemoryEncryptedLocalStore(),
        );
        final committer = await committerFor(repository);
        // "come" is an Italian marker but also a common English word. An
        // English-only phrase that happens to contain it, with no distinctive
        // Italian marker, must not resolve to IT at the relaxed single-marker
        // threshold; it stays neutral.
        await committer.commitCompleted(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Come in.',
          ),
        );

        final entry = (await repository.loadSnapshot())
            .meetings
            .single
            .transcriptEntries
            .single;
        expect(entry.languageCode, 'auto');
        expect(entry.languageCode, isNot('IT'));
      },
    );

    test(
      'continuous source utterance is not fragmented into a sourceless card '
      'by translation-side rolling',
      () async {
        // Reproduces Tom's 2026-06-01 installed-app screenshot against the
        // real /v1/realtime/translations wire shape (no item ids, no language
        // metadata). A single continuous source utterance streams while the
        // translation output streams alongside and crosses a sentence
        // boundary. The previous translation-side readable-block roll split
        // the still-open source utterance: the first card kept the original
        // text, but the continued translation rolled onto a NEW card whose
        // original was empty ("Original speech pending"), exactly the
        // screenshot symptom. The source utterance is the only reliable turn
        // boundary on this wire, so a still-incomplete source utterance must
        // keep its translation on the same card.
        final repository = LocalMeetingRepository(
          store: MemoryEncryptedLocalStore(),
        );
        final committer = await committerFor(repository);

        // Source transcription streams the full utterance first (Whisper
        // source transcription and target translation arrive on independent
        // cadences; neither side has completed yet).
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hello, how are you? That is good. Okay, yes.',
          ),
        );
        // Translation output streams in pieces that individually end on
        // sentence boundaries.
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Hi, how are you?',
          ),
        );
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: ' That is good. Okay, yes.',
          ),
        );

        final entries = (await repository.loadSnapshot())
            .meetings
            .single
            .transcriptEntries;
        // The whole continuous turn stays on ONE card; no sourceless card is
        // created while the source utterance is still open.
        expect(entries, hasLength(1));
        expect(
          entries.single.originalText,
          'Hello, how are you? That is good. Okay, yes.',
        );
        expect(
          entries.single.translatedText,
          'Hi, how are you? That is good. Okay, yes.',
        );
        for (final entry in entries) {
          expect(
            entry.originalText,
            isNotEmpty,
            reason: 'no card may show "Original speech pending" while the '
                'source utterance is still streaming',
          );
        }
      },
    );

    test(
      'source completion mid-translation keeps the continued translation on '
      'the same card',
      () async {
        // Architect blocker repro (PR #51): the readable-block roll can fire
        // when source completion arrives WHILE the same turn's translation is
        // still streaming. Ordering:
        //   1. source delta
        //   2. translation delta ending on a sentence boundary (readable)
        //   3. source done (turn's source finishes; readable roll arms)
        //   4. later translation delta + done for the SAME turn
        // Before the fix, step 3 set `_readyForNextReadableBlock` and step 4's
        // non-completion translation delta rolled a brand new, source-less
        // card ("Original speech pending" / "--"), then orphaned the
        // translation tail onto it. The completed source utterance is the only
        // reliable turn boundary on this wire, and no NEW source arrived, so
        // the whole turn must stay on one card with the original preserved and
        // the full translation appended.
        final repository = LocalMeetingRepository(
          store: MemoryEncryptedLocalStore(),
        );
        final committer = await committerFor(repository);

        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Hello, how are you?',
          ),
        );
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: 'Ciao, come stai?',
          ),
        );
        // Source for this turn finishes before the translation stream does.
        await committer.commitCompleted(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Hello, how are you?',
          ),
        );
        // The translation for the SAME turn keeps streaming and then finishes.
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.output_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.translation,
            delta: ' Tutto bene.',
          ),
        );
        await committer.commitCompleted(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Ciao, come stai? Tutto bene.',
          ),
        );

        final entries = (await repository.loadSnapshot())
            .meetings
            .single
            .transcriptEntries;
        expect(
          entries,
          hasLength(1),
          reason: 'source completion mid-translation must not split the turn '
              'into a second, source-less card',
        );
        expect(entries.single.originalText, 'Hello, how are you?');
        expect(entries.single.translatedText, 'Ciao, come stai? Tutto bene.');
        for (final entry in entries) {
          expect(
            entry.originalText,
            isNotEmpty,
            reason: 'no card may show "Original speech pending" for a turn '
                'whose source completed',
          );
        }
      },
    );

    test(
      'next source utterance after completion still starts a new card',
      () async {
        // Guard against over-correcting: once the current source utterance has
        // completed, a genuinely new source utterance must still roll a new
        // card on the no-item-id wire.
        final repository = LocalMeetingRepository(
          store: MemoryEncryptedLocalStore(),
        );
        final committer = await committerFor(repository);

        await committer.commitCompleted(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.input_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.source,
            transcript: 'Buongiorno a tutti.',
          ),
        );
        await committer.commitCompleted(
          const OpenAiRealtimeTranscriptCompleted(
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            transcript: 'Good morning everyone.',
          ),
        );
        await committer.commitDelta(
          const OpenAiRealtimeTranscriptDelta(
            type: 'session.input_transcript.delta',
            kind: OpenAiRealtimeTranscriptKind.source,
            delta: 'Come stai oggi?',
          ),
        );

        final entries = (await repository.loadSnapshot())
            .meetings
            .single
            .transcriptEntries;
        expect(entries, hasLength(2));
        expect(entries.first.originalText, 'Buongiorno a tutti.');
        expect(entries.first.translatedText, 'Good morning everyone.');
        expect(entries.last.originalText, 'Come stai oggi?');
      },
    );
  });
}

Future<void> _drainAsync() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Harness {
  _Harness._({required MicrophonePermissionStatus permissionStatus})
    : permissionGateway = _FakePermissionGateway(permissionStatus),
      repository = LocalMeetingRepository(store: MemoryEncryptedLocalStore()),
      captureGateway = _FakeMicrophoneCaptureGateway(),
      playbackGateway = _FakeTranslatedAudioPlaybackGateway(),
      realtimeGateway = _FakeRealtimeTranslationGateway() {
    controller = LiveSessionController(permissionGateway: permissionGateway);
    credentialStore = OpenAiCredentialStore(repository: repository);
    coordinator = LiveRealtimeTranslationCoordinator(
      sessionController: controller,
      credentialStore: credentialStore,
      captureGateway: captureGateway,
      realtimeGateway: realtimeGateway,
      playbackGateway: playbackGateway,
    );
  }

  static Future<_Harness> create({
    required MicrophonePermissionStatus permissionStatus,
    bool seedCredential = true,
    OpenAiRealtimeReconnectPolicy reconnectPolicy =
        const OpenAiRealtimeReconnectPolicy(),
    LiveRealtimeReconnectDelay? reconnectDelay,
    Duration connectionTimeout = const Duration(seconds: 12),
    Duration startupStepTimeout = const Duration(seconds: 12),
    TextInterpreterGateway? textInterpreterGateway,
    PrivacySafeDiagnostics? diagnostics,
    bool enableBidirectionalReverseSession = false,
  }) async {
    final harness = _Harness._(permissionStatus: permissionStatus);
    harness.coordinator = LiveRealtimeTranslationCoordinator(
      sessionController: harness.controller,
      credentialStore: harness.credentialStore,
      captureGateway: harness.captureGateway,
      realtimeGateway: harness.realtimeGateway,
      playbackGateway: harness.playbackGateway,
      reconnectPolicy: reconnectPolicy,
      reconnectDelay: reconnectDelay ?? (_) => Future<void>.value(),
      connectionTimeout: connectionTimeout,
      startupStepTimeout: startupStepTimeout,
      textInterpreterGateway: textInterpreterGateway,
      diagnostics: diagnostics ?? const PrivacySafeDiagnostics(),
      enableBidirectionalReverseSession: enableBidirectionalReverseSession,
    );
    if (seedCredential) {
      await harness.credentialStore.saveUserProvidedCredential(
        'placeholder-credential',
      );
    }
    return harness;
  }

  final _FakePermissionGateway permissionGateway;
  final LocalMeetingRepository repository;
  final _FakeMicrophoneCaptureGateway captureGateway;
  final _FakeTranslatedAudioPlaybackGateway playbackGateway;
  final _FakeRealtimeTranslationGateway realtimeGateway;
  late LiveSessionController controller;
  late OpenAiCredentialStore credentialStore;
  late LiveRealtimeTranslationCoordinator coordinator;
}

class _FakePermissionGateway implements MicrophonePermissionGateway {
  _FakePermissionGateway(this.status);

  final MicrophonePermissionStatus status;
  int requestCount = 0;

  @override
  Future<MicrophonePermissionStatus> checkStatus() async => status;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<MicrophonePermissionStatus> request() async {
    requestCount += 1;
    return status;
  }
}

class _FakeMicrophoneCaptureGateway implements MicrophoneCaptureGateway {
  final StreamController<MicrophonePcm16Chunk> _chunks =
      StreamController<MicrophonePcm16Chunk>.broadcast();
  bool _isCapturing = false;
  int startCount = 0;
  int stopCount = 0;
  bool hangStart = false;
  MicrophoneCaptureConfig? lastConfig;

  @override
  Stream<MicrophonePcm16Chunk> get chunks => _chunks.stream;

  @override
  bool get isCapturing => _isCapturing;

  @override
  Future<void> start(MicrophoneCaptureConfig config) async {
    startCount += 1;
    lastConfig = config;
    if (hangStart) {
      await Completer<void>().future;
      return;
    }
    _isCapturing = true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _isCapturing = false;
  }

  void addChunk(List<int> bytes) {
    _chunks.add(
      MicrophonePcm16Chunk(
        bytes: Uint8List.fromList(bytes),
        sampleRateHz: 24000,
        channelCount: 1,
        duration: const Duration(milliseconds: 200),
      ),
    );
  }
}

class _FakeTranslatedAudioPlaybackGateway
    implements TranslatedAudioPlaybackGateway {
  bool _isOpen = false;
  int startCount = 0;
  int stopCount = 0;
  bool hangStart = false;
  TranslatedAudioPlaybackConfig? lastConfig;
  final List<TranslatedAudioPcm16Chunk> enqueuedChunks = [];

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> start(TranslatedAudioPlaybackConfig config) async {
    startCount += 1;
    lastConfig = config;
    if (hangStart) {
      await Completer<void>().future;
      return;
    }
    _isOpen = true;
  }

  @override
  Future<void> enqueuePcm16(TranslatedAudioPcm16Chunk chunk) async {
    if (!_isOpen) {
      throw StateError('Playback queue is closed.');
    }

    enqueuedChunks.add(chunk);
  }

  @override
  Future<void> stop({required bool clearQueue}) async {
    stopCount += 1;
    _isOpen = false;
    if (clearQueue) {
      enqueuedChunks.clear();
    }
  }
}

class _FakeRealtimeTranslationGateway implements RealtimeTranslationGateway {
  final List<_FakeRealtimeTranslationSession> sessions = [];
  final List<OpenAiRealtimeTranslationConfig> configs = [];
  final List<String> credentials = [];
  int connectCount = 0;
  bool failNextConnect = false;
  bool hangNextConnect = false;
  bool delayNextConnect = false;
  Completer<RealtimeTranslationSession>? _delayedConnect;

  _FakeRealtimeTranslationSession get session => sessions.last;

  @override
  Future<RealtimeTranslationSession> connect({
    required OpenAiRealtimeTranslationConfig config,
    required String credential,
  }) async {
    connectCount += 1;
    if (hangNextConnect) {
      hangNextConnect = false;
      return Completer<RealtimeTranslationSession>().future;
    }
    if (failNextConnect) {
      failNextConnect = false;
      throw StateError('socket reconnect failed');
    }

    final session = _FakeRealtimeTranslationSession();
    sessions.add(session);
    configs.add(config);
    credentials.add(credential);
    if (delayNextConnect) {
      delayNextConnect = false;
      final completer = Completer<RealtimeTranslationSession>();
      _delayedConnect = completer;
      return completer.future;
    }
    return session;
  }

  void completeDelayedConnect() {
    final completer = _delayedConnect;
    _delayedConnect = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(session);
    }
  }
}

class _FakeRealtimeTranslationSession implements RealtimeTranslationSession {
  final StreamController<OpenAiRealtimeEvent> _events =
      StreamController<OpenAiRealtimeEvent>.broadcast();
  final List<List<int>> appendedChunks = [];
  final List<OpenAiRealtimeEvent> eventsOnGracefulClose = [];
  int closeGracefullyCount = 0;
  int closeImmediatelyCount = 0;
  int commitInputAudioBufferCount = 0;
  int createResponseCount = 0;

  @override
  Stream<OpenAiRealtimeEvent> get events => _events.stream;

  @override
  void appendPcm16Audio(List<int> pcm16Audio) {
    appendedChunks.add(List<int>.from(pcm16Audio));
  }

  @override
  void commitInputAudioBuffer() {
    commitInputAudioBufferCount += 1;
  }

  @override
  void createResponse() {
    createResponseCount += 1;
  }

  @override
  Future<void> closeGracefully() async {
    closeGracefullyCount += 1;
    for (final event in eventsOnGracefulClose) {
      _events.add(event);
    }
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> closeImmediately() async {
    closeImmediatelyCount += 1;
  }

  @override
  void sendSessionUpdate() {}

  void addEvent(OpenAiRealtimeEvent event) {
    _events.add(event);
  }
}

class _FakeTextInterpreterGateway implements TextInterpreterGateway {
  final List<TextInterpreterTurnRequest> requests = [];
  final List<TextInterpreterTurnResult> results = [];
  final List<String> credentials = [];

  @override
  Future<TextInterpreterTurnResult> interpretTurn({
    required TextInterpreterTurnRequest request,
    required String credential,
  }) async {
    requests.add(request);
    credentials.add(credential);
    return results.removeAt(0);
  }
}
