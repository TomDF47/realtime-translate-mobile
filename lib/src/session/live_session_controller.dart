import 'package:flutter/widgets.dart';

import '../diagnostics/privacy_safe_diagnostics.dart';
import 'microphone_permission.dart';

enum LiveSessionPhase {
  localSetup,
  requestingMicrophonePermission,
  connecting,
  listening,
  speaking,
  readAloudPaused,
  reconnecting,
  offline,
  credentialInvalid,
  error,
  microphoneDenied,
  microphonePermanentlyDenied,
}

extension LiveSessionPhaseLabels on LiveSessionPhase {
  bool get isActive {
    return switch (this) {
      LiveSessionPhase.listening ||
      LiveSessionPhase.speaking ||
      LiveSessionPhase.readAloudPaused ||
      LiveSessionPhase.reconnecting => true,
      _ => false,
    };
  }
}

enum LiveAudioRoute { unknown, speaker, headphones, bluetooth }

class LiveSessionState {
  const LiveSessionState({
    required this.phase,
    required this.microphonePermission,
    required this.audioRoute,
    required this.isMicrophoneCaptureOpen,
    required this.isRealtimeSessionOpen,
    required this.isPlaybackQueueOpen,
    this.notice,
  });

  const LiveSessionState.initial()
    : phase = LiveSessionPhase.localSetup,
      microphonePermission = MicrophonePermissionStatus.unknown,
      audioRoute = LiveAudioRoute.unknown,
      isMicrophoneCaptureOpen = false,
      isRealtimeSessionOpen = false,
      isPlaybackQueueOpen = false,
      notice = null;

  final LiveSessionPhase phase;
  final MicrophonePermissionStatus microphonePermission;
  final LiveAudioRoute audioRoute;
  final bool isMicrophoneCaptureOpen;
  final bool isRealtimeSessionOpen;
  final bool isPlaybackQueueOpen;
  final String? notice;

  LiveSessionState copyWith({
    LiveSessionPhase? phase,
    MicrophonePermissionStatus? microphonePermission,
    LiveAudioRoute? audioRoute,
    bool? isMicrophoneCaptureOpen,
    bool? isRealtimeSessionOpen,
    bool? isPlaybackQueueOpen,
    String? notice,
    bool clearNotice = false,
  }) {
    return LiveSessionState(
      phase: phase ?? this.phase,
      microphonePermission: microphonePermission ?? this.microphonePermission,
      audioRoute: audioRoute ?? this.audioRoute,
      isMicrophoneCaptureOpen:
          isMicrophoneCaptureOpen ?? this.isMicrophoneCaptureOpen,
      isRealtimeSessionOpen:
          isRealtimeSessionOpen ?? this.isRealtimeSessionOpen,
      isPlaybackQueueOpen: isPlaybackQueueOpen ?? this.isPlaybackQueueOpen,
      notice: clearNotice ? null : notice ?? this.notice,
    );
  }
}

class LiveSessionController extends ChangeNotifier {
  LiveSessionController({
    required this.permissionGateway,
    this.diagnostics = const PrivacySafeDiagnostics(),
  });

  final MicrophonePermissionGateway permissionGateway;
  final PrivacySafeDiagnostics diagnostics;

  LiveSessionState _state = const LiveSessionState.initial();
  bool _pausedByLifecycle = false;

  LiveSessionState get state => _state;

  Future<void> startMeeting() async {
    _setState(
      _state.copyWith(
        phase: LiveSessionPhase.requestingMicrophonePermission,
        isMicrophoneCaptureOpen: false,
        isRealtimeSessionOpen: false,
        isPlaybackQueueOpen: false,
        notice: 'Microphone access is required before live translation starts.',
      ),
    );

    final permission = await permissionGateway.request();
    if (!permission.isGranted) {
      _setState(
        _state.copyWith(
          phase: _permissionDeniedPhase(permission),
          microphonePermission: permission,
          isMicrophoneCaptureOpen: false,
          isRealtimeSessionOpen: false,
          isPlaybackQueueOpen: false,
          notice:
              'No audio is captured before microphone permission is granted.',
        ),
      );
      return;
    }

    _setState(
      _state.copyWith(
        phase: LiveSessionPhase.connecting,
        microphonePermission: permission,
        isMicrophoneCaptureOpen: false,
        isRealtimeSessionOpen: false,
        isPlaybackQueueOpen: false,
        notice: 'Preparing the phone-local live session.',
      ),
    );

    _setState(
      _state.copyWith(
        phase: LiveSessionPhase.listening,
        isMicrophoneCaptureOpen: true,
        isRealtimeSessionOpen: true,
        isPlaybackQueueOpen: true,
        clearNotice: true,
      ),
    );
  }

