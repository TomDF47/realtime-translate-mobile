import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:realtime_translate_mobile/main.dart';
import 'package:realtime_translate_mobile/src/openai/openai_ai_chat.dart';
import 'package:realtime_translate_mobile/src/openai/openai_credential_store.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';
import 'package:realtime_translate_mobile/src/session/microphone_capture.dart';
import 'package:realtime_translate_mobile/src/session/microphone_permission.dart';
import 'package:realtime_translate_mobile/src/session/translated_audio_playback.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';
import 'package:realtime_translate_mobile/src/storage/local_storage_models.dart';

void main() {
  testWidgets('core controls expose semantic labels and tap actions', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      final repository = _testRepository();
      await _seedCredentials(repository);
      await tester.pumpWidget(
        LiveTranslateApp(
          permissionGateway: _FakePermissionGateway.granted(),
          meetingRepository: repository,
          aiChatGateway: _FakeAiChatGateway(),
          microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
          translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
          realtimeTranslationGateway: _FakeRealtimeTranslationGateway(),
        ),
      );

      await _expectSetupButtonSemantics(
        tester,
        buttonText: 'Start interpreter',
        semanticLabel: 'Start interpreter',
      );
      await _expectSetupButtonSemantics(
        tester,
        buttonText: 'Open meeting history',
        semanticLabel: 'Open meeting history',
      );
      await _expectSetupButtonSemantics(
        tester,
        buttonText: 'Gemini live setup',
        semanticLabel: 'Gemini live setup',
      );
      await _expectSetupButtonSemantics(
        tester,
        buttonText: 'OpenAI chat & summary setup',
        semanticLabel: 'OpenAI chat and summary setup',
      );

      await tester.ensureVisible(find.text('Start interpreter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start interpreter'));
      await tester.pumpAndSettle();
      final activeMeeting = (await repository.loadSnapshot()).meetings.single;
      await _appendStoredTranscriptLine(repository, activeMeeting.id);

      expect(find.byTooltip('Open menu'), findsOneWidget);
      expect(find.byTooltip('Open AI chat'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('From language selector')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('To language selector')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Translate Text on')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Read Aloud on')), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Headphones Active active')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Stop listening'), findsOneWidget);
      expect(find.bySemanticsLabel('Pause read aloud'), findsNothing);
      expect(
        find.bySemanticsLabel('Switch translation direction'),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Open menu'));
      await tester.pumpAndSettle();

      expect(find.text('Meeting history'), findsOneWidget);
      expect(find.text('Generate export'), findsNothing);
      expect(find.text('Open generated exports'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('large text and compact viewport keep core surfaces usable', (
    tester,
  ) async {
    _configureCompactLargeTextViewport(tester);

    final repository = _testRepository();
    await _seedCredentials(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        microphoneCaptureGateway: _FakeMicrophoneCaptureGateway(),
        translatedAudioPlaybackGateway: NoopTranslatedAudioPlaybackGateway(),
        realtimeTranslationGateway: _FakeRealtimeTranslationGateway(),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterOverflow(tester);

    expect(find.text('Live Translate'), findsOneWidget);
    await tester.ensureVisible(find.text('Start interpreter'));
    await tester.tap(find.text('Start interpreter'));
    await tester.pumpAndSettle();
    _expectNoFlutterOverflow(tester);

    expect(find.text('Italian <-> English'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('From language selector')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('To language selector')),
      findsOneWidget,
    );
    expect(find.text('Waiting for speech'), findsOneWidget);

    expect(find.byTooltip('Open AI chat'), findsNothing);

    expect(find.text('Pause Read Aloud'), findsNothing);
    expect(find.text('Read aloud is paused'), findsNothing);
    expect(find.text('Resume Read Aloud'), findsNothing);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    _expectNoFlutterOverflow(tester);

    expect(find.text('Generate export'), findsNothing);
    expect(find.text('Transcript'), findsNothing);
    expect(find.text('Summary'), findsNothing);
    expect(find.text('Both'), findsNothing);
    expect(find.text('Open generated exports'), findsNothing);
    expect(find.textContaining('stay encrypted on this device'), findsNothing);
    expect(find.byTooltip('Add recipient'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('recipient@example.com'), findsNothing);
  });
}

Future<void> _expectSetupButtonSemantics(
  WidgetTester tester, {
  required String buttonText,
  required String semanticLabel,
}) async {
  final finder = find.widgetWithText(FilledButton, buttonText);

  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();

  expect(
    tester.getSemantics(finder),
    matchesSemantics(label: semanticLabel, isButton: true, hasTapAction: true),
  );
}

LocalMeetingRepository _testRepository() {
  return LocalMeetingRepository(store: MemoryEncryptedLocalStore());
}

Future<void> _seedCredentials(LocalMeetingRepository repository) async {
  await OpenAiCredentialStore.gemini(
    repository: repository,
  ).saveUserProvidedCredential('placeholder-local-gemini-credential');
  await OpenAiCredentialStore(
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
      playbackState: 'playable',
    ),
  );
}

void _configureCompactLargeTextViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390, 844);
  tester.binding.platformDispatcher.textScaleFactorTestValue = 1.3;

  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
}

void _expectNoFlutterOverflow(WidgetTester tester) {
  final exception = tester.takeException();
  expect(exception, isNull);
}

class _FakePermissionGateway implements MicrophonePermissionGateway {
  _FakePermissionGateway(this._status);

  _FakePermissionGateway.granted() : this(MicrophonePermissionStatus.granted);

  final MicrophonePermissionStatus _status;

  @override
  Future<MicrophonePermissionStatus> checkStatus() async => _status;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<MicrophonePermissionStatus> request() async => _status;
}

class _FakeMicrophoneCaptureGateway implements MicrophoneCaptureGateway {
  @override
  Stream<MicrophonePcm16Chunk> get chunks => const Stream.empty();

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
  @override
  Future<RealtimeTranslationSession> connect({
    required OpenAiRealtimeTranslationConfig config,
    required String credential,
  }) async {
    return _FakeRealtimeTranslationSession();
  }
}

class _FakeRealtimeTranslationSession implements RealtimeTranslationSession {
  @override
  Stream<OpenAiRealtimeEvent> get events => const Stream.empty();

  @override
  void appendPcm16Audio(List<int> pcm16Audio) {}

  @override
  void commitInputAudioBuffer() {}

  @override
  void createResponse() {}

  @override
  Future<void> closeGracefully() async {}

  @override
  Future<void> closeImmediately() async {}

  @override
  void sendSessionUpdate() {}
}

class _FakeAiChatGateway implements AiChatGateway {
  @override
  Future<AiChatAnswer> ask({
    required AiChatRequest request,
    required String credential,
  }) async {
    return AiChatAnswer(
      text: 'The local transcript contains a timeline update (10:37 AM).',
      generatedAt: DateTime(2026, 5, 24, 2, 42),
    );
  }
}
