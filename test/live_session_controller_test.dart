import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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

      expect(controller.state.phase, LiveSessionPhase.listening);
      expect(controller.state.isMicrophoneCaptureOpen, isTrue);
      expect(controller.state.isRealtimeSessionOpen, isTrue);
    },
  );

  test('denied permission keeps all live resources closed', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.denied,
      ),
    );

    await controller.startMeeting();

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

  test('background lifecycle pauses all live resources', () async {
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
    );

    await controller.startMeeting();
    controller.handleAppLifecycleState(AppLifecycleState.paused);

    expect(controller.state.phase, LiveSessionPhase.readAloudPaused);
    expect(controller.state.isMicrophoneCaptureOpen, isFalse);
    expect(controller.state.isRealtimeSessionOpen, isFalse);
    expect(controller.state.isPlaybackQueueOpen, isFalse);
  });

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
