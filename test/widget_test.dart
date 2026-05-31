import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:realtime_translate_mobile/main.dart';
import 'package:realtime_translate_mobile/src/language/language_support.dart';
import 'package:realtime_translate_mobile/src/openai/openai_ai_chat.dart';
import 'package:realtime_translate_mobile/src/openai/openai_credential_store.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_resilience.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';
import 'package:realtime_translate_mobile/src/openai/openai_text_interpreter.dart';
import 'package:realtime_translate_mobile/src/mock/mock_live_translate_data.dart';
import 'package:realtime_translate_mobile/src/session/live_session_controller.dart';
import 'package:realtime_translate_mobile/src/session/microphone_capture.dart';
import 'package:realtime_translate_mobile/src/session/microphone_permission.dart';
import 'package:realtime_translate_mobile/src/session/translated_audio_playback.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';
import 'package:realtime_translate_mobile/src/storage/local_storage_models.dart';
import 'package:realtime_translate_mobile/src/theme/live_translate_theme.dart';
import 'package:realtime_translate_mobile/src/ui/live_translate_models.dart';

void main() {
  testWidgets('shows phone-local start surface', (tester) async {
    final repository = _testRepository();
    await tester.pumpWidget(LiveTranslateApp(meetingRepository: repository));

    expect(find.text('Live Translate'), findsOneWidget);
    expect(find.text('Start interpreter'), findsOneWidget);
    expect(find.text('Open meeting history'), findsOneWidget);
    expect(find.text('OpenAI setup'), findsOneWidget);
    expect(
      find.text(
        'Transcripts are stored on device only. Your conversations stay private.',
      ),
      findsOneWidget,
    );
    expect(find.text('Copyright by Xenovis Pty Ltd'), findsOneWidget);
    expect(find.text('Secure & Private'), findsNothing);
    expect(find.text('Android MVP'), findsNothing);

    expect(find.textContaining('Continue with'), findsNothing);
    expect(find.textContaining('Flutter Demo'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('saves OpenAI credential locally before live start', (
    tester,
  ) async {
    final repository = _testRepository();
    await tester.pumpWidget(LiveTranslateApp(meetingRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI setup required'), findsWidgets);
    expect(find.text('Open OpenAI setup'), findsOneWidget);

    await tester.tap(find.text('Open OpenAI setup'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'placeholder-local-openai-credential',
    );
    await tester.tap(find.text('Save encrypted credential'));
    await tester.pumpAndSettle();

    expect(
      find.text('OpenAI credential stored on this device'),
      findsOneWidget,
    );
    expect(find.text('placeholder-local-openai-credential'), findsNothing);
    expect(
      await OpenAiCredentialStore(
        repository: repository,
      ).readCredentialForNetworkUse(),
      'placeholder-local-openai-credential',
    );

    await tester.tap(find.text('Remove credential from this device'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI setup required'), findsWidgets);
    expect(find.text('Remove credential from this device'), findsNothing);
    expect(
      await OpenAiCredentialStore(
        repository: repository,
      ).readCredentialForNetworkUse(),
      isNull,
    );
  });

  testWidgets('opens teal listening without competing live controls', (
    tester,
  ) async {
    final repository = _testRepository();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: _FakeRealtimeTranslationGateway(),
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();

    expect(find.text('Listening for languages...'), findsOneWidget);
    expect(find.text('Auto-detect Spanish -> English'), findsNothing);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Pause Listening'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause listening'), findsOneWidget);
    expect(find.text('Translate Text'), findsNothing);
    expect(find.text('Waiting for speech'), findsOneWidget);
    expect(
      find.text('Live transcript lines will appear here.'),
      findsOneWidget,
    );
    expect(find.text('Jump to Live'), findsNothing);

    final activeMeeting = (await repository.loadSnapshot()).meetings.single;
    await _appendStoredTranscriptLine(repository, activeMeeting.id);

    expect(find.bySemanticsLabel(RegExp('To language selector')), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('From language selector')),
      findsNothing,
    );
    expect(find.text('Switch'), findsNothing);
    expect(find.text('Read Aloud'), findsNothing);
    expect(find.text('Pause Read Aloud'), findsNothing);
    expect(find.byTooltip('Open AI chat'), findsNothing);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();

    expect(find.text('Meeting history'), findsOneWidget);
    expect(find.text('Generate export'), findsNothing);
    expect(find.text('Open generated exports'), findsNothing);
  });

  testWidgets('starts interpreter without language pickers or voice controls', (
    tester,
  ) async {
    final repository = _testRepository();
    final realtimeGateway = _FakeRealtimeTranslationGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: realtimeGateway,
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();
    expect(find.text('Listening for languages...'), findsOneWidget);
    expect(realtimeGateway.configs.last.targetLanguageCode, 'en');
    expect(realtimeGateway.configs.last.sourceLanguageCode, 'auto');
    expect(
      realtimeGateway.configs.last.profile,
      OpenAiRealtimeTranslationProfile.dedicatedTranslation,
    );
    final initialRealtimeConfigCount = realtimeGateway.configs.length;
    expect(find.bySemanticsLabel(RegExp('To language selector')), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('From language selector')),
      findsNothing,
    );
    expect(find.text('Switch'), findsNothing);
    expect(find.text('Read Aloud'), findsNothing);
    expect(find.text('Pause Read Aloud'), findsNothing);
    expect(find.text('Pause Listening'), findsOneWidget);
    expect(find.bySemanticsLabel('Translate Text on'), findsNothing);
    expect(realtimeGateway.configs.length, initialRealtimeConfigCount);
  });

  testWidgets('shows live connecting surface while realtime starts', (
    tester,
  ) async {
    final repository = _testRepository();
    final realtimeGateway = _BlockingRealtimeTranslationGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: realtimeGateway,
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Preparing live interpretation on this phone...'),
      findsOneWidget,
    );
    expect(find.text('Listening for languages...'), findsNothing);
    expect(find.text('Auto-detect Spanish -> English'), findsNothing);
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Connecting to OpenAI'), findsOneWidget);
    expect(
      find.text(
        'Preparing live interpretation on this phone. Recording starts after the secure realtime session is ready.',
      ),
      findsOneWidget,
    );
    expect(find.text('Start interpreter'), findsNothing);

    realtimeGateway.completeConnect();
    await tester.pumpAndSettle();

    expect(find.text('Listening'), findsOneWidget);
  });

  testWidgets('pause and resume listening controls keep meeting transcript', (
    tester,
  ) async {
    final repository = _testRepository();
    final realtimeGateway = _FakeRealtimeTranslationGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: realtimeGateway,
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();
    final meetingId = (await repository.loadSnapshot()).meetings.single.id;
    await _appendStoredTranscriptLine(repository, meetingId);
    realtimeGateway.sessions.first.delayGracefulClose();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Pause listening'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Listening paused'), findsWidgets);
    expect(find.text('Resume Listening'), findsOneWidget);
    expect(find.bySemanticsLabel('Resume listening'), findsOneWidget);
    expect(
      find.text('They agreed to meet on Tuesday at 10 AM.'),
      findsOneWidget,
    );
    expect(realtimeGateway.sessions.first.closeGracefullyCount, 1);

    realtimeGateway.sessions.first.completeGracefulClose();
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Resume listening'));
    await tester.pumpAndSettle();

    expect(find.text('Pause Listening'), findsOneWidget);
    expect(find.text('Resume Listening'), findsNothing);
    expect(realtimeGateway.sessions, hasLength(2));
    expect((await repository.loadSnapshot()).meetings.single.id, meetingId);
  });

  testWidgets('keeps startup failure on live surface with recovery banner', (
    tester,
  ) async {
    final repository = _testRepository();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: _ThrowingRealtimeTranslationGateway(),
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();

    expect(find.text('Listening for languages...'), findsOneWidget);
    expect(find.text('Auto-detect Spanish -> English'), findsNothing);
    expect(find.text('Reconnecting to OpenAI'), findsOneWidget);
    expect(
      find.text('Connection interrupted. Reconnecting to OpenAI shortly.'),
      findsOneWidget,
    );
    expect(find.text('socket connection interrupted'), findsNothing);
    expect((await repository.loadSnapshot()).meetings, hasLength(1));
    expect(find.text('Start interpreter'), findsNothing);
  });

  testWidgets(
    'live interpreter hides source target pickers and direction switch',
    (tester) async {
      final repository = _testRepository();
      final realtimeGateway = _FakeRealtimeTranslationGateway();
      await _seedCredential(repository);
      await tester.pumpWidget(
        LiveTranslateApp(
          permissionGateway: _FakePermissionGateway.granted(),
          meetingRepository: repository,
          microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
          translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
          realtimeTranslationGateway: realtimeGateway,
        ),
      );

      await tester.tap(find.text('Start interpreter'));
      await tester.pumpAndSettle();
      expect(find.text('Listening for languages...'), findsOneWidget);
      expect(find.text('Auto-detect Spanish -> English'), findsNothing);
      expect(realtimeGateway.configs.last.sourceLanguageCode, 'auto');

      expect(find.text('Switch'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('To language selector')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp('From language selector')),
        findsNothing,
      );

      expect(find.text('Listening for languages...'), findsOneWidget);
      expect(find.text('Auto-detect Spanish -> English'), findsNothing);
      var snapshot = await repository.loadSnapshot();
      expect(snapshot.meetings.single.sourceLanguageLabel, 'Auto-detect');
      expect(snapshot.meetings.single.targetLanguageLabel, 'English (US)');
      expect(realtimeGateway.configs.last.sourceLanguageCode, 'auto');
    },
  );

  testWidgets('renders live transcript commits on the active screen', (
    tester,
  ) async {
    final repository = _testRepository();
    final realtimeGateway = _FakeRealtimeTranslationGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: realtimeGateway,
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for speech'), findsOneWidget);

    realtimeGateway.sessions.last
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.output_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.translation,
          delta: 'Hello ',
        ),
      )
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.input_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.source,
          languageCode: 'es',
          delta: 'Hola ',
        ),
      );

    await tester.pump(const Duration(milliseconds: 60));
    realtimeGateway.sessions.last
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.output_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.translation,
          delta: 'team.',
        ),
      )
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.input_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.source,
          delta: 'equipo.',
        ),
      );

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for speech'), findsNothing);
    expect(
      find.text('Heard Spanish. Waiting for the other language...'),
      findsOneWidget,
    );
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Hola equipo.'), findsOneWidget);
    expect(find.text('Translation'), findsOneWidget);
    expect(find.text('Hello team.'), findsOneWidget);
    expect(find.text('Translating...'), findsOneWidget);

    realtimeGateway.sessions.last.addEvent(
      const OpenAiRealtimeTranscriptDelta(
        type: 'session.input_transcript.delta',
        kind: OpenAiRealtimeTranscriptKind.source,
        languageCode: 'en',
        itemId: 'source-en-1',
        delta: 'Thank you.',
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Spanish <-> English'), findsOneWidget);
  });

  testWidgets(
    'active realtime path uses English Italian text fallback direction',
    (tester) async {
      final repository = _testRepository();
      final realtimeGateway = _FakeRealtimeTranslationGateway();
      final textGateway = _FakeTextInterpreterGateway();
      textGateway.results.add(
        const TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
          translatedText: 'Possiamo confermare il piano.',
        ),
      );
      await _seedCredential(repository);
      await tester.pumpWidget(
        LiveTranslateApp(
          permissionGateway: _FakePermissionGateway.granted(),
          meetingRepository: repository,
          microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
          translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
          realtimeTranslationGateway: realtimeGateway,
          textInterpreterGateway: textGateway,
        ),
      );

      await tester.tap(find.text('Start interpreter'));
      await tester.pumpAndSettle();
      expect(realtimeGateway.configs.last.targetLanguageCode, 'en');

      realtimeGateway.sessions.last.addEvent(
        const OpenAiRealtimeTranscriptCompleted(
          type: 'session.input_transcript.done',
          kind: OpenAiRealtimeTranscriptKind.source,
          itemId: 'source-en-1',
          languageCode: 'en',
          transcript: 'We can confirm the plan.',
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      realtimeGateway.sessions.last
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
            type: 'session.output_transcript.done',
            kind: OpenAiRealtimeTranscriptKind.translation,
            itemId: 'source-it-1',
            transcript: 'We can begin.',
          ),
        );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final entries =
          (await repository.loadSnapshot()).meetings.single.transcriptEntries;
      expect(entries, hasLength(2));
      expect(entries.first.languageCode, 'EN');
      expect(entries.first.originalText, 'We can confirm the plan.');
      expect(entries.first.translatedText, 'Possiamo confermare il piano.');
      expect(entries.last.languageCode, 'IT');
      expect(entries.last.originalText, 'Possiamo iniziare.');
      expect(entries.last.translatedText, 'We can begin.');
      expect(find.text('English <-> Italian'), findsOneWidget);
      expect(find.text('Possiamo confermare il piano.'), findsOneWidget);
      expect(find.text('We can begin.'), findsOneWidget);

      expect(textGateway.requests, hasLength(1));
      final request = textGateway.requests.single;
      expect(request.sourceLanguageCode, 'en');
      expect(request.targetLanguageCode, 'it');
      expect(request.routeType, TranslationRouteType.directOpenAiFallback);
      expect(request.knownLanguageCodes, ['en', 'it']);
      expect(
        textGateway.credentials.single,
        'placeholder-local-openai-credential',
      );
    },
  );

  testWidgets('shows reconnecting realtime recovery state on live surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      _liveSessionHarness(
        const LiveSessionState(
          phase: LiveSessionPhase.reconnecting,
          microphonePermission: MicrophonePermissionStatus.granted,
          audioRoute: LiveAudioRoute.speaker,
          isMicrophoneCaptureOpen: false,
          isRealtimeSessionOpen: false,
          isPlaybackQueueOpen: false,
          realtimeRetryAttempt: 1,
          realtimeReconnectDelay: Duration(milliseconds: 500),
          notice: 'Connection interrupted. Reconnecting to OpenAI shortly.',
        ),
      ),
    );

    expect(find.text('Reconnecting to OpenAI'), findsOneWidget);
    expect(
      find.text('Connection interrupted. Reconnecting to OpenAI shortly.'),
      findsOneWidget,
    );
    expect(find.textContaining('Retry attempt 1'), findsOneWidget);
    expect(find.text('Back to start'), findsOneWidget);
    expect(find.text('Retry live session'), findsNothing);
  });

  testWidgets('shows stopped realtime recovery state with retry action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _liveSessionHarness(
        const LiveSessionState(
          phase: LiveSessionPhase.offline,
          microphonePermission: MicrophonePermissionStatus.granted,
          audioRoute: LiveAudioRoute.speaker,
          isMicrophoneCaptureOpen: false,
          isRealtimeSessionOpen: false,
          isPlaybackQueueOpen: false,
          realtimeRetryAttempt: 5,
          realtimeReconnectDelay: Duration.zero,
          notice:
              'Network connection appears offline. Live translation is paused.',
        ),
      ),
    );

    expect(find.text('Live translation paused'), findsOneWidget);
    expect(
      find.text(
        'Network connection appears offline. Live translation is paused.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retries exhausted after 5 attempts.'), findsOneWidget);
    expect(find.text('Retry live session'), findsOneWidget);
    expect(find.text('Back to start'), findsOneWidget);
  });

  testWidgets('shows rate-limit recovery without raw OpenAI error details', (
    tester,
  ) async {
    await tester.pumpWidget(
      _liveSessionHarness(
        const LiveSessionState(
          phase: LiveSessionPhase.error,
          microphonePermission: MicrophonePermissionStatus.granted,
          audioRoute: LiveAudioRoute.speaker,
          isMicrophoneCaptureOpen: false,
          isRealtimeSessionOpen: false,
          isPlaybackQueueOpen: false,
          realtimeRetryAttempt: 2,
          realtimeReconnectDelay: Duration.zero,
          realtimeRecoveryAction: OpenAiRealtimeRecoveryAction.fatalError,
          realtimeFailureKind: OpenAiRealtimeFailureKind.rateLimited,
          notice:
              'OpenAI rate limits persisted after retries. Restart when quota is available.',
        ),
      ),
    );

    expect(find.text('OpenAI rate limit reached'), findsOneWidget);
    expect(
      find.text(
        'OpenAI rate limits persisted after retries. Restart when quota is available.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('rate_limit_exceeded'), findsNothing);
    expect(find.text('Retry live session'), findsOneWidget);
    expect(find.text('Back to start'), findsOneWidget);
  });

  testWidgets('shows unsupported language recovery without retry loop', (
    tester,
  ) async {
    await tester.pumpWidget(
      _liveSessionHarness(
        const LiveSessionState(
          phase: LiveSessionPhase.error,
          microphonePermission: MicrophonePermissionStatus.granted,
          audioRoute: LiveAudioRoute.speaker,
          isMicrophoneCaptureOpen: false,
          isRealtimeSessionOpen: false,
          isPlaybackQueueOpen: false,
          realtimeRetryAttempt: 0,
          realtimeReconnectDelay: Duration.zero,
          realtimeRecoveryAction:
              OpenAiRealtimeRecoveryAction.unsupportedLanguage,
          notice:
              'This target language is not available for realtime output. Choose another target language.',
        ),
      ),
    );

    expect(find.text('Language not supported'), findsOneWidget);
    expect(
      find.text(
        'This target language is not available for realtime output. Choose another target language.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry live session'), findsNothing);
    expect(find.text('Back to start'), findsOneWidget);
  });

  testWidgets('opens all-meetings AI chat from meeting history', (
    tester,
  ) async {
    final repository = _testRepository();
    final aiChatGateway = _FakeAiChatGateway(
      'Across meetings, the timeline was agreed at 10:37 AM.',
    );
    final realtimeGateway = _FakeRealtimeTranslationGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        aiChatGateway: aiChatGateway,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: realtimeGateway,
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();
    final activeMeeting = (await repository.loadSnapshot()).meetings.single;
    await _appendStoredTranscriptLine(repository, activeMeeting.id);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meeting history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask across meetings'));
    await tester.pumpAndSettle();

    expect(find.text('AI Chat'), findsOneWidget);
    expect(find.text('All meetings'), findsOneWidget);
    expect(find.text('Ask across meetings...'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Summarise timeline');
    await tester.tap(find.byTooltip('Send AI chat prompt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Across meetings'), findsOneWidget);
    expect(
      aiChatGateway.requests.single.context.scope,
      AiChatScope.allMeetings,
    );
  });

  testWidgets('hides generated export controls from the live screen', (
    tester,
  ) async {
    final repository = _testRepository();
    final realtimeGateway = _FakeRealtimeTranslationGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: realtimeGateway,
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();

    expect(find.text('Listening for languages...'), findsOneWidget);
    expect(find.text('Auto-detect Spanish -> English'), findsNothing);
    expect(find.text('Read Aloud'), findsNothing);
    expect(find.text('Speaker Active'), findsNothing);
    expect(find.text('Read aloud is paused'), findsNothing);
    expect(find.text('Resume Read Aloud'), findsNothing);
    expect(find.text('Waiting for speech'), findsOneWidget);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('Resume read-aloud meeting'), findsNothing);
    expect(find.text('Meeting history'), findsOneWidget);
    expect(find.text('Generate export'), findsNothing);
    expect(find.text('Open generated exports'), findsNothing);
    expect(find.byTooltip('Add recipient'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('recipient@example.com'), findsNothing);
  });

  testWidgets('keeps hidden live controls hidden after lifecycle and menu', (
    tester,
  ) async {
    final repository = _testRepository();
    final realtimeGateway = _FakeRealtimeTranslationGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: realtimeGateway,
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();
    _expectHiddenActiveLiveControls();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    _expectHiddenActiveLiveControls();

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();

    expect(find.text('Meeting history'), findsOneWidget);
    _expectHiddenActiveLiveControls();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    _expectHiddenActiveLiveControls();
  });

  testWidgets('blocks live session when microphone permission is denied', (
    tester,
  ) async {
    final repository = _testRepository();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.denied(),
        meetingRepository: repository,
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();

    expect(find.text('Microphone access needed'), findsOneWidget);
    expect(find.text('Try microphone permission again'), findsOneWidget);
    expect(
      find.text(
        'No audio is captured before microphone permission is granted.',
      ),
      findsOneWidget,
    );
    expect(find.text('Listening for languages...'), findsNothing);
  });

  testWidgets('delete updates open meeting history and clears active meeting', (
    tester,
  ) async {
    final repository = _testRepository();
    final captureGateway = _FakeMicrophoneCaptureGateway();
    final realtimeGateway = _FakeRealtimeTranslationGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: captureGateway,
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: realtimeGateway,
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();
    expect((await repository.loadSnapshot()).meetings, hasLength(1));
    expect(captureGateway.isCapturing, isTrue);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meeting history'));
    await tester.pumpAndSettle();

    expect(find.text('Live interpreter meeting'), findsOneWidget);

    final deleteMeetingButton = find.byTooltip(
      'Delete Live interpreter meeting',
    );
    await tester.ensureVisible(deleteMeetingButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteMeetingButton);
    await tester.pumpAndSettle();

    expect((await repository.loadSnapshot()).meetings, isEmpty);
    expect(find.text('Live interpreter meeting'), findsNothing);
    expect(find.text('No saved meetings yet'), findsOneWidget);
    expect(find.text('Meeting deleted.'), findsWidgets);
    expect(find.text('Start interpreter'), findsOneWidget);
    expect(captureGateway.isCapturing, isFalse);
    expect(realtimeGateway.sessions.single.closeImmediatelyCount, 1);
    expect(realtimeGateway.sessions.single.closeGracefullyCount, 0);
  });

  testWidgets('selects an old meeting and appends local history', (
    tester,
  ) async {
    final repository = _testRepository();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: _FakeRealtimeTranslationGateway(),
      ),
    );

    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();

    final initialMeeting = (await repository.loadSnapshot()).meetings.single;

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meeting history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Live interpreter meeting'));
    await tester.pumpAndSettle();

    final continuedMeeting = (await repository.loadSnapshot()).meetings.single;
    expect(continuedMeeting.id, initialMeeting.id);
    expect(continuedMeeting.transcriptCount, initialMeeting.transcriptCount);
    expect(continuedMeeting.createdAt, initialMeeting.createdAt);
    expect(
      continuedMeeting.updatedAt.isAfter(initialMeeting.updatedAt),
      isTrue,
    );
    expect(find.text('Live interpreter meeting'), findsNothing);
    expect(find.text('Listening for languages...'), findsOneWidget);
    expect(find.text('Auto-detect Spanish -> English'), findsNothing);
  });

  testWidgets('normalizes legacy auto-detect source labels in history', (
    tester,
  ) async {
    final repository = _testRepository();
    final now = DateTime.utc(2026, 5, 27, 10, 42);
    await repository.upsertMeeting(
      StoredMeeting(
        id: 'legacy-meeting',
        title: 'Legacy meeting',
        createdAt: now,
        updatedAt: now,
        sourceLanguageLabel: 'Auto-detect Spanish',
        targetLanguageLabel: 'English (US)',
        transcriptEntries: const [],
        summaryMetadata: const StoredSummaryMetadata.empty(),
      ),
    );
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: _FakeRealtimeTranslationGateway(),
      ),
    );

    await tester.tap(find.text('Open meeting history'));
    await tester.pumpAndSettle();

    expect(find.text('Listening for languages...'), findsOneWidget);
    expect(find.text('Auto-detect Spanish -> English'), findsNothing);

    await tester.tap(find.text('Legacy meeting'));
    await tester.pumpAndSettle();

    expect(find.text('Listening for languages...'), findsOneWidget);
    expect(find.text('Auto-detect Spanish -> English'), findsNothing);
  });
}

