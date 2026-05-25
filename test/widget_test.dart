import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:realtime_translate_mobile/main.dart';
import 'package:realtime_translate_mobile/src/openai/openai_ai_chat.dart';
import 'package:realtime_translate_mobile/src/openai/openai_credential_store.dart';
import 'package:realtime_translate_mobile/src/openai/openai_meeting_summary.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_resilience.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';
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
    expect(find.text('Start new meeting'), findsOneWidget);
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

    await tester.tap(find.text('Start new meeting'));
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

  testWidgets('opens teal listening and scoped AI chat surfaces', (
    tester,
  ) async {
    final repository = _testRepository();
    final aiChatGateway = _FakeAiChatGateway(
      'They agreed to meet on Tuesday at 10 AM (10:37 AM).',
    );
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        aiChatGateway: aiChatGateway,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: _FakeRealtimeTranslationGateway(),
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();

    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Translate Text'), findsOneWidget);
    expect(find.text('Waiting for speech'), findsOneWidget);
    expect(
      find.text('Live transcript lines will appear here.'),
      findsOneWidget,
    );
    expect(find.text('Jump to Live'), findsNothing);

    final activeMeeting = (await repository.loadSnapshot()).meetings.single;
    await _appendStoredTranscriptLine(repository, activeMeeting.id);

    await tester.tap(find.bySemanticsLabel(RegExp('To language selector')));
    await tester.pumpAndSettle();

    expect(find.text('Target languages'), findsOneWidget);
    expect(find.text('English (US)'), findsOneWidget);
    expect(find.text('Spanish (ES)'), findsOneWidget);
    expect(find.text('French (FR)'), findsOneWidget);
    expect(find.text('Japanese (JP)'), findsOneWidget);
    expect(find.text('Fallback route'), findsOneWidget);
    expect(find.textContaining('fallback targets'), findsOneWidget);

    Navigator.of(tester.element(find.text('Target languages'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open AI chat'));
    await tester.pumpAndSettle();

    expect(find.text('AI Chat'), findsOneWidget);
    expect(find.text('This meeting'), findsOneWidget);
    expect(find.textContaining('Ready to answer from'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'What did they agree about the timeline?',
    );
    await tester.tap(find.byTooltip('Send AI chat prompt'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('They agreed to meet on Tuesday at 10 AM'),
      findsOneWidget,
    );
    expect(
      aiChatGateway.requests.single.context.scope,
      AiChatScope.thisMeeting,
    );
    expect(
      aiChatGateway.requests.single.context.transcriptEntryCount,
      greaterThan(0),
    );
  });

  testWidgets('selects realtime target language and toggles live outputs', (
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

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);
    expect(realtimeGateway.configs.last.targetLanguageCode, 'en');

    await tester.tap(find.bySemanticsLabel(RegExp('To language selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('French (FR)'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Auto-detect Spanish -> French'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Translate Text on'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Translate Text off'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Read Aloud on'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Read Aloud off'), findsOneWidget);
    expect(find.text('Read aloud is paused'), findsOneWidget);
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

    await tester.tap(find.text('Start new meeting'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Start new meeting'), findsNothing);

    realtimeGateway.completeConnect();
    await tester.pumpAndSettle();

    expect(find.text('Listening'), findsOneWidget);
  });

  testWidgets('switches direction repeatedly without corrupting languages', (
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

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);

    await tester.tap(find.text('Switch'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('English -> Spanish'), findsOneWidget);
    var snapshot = await repository.loadSnapshot();
    expect(snapshot.meetings.single.sourceLanguageLabel, 'English (US)');
    expect(snapshot.meetings.single.targetLanguageLabel, 'Spanish (ES)');

    await tester.tap(find.text('Switch'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Spanish -> English'), findsOneWidget);
    snapshot = await repository.loadSnapshot();
    expect(snapshot.meetings.single.sourceLanguageLabel, 'Spanish (ES)');
    expect(snapshot.meetings.single.targetLanguageLabel, 'English (US)');
  });

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

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for speech'), findsOneWidget);

    realtimeGateway.sessions.last
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.output_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.translation,
          delta: 'Hello team.',
        ),
      )
      ..addEvent(
        const OpenAiRealtimeTranscriptDelta(
          type: 'session.input_transcript.delta',
          kind: OpenAiRealtimeTranscriptKind.source,
          delta: 'Hola equipo.',
        ),
      );

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for speech'), findsNothing);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Hola equipo.'), findsOneWidget);
    expect(find.text('Translation'), findsOneWidget);
    expect(find.text('Hello team.'), findsOneWidget);
  });

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
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        aiChatGateway: aiChatGateway,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: _FakeRealtimeTranslationGateway(),
      ),
    );

    await tester.tap(find.text('Start new meeting'));
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

  testWidgets('opens amber paused read-aloud and export surfaces', (
    tester,
  ) async {
    final repository = _testRepository();
    final meetingSummaryGateway = _FakeMeetingSummaryGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        meetingSummaryGateway: meetingSummaryGateway,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: _FakeRealtimeTranslationGateway(),
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause Read Aloud'));
    await tester.pumpAndSettle();

    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);
    expect(find.text('Speaking'), findsOneWidget);
    expect(find.text('Speaker Active'), findsOneWidget);
    expect(find.text('Read aloud is paused'), findsOneWidget);
    expect(find.text('Resume Read Aloud'), findsOneWidget);
    expect(find.text('Waiting for speech'), findsOneWidget);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate export'));
    await tester.pumpAndSettle();

    expect(find.text('Generate export'), findsWidgets);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Both'), findsOneWidget);
    expect(find.text('Open generated exports'), findsOneWidget);
    expect(
      find.textContaining('stay encrypted on this device'),
      findsOneWidget,
    );
    expect(find.byTooltip('Add recipient'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('recipient@example.com'), findsNothing);

    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.textContaining('direct OpenAI request'), findsOneWidget);
    final generateButton = find.widgetWithText(FilledButton, 'Generate export');
    await tester.ensureVisible(generateButton);
    await tester.tap(generateButton);
    await tester.pumpAndSettle();

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.meetings.single.summaryAvailable, isTrue);
    expect(snapshot.meetings.single.generatedExports, hasLength(1));
    expect(meetingSummaryGateway.requests, hasLength(1));
    expect(snapshot.meetings.single.generatedExports.single.type, 'summary');
    expect(
      snapshot.meetings.single.generatedExports.single.body,
      contains('Executive Summary'),
    );
    expect(
      snapshot.meetings.single.generatedExports.single.body,
      isNot(contains('Transcript\n\n[')),
    );
    expect(find.text('Generated export is ready.'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Copy generated export'), findsOneWidget);
    expect(find.textContaining('Executive Summary'), findsOneWidget);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            expect('${call.arguments}', isNot(contains('placeholder')));
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final copyButton = find.widgetWithText(
      FilledButton,
      'Copy generated export',
    );
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(find.text('Generated export copied.'), findsOneWidget);
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

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();

    expect(find.text('Microphone access needed'), findsOneWidget);
    expect(find.text('Try microphone permission again'), findsOneWidget);
    expect(
      find.text(
        'No audio is captured before microphone permission is granted.',
      ),
      findsOneWidget,
    );
    expect(find.text('Auto-detect Spanish -> English'), findsNothing);
  });

  testWidgets('persists and deletes local meeting history', (tester) async {
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

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    expect((await repository.loadSnapshot()).meetings, hasLength(1));

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meeting history'));
    await tester.pumpAndSettle();

    expect(find.text('Live translation meeting'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Live translation meeting'));
    await tester.pumpAndSettle();

    expect((await repository.loadSnapshot()).meetings, isEmpty);
    expect(find.text('Start new meeting'), findsOneWidget);
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

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();

    final initialMeeting = (await repository.loadSnapshot()).meetings.single;

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meeting history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Live translation meeting'));
    await tester.pumpAndSettle();

    final continuedMeeting = (await repository.loadSnapshot()).meetings.single;
    expect(continuedMeeting.id, initialMeeting.id);
    expect(continuedMeeting.transcriptCount, initialMeeting.transcriptCount);
    expect(continuedMeeting.createdAt, initialMeeting.createdAt);
    expect(
      continuedMeeting.updatedAt.isAfter(initialMeeting.updatedAt),
      isTrue,
    );
    expect(find.text('Live translation meeting'), findsNothing);
    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);
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

class _FakeRealtimeTranslationSession implements RealtimeTranslationSession {
  final _events = StreamController<OpenAiRealtimeEvent>.broadcast(sync: true);

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
    unawaited(_events.close());
  }

  @override
  Future<void> closeImmediately() async {
    unawaited(_events.close());
  }

  @override
  void sendSessionUpdate() {}
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

class _FakeMeetingSummaryGateway implements MeetingSummaryGateway {
  final List<MeetingSummaryRequest> requests = [];

  @override
  Future<MeetingSummaryResult> generate({
    required MeetingSummaryRequest request,
    required String credential,
  }) async {
    requests.add(request);
    expect(credential, 'placeholder-local-openai-credential');
    return MeetingSummaryResult(
      text:
          'Executive Summary\nThe meeting aligned on the project timeline.\n\n'
          'Critical Talking Points And Outcomes\n- Review the deliverables.\n\n'
          'Actions\n- Share the draft plan.',
      generatedAt: DateTime(2026, 5, 24, 2, 45),
      modelIntent: request.model,
      transcriptEntryCount: request.transcriptEntryCount,
    );
  }
}