  Future<void> retryMicrophonePermission() {
    return startMeeting();
  }

  Future<void> openPermissionSettings() {
    return permissionGateway.openAppSettings();
  }

  void markCredentialInvalid({String? notice}) {
    _pausedByLifecycle = false;
    _setState(
      _state.copyWith(
        phase: LiveSessionPhase.credentialInvalid,
        isMicrophoneCaptureOpen: false,
        isRealtimeSessionOpen: false,
        isPlaybackQueueOpen: false,
        notice:
            notice ??
            'Add an OpenAI credential stored on this device before live translation starts.',
      ),
    );
  }

  void enterSpeakingPaused() {
    if (_state.microphonePermission.isGranted) {
      _pausedByLifecycle = false;
      _setState(
        _state.copyWith(
          phase: LiveSessionPhase.readAloudPaused,
          isMicrophoneCaptureOpen: true,
          isRealtimeSessionOpen: true,
          isPlaybackQueueOpen: false,
          notice:
              'Read-aloud playback is paused; transcript capture stays gated.',
        ),
      );
    }
  }

  void resumeListening() {
    if (!_state.microphonePermission.isGranted) {
      return;
    }

    _pausedByLifecycle = false;
    _setState(
      _state.copyWith(
        phase: LiveSessionPhase.listening,
        isMicrophoneCaptureOpen: true,
        isRealtimeSessionOpen: true,
        isPlaybackQueueOpen: true,
        clearNotice: true,
      ),
    );
  }

  void stopMeeting() {
    _pausedByLifecycle = false;
    _setState(
      _state.copyWith(
        phase: LiveSessionPhase.localSetup,
        isMicrophoneCaptureOpen: false,
        isRealtimeSessionOpen: false,
        isPlaybackQueueOpen: false,
        clearNotice: true,
      ),
    );
  }

  void handleAppLifecycleState(AppLifecycleState lifecycleState) {
    switch (lifecycleState) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_state.phase.isActive) {
          _pausedByLifecycle = true;
          _setState(
            _state.copyWith(
              phase: LiveSessionPhase.readAloudPaused,
              isMicrophoneCaptureOpen: false,
              isRealtimeSessionOpen: false,
              isPlaybackQueueOpen: false,
              notice:
                  'Session paused while the app is not foregrounded. Resume when ready.',
            ),
          );
        }
      case AppLifecycleState.resumed:
        if (_pausedByLifecycle &&
            _state.phase == LiveSessionPhase.readAloudPaused) {
          _pausedByLifecycle = false;
          _setState(
            _state.copyWith(
              phase: LiveSessionPhase.reconnecting,
              isMicrophoneCaptureOpen: false,
              isRealtimeSessionOpen: false,
              isPlaybackQueueOpen: false,
              notice: 'Ready to resume the direct live session.',
            ),
          );
        }
      case AppLifecycleState.detached:
        stopMeeting();
    }
  }

  void handleAudioRouteChange(LiveAudioRoute route) {
    _setState(_state.copyWith(audioRoute: route));
  }

  LiveSessionPhase _permissionDeniedPhase(
    MicrophonePermissionStatus permission,
  ) {
    return switch (permission) {
      MicrophonePermissionStatus.permanentlyDenied ||
      MicrophonePermissionStatus.restricted =>
        LiveSessionPhase.microphonePermanentlyDenied,
      _ => LiveSessionPhase.microphoneDenied,
    };
  }

  void _setState(LiveSessionState value) {
    final previous = _state;
    _state = value;
    diagnostics.info(
      'live_session.state_change',
      fields: {
        'previousPhase': previous.phase.name,
        'nextPhase': value.phase.name,
        'permissionStatus': value.microphonePermission.name,
        'audioRoute': value.audioRoute.name,
        'isMicrophoneCaptureOpen': value.isMicrophoneCaptureOpen,
        'isRealtimeSessionOpen': value.isRealtimeSessionOpen,
        'isPlaybackQueueOpen': value.isPlaybackQueueOpen,
      },
    );
    notifyListeners();
  }
}