LocalMeetingRepository _testRepository() {
  return LocalMeetingRepository(store: MemoryEncryptedLocalStore());
}

Future<void> _seedCredential(LocalMeetingRepository repository) {
  return OpenAiCredentialStore(
    repository: repository,
  ).saveUserProvidedCredential('placeholder-local-openai-credential');
}

Future<void> _appendStoredTranscriptLine(
  LocalMeetingRepository repository,
  String meetingId,
) async {
  final snapshot = await repository.loadSnapshot();
  final meeting = snapshot.meetings.singleWhere((item) => item.id == meetingId);
  final currentTime = DateTime.now().toUtc();
  final now = currentTime.isAfter(meeting.updatedAt)
      ? currentTime
      : meeting.updatedAt.add(const Duration(microseconds: 1));
  await repository.appendTranscriptEntry(
    meetingId: meetingId,
    updatedAt: now,
    entry: StoredTranscriptEntry(
      id: '$meetingId-test-line',
      meetingId: meetingId,
      languageCode: 'EN',
      originalText: 'Timeline was agreed.',
      translatedText: 'They agreed to meet on Tuesday at 10 AM.',
      timestamp: now,
      speakerLabel: null,
      confidence: null,
      status: 'final',
      playbackState: TranscriptPlaybackState.playable.name,
    ),
  );
}

