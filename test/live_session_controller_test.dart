import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/diagnostics/privacy_safe_diagnostics.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_resilience.dart';
import 'package:realtime_translate_mobile/src/session/live_session_controller.dart';
import 'package:realtime_translate_mobile/src/session/microphone_permission.dart';

void main() {
  test(
    'does not open capture while microphone permission is pending',
    () async {
      final gateway = _DeferredPermissionGateway();
      final controller = LiveSessionController(permissionGateway: gateway);

      final start = controller.startMeeting();

      expect(
        controller.state.phase,
        LiveSessionPhase.requestingMicrophonePermission,
      );
      expect(controller.state.isMicrophoneCaptureOpen, isFalse);
      expect(controller.state.isRealtimeSessionOpen, isFalse);

      gateway.complete(MicrophonePermissionStatus.granted);
      await start;

      expect(controller.state.phase, LiveSessionPhase.connecting);
      expect(controller.state.isMicrophoneCaptureOpen, isFalse);
      expect(controller.state.isRealtimeSessionOpen, isFalse);
    },
  );

  test('denied permission keeps all live resources closed', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.denied,
      ),
    );

    await controller.startMeeting();
    controller.markRealtimeStarted();

    expect(controller.state.phase, LiveSessionPhase.microphoneDenied);
    expect(controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(controller.state.isRealtimeSessionOpen, isFalse);
    expect(controller.state.isPlaybackQueueOpen, isFalse);
  });

  test('permanently denied permission surfaces settings path', () async {
    final gateway = _FixedPermissionGateway(
      MicrophonePermissionStatus.permanentlyDenied,
    );
    final controller = LiveSessionController(permissionGateway: gateway);

    await controller.startMeeting();
    controller.markRealtimeStarted();
    await controller.openPermissionSettings();

    expect(
      controller.state.phase,
      LiveSessionPhase.microphonePermanentlyDenied,
    );
    expect(gateway.settingsOpenCount, 1);
  });

  test('stop closes capture, realtime session, and playback queue', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );

    await controller.startMeeting();
    controller.stopMeeting();

    expect(controller.state.phase, LiveSessionPhase.localSetup);
    expect(controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(controller.state.isRealtimeSessionOpen, isFalse);
    expect(controller.state.isPlaybackQueueOpen, isFalse);
  });

  test('background lifecycle pauses listening resources', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );

    await controller.startMeeting();
    controller.markRealtimeStarted();
    controller.handleAppLifecycleState(AppLifecycleState.paused);

    expect(controller.state.phase, LiveSessionPhase.listeningPaused);
    expect(controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(controller.state.isRealtimeSessionOpen, isFalse);
    expect(controller.state.isPlaybackQueueOpen, isFalse);
  });

  test(
    'manual listening pause keeps transcript state but closes resources',
    () async {
      final controller = LiveSessionController(
        permissionGateway: _FixedPermissionGateway(
          MicrophonePermissionStatus.granted,
        ),
      );

      await controller.startMeeting();
      controller.markRealtimeStarted();
      controller.pauseListening();

      expect(controller.state.phase, LiveSessionPhase.listeningPaused);
      expect(controller.state.isMicrophoneCaptureOpen, isFalse);
      expect(controller.state.isRealtimeSessionOpen, isFalse);
      expect(controller.state.isPlaybackQueueOpen, isFalse);

      controller.resumeListening();

      expect(controller.state.phase, LiveSessionPhase.listening);
      expect(controller.state.isMicrophoneCaptureOpen, isTrue);
      expect(controller.state.isRealtimeSessionOpen, isTrue);
    },
  );

  test('manual read-aloud pause is not converted into reconnecting', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );

    await controller.startMeeting();
    controller.enterSpeakingPaused();
    controller.handleAppLifecycleState(AppLifecycleState.resumed);

    expect(controller.state.phase, LiveSessionPhase.readAloudPaused);
    expect(controller.state.isRealtimeSessionOpen, isTrue);
  });

  test('audio route changes are tracked deterministically', () {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );

    controller.handleAudioRouteChange(LiveAudioRoute.headphones);

    expect(controller.state.audioRoute, LiveAudioRoute.headphones);
  });

  test('credential invalid state keeps live resources closed', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );

    await controller.startMeeting();
    controller.markCredentialInvalid();

    expect(controller.state.phase, LiveSessionPhase.credentialInvalid);
    expect(controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(controller.state.isRealtimeSessionOpen, isFalse);
    expect(controller.state.isPlaybackQueueOpen, isFalse);
  });

  test(
    'retryable realtime failure enters reconnecting with closed resources',
    () async {
      final sink = MemoryPrivacySafeDiagnosticsSink();
      final controller = LiveSessionController(
        permissionGateway: _FixedPermissionGateway(
          MicrophonePermissionStatus.granted,
        ),
        diagnostics: PrivacySafeDiagnostics(sink: sink),
      );
      const policy = OpenAiRealtimeReconnectPolicy(
        maxAttempts: 2,
        initialDelay: Duration(seconds: 1),
        jitterRatio: 0.2,
      );

      await controller.startMeeting();
      final decision = policy.plan(
        failure: OpenAiRealtimeFailure.sessionClosed(),
        retryAttempt: 1,
        jitterSample: 1,
      );
      controller.applyRealtimeRecoveryDecision(decision);

      expect(controller.state.phase, LiveSessionPhase.reconnecting);
      expect(controller.state.isMicrophoneCaptureOpen, isFalse);
      expect(controller.state.isRealtimeSessionOpen, isFalse);
      expect(controller.state.isPlaybackQueueOpen, isFalse);
      expect(controller.state.realtimeRetryAttempt, 1);
      expect(
        controller.state.realtimeReconnectDelay,
        const Duration(milliseconds: 1200),
      );
      expect(
        sink.records.map((record) => record.event),
        contains('live_session.realtime_recovery_decision'),
      );
      expect(_serializeAll(sink.records), isNot(contains('sk-')));
      expect(_serializeAll(sink.records), isNot(contains('transcript')));
    },
  );

  test('realtime recovery can return to listening after reconnect', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );
    const policy = OpenAiRealtimeReconnectPolicy();

    await controller.startMeeting();
    controller.applyRealtimeRecoveryDecision(
      policy.plan(
        failure: OpenAiRealtimeFailure.sessionClosed(),
        retryAttempt: 1,
      ),
    );
    controller.markRealtimeRecovered();

    expect(controller.state.phase, LiveSessionPhase.listening);
    expect(controller.state.isMicrophoneCaptureOpen, isTrue);
    expect(controller.state.isRealtimeSessionOpen, isTrue);
    expect(controller.state.isPlaybackQueueOpen, isTrue);
    expect(controller.state.realtimeRetryAttempt, 0);
    expect(controller.state.realtimeReconnectDelay, Duration.zero);
  });

  test('credential and exhausted network decisions fail closed', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );
    const policy = OpenAiRealtimeReconnectPolicy(maxAttempts: 1);

    await controller.startMeeting();
    controller.applyRealtimeRecoveryDecision(
      policy.plan(
        failure: OpenAiRealtimeFailure.classifyCode('invalid_api_key'),
        retryAttempt: 1,
      ),
    );

    expect(controller.state.phase, LiveSessionPhase.credentialInvalid);
    expect(
      controller.state.realtimeRecoveryAction,
      OpenAiRealtimeRecoveryAction.credentialInvalid,
    );
    expect(controller.state.isRealtimeSessionOpen, isFalse);

    await controller.startMeeting();
    expect(controller.state.realtimeRecoveryAction, isNull);
    controller.applyRealtimeRecoveryDecision(
      policy.plan(
        failure: OpenAiRealtimeFailure.sessionClosed(),
        retryAttempt: 2,
      ),
    );

    expect(controller.state.phase, LiveSessionPhase.offline);
    expect(
      controller.state.realtimeRecoveryAction,
      OpenAiRealtimeRecoveryAction.offline,
    );
    expect(controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(controller.state.isRealtimeSessionOpen, isFalse);
    expect(controller.state.isPlaybackQueueOpen, isFalse);
  });

  test('credential expiry decision preserves sanitized failure kind', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );
    const policy = OpenAiRealtimeReconnectPolicy(maxAttempts: 1);

    await controller.startMeeting();
    controller.applyRealtimeRecoveryDecision(
      policy.plan(
        failure: OpenAiRealtimeFailure.classifyCode('session_expired'),
        retryAttempt: 1,
      ),
    );

    expect(controller.state.phase, LiveSessionPhase.credentialInvalid);
    expect(
      controller.state.realtimeRecoveryAction,
      OpenAiRealtimeRecoveryAction.credentialInvalid,
    );
    expect(
      controller.state.realtimeFailureKind,
      OpenAiRealtimeFailureKind.credentialExpired,
    );
    expect(
      controller.state.notice,
      'OpenAI credential expired or was rejected. Update the credential stored on this device.',
    );
    expect(controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(controller.state.isRealtimeSessionOpen, isFalse);
    expect(controller.state.isPlaybackQueueOpen, isFalse);
  });

  test('rate-limit decisions use specific retry and exhausted notices', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );
    const policy = OpenAiRealtimeReconnectPolicy(
      maxAttempts: 1,
      initialDelay: Duration(seconds: 1),
      jitterRatio: 0,
    );

    await controller.startMeeting();
    controller.applyRealtimeRecoveryDecision(
      policy.plan(
        failure: OpenAiRealtimeFailure.classifyCode('rate_limit_exceeded'),
        retryAttempt: 1,
      ),
    );

    expect(controller.state.phase, LiveSessionPhase.reconnecting);
    expect(
      controller.state.realtimeFailureKind,
      OpenAiRealtimeFailureKind.rateLimited,
    );
    expect(
      controller.state.notice,
      'OpenAI is rate limiting this live session. Retrying shortly.',
    );

    controller.applyRealtimeRecoveryDecision(
      policy.plan(
        failure: OpenAiRealtimeFailure.classifyCode('rate_limit_exceeded'),
        retryAttempt: 2,
      ),
    );

    expect(controller.state.phase, LiveSessionPhase.error);
    expect(
      controller.state.realtimeRecoveryAction,
      OpenAiRealtimeRecoveryAction.fatalError,
    );
    expect(
      controller.state.realtimeFailureKind,
      OpenAiRealtimeFailureKind.rateLimited,
    );
    expect(
      controller.state.notice,
      'OpenAI rate limits persisted after retries. Restart when quota is available.',
    );
    expect(controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(controller.state.isRealtimeSessionOpen, isFalse);
    expect(controller.state.isPlaybackQueueOpen, isFalse);
  });

  test('realtime recovery diagnostics redact unsafe error codes', () async {
    final sink = MemoryPrivacySafeDiagnosticsSink();
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
      diagnostics: PrivacySafeDiagnostics(sink: sink),
    );
    final fakeApiKey = 'sk-${List.filled(24, 'a').join()}';

    await controller.startMeeting();
    controller.applyRealtimeRecoveryDecision(
      OpenAiRealtimeReconnectDecision(
        action: OpenAiRealtimeRecoveryAction.fatalError,
        failure: OpenAiRealtimeFailure(
          kind: OpenAiRealtimeFailureKind.fatal,
          diagnosticCode: fakeApiKey,
        ),
        retryAttempt: 1,
        delay: Duration.zero,
      ),
    );

    final serialized = _serializeAll(sink.records);
    expect(serialized, isNot(contains(fakeApiKey)));
    expect(serialized, contains(PrivacySafeDiagnostics.redacted));
  });
}

String _serializeAll(Iterable<PrivacySafeDiagnosticRecord> records) {
  return records
      .map((record) => '${record.event} ${record.severity} ${record.fields}')
      .join('\n');
}

class _FixedPermissionGateway implements MicrophonePermissionGateway {
  _FixedPermissionGateway(this.status);

  final MicrophonePermissionStatus status;
  int settingsOpenCount = 0;

  @override
  Future<MicrophonePermissionStatus> checkStatus() async => status;

  @override
  Future<void> openAppSettings() async {
    settingsOpenCount += 1;
  }

  @override
  Future<MicrophonePermissionStatus> request() async => status;
}

class _DeferredPermissionGateway implements MicrophonePermissionGateway {
  final Completer<MicrophonePermissionStatus> _request = Completer();

  void complete(MicrophonePermissionStatus status) {
    _request.complete(status);
  }

  @override
  Future<MicrophonePermissionStatus> checkStatus() => _request.future;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<MicrophonePermissionStatus> request() => _request.future;
}
