import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_credential_store.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';
import 'package:realtime_translate_mobile/src/session/live_session_controller.dart';
import 'package:realtime_translate_mobile/src/session/microphone_capture.dart';
import 'package:realtime_translate_mobile/src/session/microphone_permission.dart';
import 'package:realtime_translate_mobile/src/session/realtime_translation_coordinator.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';

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
      harness.realtimeGateway.credentials.single,
      'placeholder-credential',
    );
    expect(harness.realtimeGateway.session.appendedChunks.single, [0, 1, 2, 3]);
  });

  test('stop closes capture, realtime, and controller resources', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
    );

    await harness.coordinator.start(config: config);
    await harness.coordinator.stop();

    expect(harness.captureGateway.stopCount, greaterThanOrEqualTo(1));
    expect(harness.captureGateway.isCapturing, isFalse);
    expect(harness.realtimeGateway.session.closeGracefullyCount, 1);
    expect(harness.controller.state.phase, LiveSessionPhase.localSetup);
    expect(harness.controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(harness.controller.state.isRealtimeSessionOpen, isFalse);
  });

  test('realtime failure closes capture while reconnecting', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
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
  });

  test('background lifecycle closes capture and realtime resources', () async {
    final harness = await _Harness.create(
      permissionStatus: MicrophonePermissionStatus.granted,
    );

    await harness.coordinator.start(config: config);
    harness.coordinator.handleAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.state.phase, LiveSessionPhase.readAloudPaused);
    expect(harness.controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(harness.captureGateway.isCapturing, isFalse);
    expect(harness.realtimeGateway.session.closeImmediatelyCount, 1);
  });
}

class _Harness {
  _Harness._({required MicrophonePermissionStatus permissionStatus})
    : permissionGateway = _FakePermissionGateway(permissionStatus),
      repository = LocalMeetingRepository(store: MemoryEncryptedLocalStore()),
      captureGateway = _FakeMicrophoneCaptureGateway(),
      realtimeGateway = _FakeRealtimeTranslationGateway() {
    controller = LiveSessionController(permissionGateway: permissionGateway);
    credentialStore = OpenAiCredentialStore(repository: repository);
    coordinator = LiveRealtimeTranslationCoordinator(
      sessionController: controller,
      credentialStore: credentialStore,
      captureGateway: captureGateway,
      realtimeGateway: realtimeGateway,
    );
  }

  static Future<_Harness> create({
    required MicrophonePermissionStatus permissionStatus,
    bool seedCredential = true,
  }) async {
    final harness = _Harness._(permissionStatus: permissionStatus);
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
  MicrophoneCaptureConfig? lastConfig;

  @override
  Stream<MicrophonePcm16Chunk> get chunks => _chunks.stream;

  @override
  bool get isCapturing => _isCapturing;

  @override
  Future<void> start(MicrophoneCaptureConfig config) async {
    startCount += 1;
    lastConfig = config;
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

class _FakeRealtimeTranslationGateway implements RealtimeTranslationGateway {
  final _FakeRealtimeTranslationSession session =
      _FakeRealtimeTranslationSession();
  final List<OpenAiRealtimeTranslationConfig> configs = [];
  final List<String> credentials = [];
  int connectCount = 0;

  @override
  Future<RealtimeTranslationSession> connect({
    required OpenAiRealtimeTranslationConfig config,
    required String credential,
  }) async {
    connectCount += 1;
    configs.add(config);
    credentials.add(credential);
    return session;
  }
}

class _FakeRealtimeTranslationSession implements RealtimeTranslationSession {
  final StreamController<OpenAiRealtimeEvent> _events =
      StreamController<OpenAiRealtimeEvent>.broadcast();
  final List<List<int>> appendedChunks = [];
  int closeGracefullyCount = 0;
  int closeImmediatelyCount = 0;

  @override
  Stream<OpenAiRealtimeEvent> get events => _events.stream;

  @override
  void appendPcm16Audio(List<int> pcm16Audio) {
    appendedChunks.add(List<int>.from(pcm16Audio));
  }

  @override
  Future<void> closeGracefully() async {
    closeGracefullyCount += 1;
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