void _expectHiddenActiveLiveControls() {
  expect(find.text('Listening for languages...'), findsOneWidget);
  expect(find.text('Auto-detect Spanish -> English'), findsNothing);
  expect(find.bySemanticsLabel(RegExp('From language selector')), findsNothing);
  expect(find.bySemanticsLabel(RegExp('To language selector')), findsNothing);
  expect(find.text('Switch'), findsNothing);
  expect(find.text('Switch Direction'), findsNothing);
  expect(find.text('Translate Text'), findsNothing);
  expect(find.text('Read Aloud'), findsNothing);
  expect(find.text('Resume read-aloud meeting'), findsNothing);
  expect(find.text('Pause Read Aloud'), findsNothing);
  expect(find.text('Resume Read Aloud'), findsNothing);
  expect(find.text('Speaker Active'), findsNothing);
  expect(find.text('Headphones Active'), findsNothing);
  expect(find.byTooltip('Open AI chat'), findsNothing);
  expect(find.text('Generate export'), findsNothing);
  expect(find.text('Open generated exports'), findsNothing);
}

Widget _liveSessionHarness(LiveSessionState state) {
  return MaterialApp(
    theme: LiveTranslateTheme.dark(),
    home: LiveSessionScreen(
      session: MockLiveTranslateData.listeningSession,
      sessionState: state,
      onOpenMenu: () {},
      onOpenAssistant: () {},
      onOpenSourceLanguageOptions: () {},
      onOpenTargetLanguageOptions: () {},
      onDirectionSwitch: () {},
      onRetryLiveSession: () {},
      onBottomAction: (_) {},
      onFeatureToggle: (_) {},
      onQueuePrimaryAction: () {},
      onQueueSecondaryAction: () {},
      onJumpToLive: () {},
    ),
  );
}

