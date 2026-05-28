import 'package:flutter/widgets.dart';

import '../diagnostics/privacy_safe_diagnostics.dart';
import '../openai/openai_realtime_resilience.dart';
import 'microphone_permission.dart';

enum LiveSessionPhase {
  localSetup,
  requestingMicrophonePermission,
  connecting,
  listening,
  listeningPaused,
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
    required this.realtimeRetryAttempt,
    required this.realtimeReconnectDelay,
    this.realtimeRecoveryAction,
    this.realtimeFailureKind,
    this.notice,
  });

  const LiveSessionState.initial()
    : phase = LiveSessionPhase.localSetup,
      microphonePermission = MicrophonePermissionStatus.unknown,
      audioRoute = LiveAudioRoute.unknown,
      isMicrophoneCaptureOpen = false,
      isRealtimeSessionOpen = false,
      isPlaybackQueueOpen = false,
      realtimeRetryAttempt = 0,
      realtimeReconnectDelay = Duration.zero,
      realtimeRecoveryAction = null,
      realtimeFailureKind = null,
      notice = null;

  final LiveSessionPhase phase;
  final MicrophonePermissionStatus microphonePermission;
  final LiveAudioRoute audioRoute;
  final bool isMicrophoneCaptureOpen;
  final bool isRealtimeSessionOpen;
  final bool isPlaybackQueueOpen;
  final int realtimeRetryAttempt;
  final Duration realtimeReconnectDelay;
  final OpenAiRealtimeRecoveryAction? realtimeRecoveryAction;
  final OpenAiRealtimeFailureKind? realtimeFailureKind;
  final String? notice;

  LiveSessionState copyWith({
    LiveSessionPhase? phase,
    MicrophonePermissionStatus? microphonePermission,
    LiveAudioRoute? audioRoute,
    bool? isMicrophoneCaptureOpen,
    bool? isRealtimeSessionOpen,
    bool? isPlaybackQueueOpen,
    int? realtimeRetryAttempt,
    Duration? realtimeReconnectDelay,
    OpenAiRealtimeRecoveryAction? realtimeRecoveryAction,
    bool clearRealtimeRecoveryAction = false,
    OpenAiRealtimeFailureKind? realtimeFailureKind,
    bool clearRealtimeFailureKind = false,
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
      realtimeRetryAttempt: realtimeRetryAttempt ?? this.realtimeRetryAttempt,
      realtimeReconnectDelay:
          realtimeReconnectDelay ?? this.realtimeReconnectDelay,
      realtimeRecoveryAction: clearRealtimeRecoveryAction
          ? null
          : realtimeRecoveryAction ?? this.realtimeRecoveryAction,
      realtimeFailureKind: clearRealtimeFailureKind
          ? null
          : realtimeFailureKind ?? this.realtimeFailureKind,
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
        realtimeRetryAttempt: 0,
        realtimeReconnectDelay: Duration.zero,
        clearRealtimeRecoveryAction: true,
        clearRealtimeFailureKind: true,
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
          realtimeRetryAttempt: 0,
          realtimeReconnectDelay: Duration.zero,
          clearRealtimeRecoveryAction: true,
          clearRealtimeFailureKind: true,
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
        realtimeRetryAttempt: 0,
        realtimeReconnectDelay: Duration.zero,
        clearRealtimeRecoveryAction: true,
        clearRealtimeFailureKind: true,
        notice: 'Preparing the phone-local live session.',
      ),
    );

    // The realtime coordinator marks the session as listening only after the
    // WebSocket, playback queue, and microphone capture have opened.
  }

  Future<void> retryMicrophonePermission() {
    return startMeeting();
  }

  Future<void> openPermissionSettings() {
    return permissionGateway.openAppSettings();
  }

  void markCredentialInvalid({
    String? notice,
    OpenAiRealtimeFailureKind failureKind =
        OpenAiRealtimeFailureKind.credentialRejected,
  }) {
    _pausedByLifecycle = false;
    _setState(
      _state.copyWith(
        phase: LiveSessionPhase.credentialInvalid,
        isMicrophoneCaptureOpen: false,
        isRealtimeSessionOpen: false,
        isPlaybackQueueOpen: false,
        realtimeRetryAttempt: 0,
        realtimeReconnectDelay: Duration.zero,
        realtimeRecoveryAction: OpenAiRealtimeRecoveryAction.credentialInvalid,
        realtimeFailureKind: failureKind,
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
          realtimeRetryAttempt: 0,
          realtimeReconnectDelay: Duration.zero,
          clearRealtimeRecoveryAction: true,
          clearRealtimeFailureKind: true,
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
        realtimeRetryAttempt: 0,
        realtimeReconnectDelay: Duration.zero,
        clearRealtimeRecoveryAction: true,
        clearRealtimeFailureKind: true,
        clearNotice: true,
      ),
    );
  }

  void pauseListening() {
    if (!_state.microphonePermission.isGranted) {
      return;
    }

    _pausedByLifecycle = false;
    _setState(
      _state.copyWith(
        phase: LiveSessionPhase.listeningPaused,
        isMicrophoneCaptureOpen: false,
        isRealtimeSessionOpen: false,
        isPlaybackQueueOpen: false,
        realtimeRetryAttempt: 0,
        realtimeReconnectDelay: Duration.zero,
        clearRealtimeRecoveryAction: true,
        clearRealtimeFailureKind: true,
        notice:
            'Listening is paused. Microphone capture and OpenAI realtime are stopped until you resume.',
      ),
    );
  }

  void markRealtimeStarted() {
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
        realtimeRetryAttempt: 0,
        realtimeReconnectDelay: Duration.zero,
        clearRealtimeRecoveryAction: true,
        clearRealtimeFailureKind: true,
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
        realtimeRetryAttempt: 0,
        realtimeReconnectDelay: Duration.zero,
        clearRealtimeRecoveryAction: true,
        clearRealtimeFailureKind: true,
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
              phase: LiveSessionPhase.listeningPaused,
              isMicrophoneCaptureOpen: false,
              isRealtimeSessionOpen: false,
              isPlaybackQueueOpen: false,
              realtimeRetryAttempt: 0,
              realtimeReconnectDelay: Duration.zero,
              clearRealtimeRecoveryAction: true,
              clearRealtimeFailureKind: true,
              notice:
                  'Session paused while the app is not foregrounded. Resume when ready.',
            ),
          );
        }
      case AppLifecycleState.resumed:
        if (_pausedByLifecycle &&
            _state.phase == LiveSessionPhase.listeningPaused) {
          _pausedByLifecycle = false;
          _setState(
            _state.copyWith(
              phase: LiveSessionPhase.reconnecting,
              isMicrophoneCaptureOpen: false,
              isRealtimeSessionOpen: false,
              isPlaybackQueueOpen: false,
              realtimeRetryAttempt: 1,
              realtimeReconnectDelay: Duration.zero,
              realtimeRecoveryAction:
                  OpenAiRealtimeRecoveryAction.reconnectAfterBackoff,
              realtimeFailureKind:
                  OpenAiRealtimeFailureKind.lifecycleInterrupted,
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

  void applyRealtimeRecoveryDecision(OpenAiRealtimeReconnectDecision decision) {
    _pausedByLifecycle = false;
    switch (decision.action) {
      case OpenAiRealtimeRecoveryAction.reconnectAfterBackoff:
        _recordRealtimeRecoveryDecision(
          decision,
          severity: DiagnosticSeverity.warning,
        );
        _setState(
          _state.copyWith(
            phase: LiveSessionPhase.reconnecting,
            isMicrophoneCaptureOpen: false,
            isRealtimeSessionOpen: false,
            isPlaybackQueueOpen: false,
            realtimeRetryAttempt: decision.retryAttempt,
            realtimeReconnectDelay: decision.delay,
            realtimeRecoveryAction: decision.action,
            realtimeFailureKind: decision.failure.kind,
            notice: decision.userFacingNotice,
          ),
        );
      case OpenAiRealtimeRecoveryAction.credentialInvalid:
        _recordRealtimeRecoveryDecision(
          decision,
          severity: DiagnosticSeverity.warning,
        );
        markCredentialInvalid(
          notice: decision.userFacingNotice,
          failureKind: decision.failure.kind,
        );
      case OpenAiRealtimeRecoveryAction.unsupportedLanguage:
        _recordRealtimeRecoveryDecision(
          decision,
          severity: DiagnosticSeverity.warning,
        );
        _setState(
          _state.copyWith(
            phase: LiveSessionPhase.error,
            isMicrophoneCaptureOpen: false,
            isRealtimeSessionOpen: false,
            isPlaybackQueueOpen: false,
            realtimeRetryAttempt: decision.retryAttempt,
            realtimeReconnectDelay: Duration.zero,
            realtimeRecoveryAction: decision.action,
            realtimeFailureKind: decision.failure.kind,
            notice: decision.userFacingNotice,
          ),
        );
      case OpenAiRealtimeRecoveryAction.offline:
        _recordRealtimeRecoveryDecision(
          decision,
          severity: DiagnosticSeverity.error,
        );
        _setState(
          _state.copyWith(
            phase: LiveSessionPhase.offline,
            isMicrophoneCaptureOpen: false,
            isRealtimeSessionOpen: false,
            isPlaybackQueueOpen: false,
            realtimeRetryAttempt: decision.retryAttempt,
            realtimeReconnectDelay: Duration.zero,
            realtimeRecoveryAction: decision.action,
            realtimeFailureKind: decision.failure.kind,
            notice: decision.userFacingNotice,
          ),
        );
      case OpenAiRealtimeRecoveryAction.fatalError:
        _recordRealtimeRecoveryDecision(
          decision,
          severity: DiagnosticSeverity.error,
        );
        _setState(
          _state.copyWith(
            phase: LiveSessionPhase.error,
            isMicrophoneCaptureOpen: false,
            isRealtimeSessionOpen: false,
            isPlaybackQueueOpen: false,
            realtimeRetryAttempt: decision.retryAttempt,
            realtimeReconnectDelay: Duration.zero,
            realtimeRecoveryAction: decision.action,
            realtimeFailureKind: decision.failure.kind,
            notice: decision.userFacingNotice,
          ),
        );
    }
  }

  void markRealtimeRecovered() {
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
        realtimeRetryAttempt: 0,
        realtimeReconnectDelay: Duration.zero,
        clearRealtimeRecoveryAction: true,
        clearRealtimeFailureKind: true,
        clearNotice: true,
      ),
    );
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
        'retryAttempt': value.realtimeRetryAttempt,
        'backoffMs': value.realtimeReconnectDelay.inMilliseconds,
      },
    );
    notifyListeners();
  }

  void _recordRealtimeRecoveryDecision(
    OpenAiRealtimeReconnectDecision decision, {
    required DiagnosticSeverity severity,
  }) {
    diagnostics.record(
      'live_session.realtime_recovery_decision',
      severity: severity,
      fields: {
        'operation': 'realtime.reconnect',
        'result': decision.action.name,
        'errorCode': decision.failure.diagnosticCode,
        'retryAttempt': decision.retryAttempt,
        'backoffMs': decision.delay.inMilliseconds,
      },
    );
  }
}
