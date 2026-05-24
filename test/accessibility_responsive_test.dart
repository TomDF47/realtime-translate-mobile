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

void main() {
  testWidgets('core controls expose semantic labels and tap actions', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      final repository = _testRepository();
      await _seedCredential(repository);
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

      expect(
        tester.getSemantics(
          find.widgetWithText(FilledButton, 'Start new meeting'),
        ),
        matchesSemantics(
          label: 'Start new meeting',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(
          find.widgetWithText(FilledButton, 'Open meeting history'),
        ),
        matchesSemantics(
          label: 'Open meeting history',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.widgetWithText(FilledButton, 'OpenAI setup')),
        matchesSemantics(
          label: 'OpenAI setup',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.text('Start new meeting'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open menu'), findsOneWidget);
      expect(find.byTooltip('Open AI chat'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('From language selector')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('To language selector')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Translate Text on')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Read Aloud on')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Headphones Active active')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Stop listening'), findsOneWidget);
      expect(find.bySemanticsLabel('Pause read aloud'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Switch translation direction'),
        findsWidgets,
      );

      await tester.tap(find.byTooltip('Open AI chat'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Close AI chat'), findsOneWidget);
      expect(find.byTooltip('Send AI chat prompt'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'What changed?');
      await tester.tap(find.byTooltip('Send AI chat prompt'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Helpful'), findsOneWidget);
      expect(find.byTooltip('Not helpful'), findsOneWidget);
      expect(
        find.text('Responses are based on this local meeting only.'),
        findsOneWidget,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('large text and compact viewport keep core surfaces usable', (
    tester,
  ) async {
    _configureCompactLargeTextViewport(tester);

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
    await tester.pumpAndSettle();
    _expectNoFlutterOverflow(tester);

    expect(find.text('Live Translate'), findsOneWidget);
    await tester.ensureVisible(find.text('Start new meeting'));
    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    _expectNoFlutterOverflow(tester);

    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);
    expect(find.text('Jump to Live'), findsOneWidget);

    await tester.tap(find.byTooltip('Open AI chat'));
    await tester.pumpAndSettle();
    _expectNoFlutterOverflow(tester);
    expect(find.text('AI Chat'), findsOneWidget);
    expect(find.text('This meeting'), findsOneWidget);
    await tester.tap(find.byTooltip('Close AI chat'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Switch').first);
    await tester.pumpAndSettle();
    _expectNoFlutterOverflow(tester);
    expect(find.text('English -> Japanese'), findsOneWidget);
    expect(find.text('Resume Read Aloud'), findsOneWidget);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export meeting'));
    await tester.pumpAndSettle();
    _expectNoFlutterOverflow(tester);

    expect(find.text('Email export'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Both'), findsOneWidget);
    expect(find.text('recipient@example.com'), findsOneWidget);
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