class _FakePermissionGateway implements MicrophonePermissionGateway {
  _FakePermissionGateway(this._status);

  _FakePermissionGateway.granted() : this(MicrophonePermissionStatus.granted);

  _FakePermissionGateway.denied() : this(MicrophonePermissionStatus.denied);

  final MicrophonePermissionStatus _status;

  @override
  Future<MicrophonePermissionStatus> checkStatus() async => _status;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<MicrophonePermissionStatus> request() async => _status;
}

class _FakeMicrophoneCaptureGateway implements MicrophoneCaptureGateway {
  final _chunks = StreamController<MicrophonePcm16Chunk>.broadcast(sync: true);

  @override
  Stream<MicrophonePcm16Chunk> get chunks => _chunks.stream;

  @override
  bool get isCapturing => _isCapturing;

  bool _isCapturing = false;

  @override
  Future<void> start(MicrophoneCaptureConfig config) async {
    _isCapturing = true;
  }

  @override
  Future<void> stop() async {
    _isCapturing = false;
  }
}

class _FakeRealtimeTranslationGateway implements RealtimeTranslationGateway {
  final List<OpenAiRealtimeTranslationConfig> configs = [];
  final List<_FakeRealtimeTranslationSession> sessions = [];

  @override
  Future<RealtimeTranslationSession> connect({
    required OpenAiRealtimeTranslationConfig config,
    required String credential,
  }) async {
    configs.add(config);
    final session = _FakeRealtimeTranslationSession();
    sessions.add(session);
    return session;
  }
}

class _BlockingRealtimeTranslationGateway
    implements RealtimeTranslationGateway {
  final _connectCompleter = Completer<RealtimeTranslationSession>();
  final session = _FakeRealtimeTranslationSession();

  @override
  Future<RealtimeTranslationSession> connect({
    required OpenAiRealtimeTranslationConfig config,
    required String credential,
  }) {
    return _connectCompleter.future;
  }

  void completeConnect() {
    if (!_connectCompleter.isCompleted) {
      _connectCompleter.complete(session);
    }
  }
}

class _ThrowingRealtimeTranslationGateway
    implements RealtimeTranslationGateway {
  @override
  Future<RealtimeTranslationSession> connect({
    required OpenAiRealtimeTranslationConfig config,
    required String credential,
  }) async {
    throw StateError('socket connection interrupted');
  }
}

class _FakeRealtimeTranslationSession implements RealtimeTranslationSession {
  final _events = StreamController<OpenAiRealtimeEvent>.broadcast(sync: true);
  Completer<void>? _gracefulCloseCompleter;
  int closeGracefullyCount = 0;
  int closeImmediatelyCount = 0;

  @override
  Stream<OpenAiRealtimeEvent> get events => _events.stream;

  void addEvent(OpenAiRealtimeEvent event) {
    _events.add(event);
  }

  @override
  void appendPcm16Audio(List<int> pcm16Audio) {}

  @override
  void commitInputAudioBuffer() {}

  @override
  void createResponse() {}

  @override
  Future<void> closeGracefully() async {
    closeGracefullyCount += 1;
    await _gracefulCloseCompleter?.future;
    unawaited(_events.close());
  }

  @override
  Future<void> closeImmediately() async {
    closeImmediatelyCount += 1;
    unawaited(_events.close());
  }

  @override
  void sendSessionUpdate() {}

  void delayGracefulClose() {
    _gracefulCloseCompleter = Completer<void>();
  }

  void completeGracefulClose() {
    final completer = _gracefulCloseCompleter;
    _gracefulCloseCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class _FakeAiChatGateway implements AiChatGateway {
  _FakeAiChatGateway(this.answer);

  final String answer;
  final List<AiChatRequest> requests = [];

  @override
  Future<AiChatAnswer> ask({
    required AiChatRequest request,
    required String credential,
  }) async {
    requests.add(request);
    expect(credential, 'placeholder-local-openai-credential');
    return AiChatAnswer(
      text: answer,
      generatedAt: DateTime(2026, 5, 24, 2, 42),
    );
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
