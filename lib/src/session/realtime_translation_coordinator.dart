import 'dart:async';

import 'package:flutter/widgets.dart';

import '../diagnostics/privacy_safe_diagnostics.dart';
import '../openai/openai_credential_store.dart';
import '../openai/openai_realtime_resilience.dart';
import '../openai/openai_realtime_translation.dart';
import 'live_session_controller.dart';
import 'microphone_capture.dart';
import 'realtime_transcript_committer.dart';

typedef LiveRealtimeReconnectDelay = Future<void> Function(Duration delay);

enum LiveRealtimeStartResult {
  started,
  missingCredential,
  permissionNotGranted,
  failed,
}

class LiveRealtimeTranslationCoordinator {
  LiveRealtimeTranslationCoordinator({
    required this.sessionController,
    required this.credentialStore,
    required this.captureGateway,
    required this.realtimeGateway,
    this.reconnectPolicy = const OpenAiRealtimeReconnectPolicy(),
    this.reconnectDelay = Future.delayed,
    this.diagnostics = const PrivacySafeDiagnostics(),
  });

  final LiveSessionController sessionController;
  final OpenAiCredentialStore credentialStore;
  final MicrophoneCaptureGateway captureGateway;
  final RealtimeTranslationGateway realtimeGateway;
  final OpenAiRealtimeReconnectPolicy reconnectPolicy;
  final LiveRealtimeReconnectDelay reconnectDelay;
  final PrivacySafeDiagnostics diagnostics;

  RealtimeTranslationSession? _realtimeSession;
  StreamSubscription<MicrophonePcm16Chunk>? _captureSubscription;
  StreamSubscription<OpenAiRealtimeEvent>? _realtimeSubscription;
  LiveRealtimeTranscriptCommitter? _transcriptCommitter;
  OpenAiRealtimeTranslationConfig? _activeConfig;
  LiveRealtimeTranscriptCommitTarget? _activeTranscriptCommitTarget;
  bool _closingIntentionally = false;
  bool _handlingFailure = false;
  bool _isDisposed = false;
  int _reconnectGeneration = 0;

  bool get isStreaming {
    return _realtimeSession != null && captureGateway.isCapturing;
  }

  Future<LiveRealtimeStartResult> start({
    required OpenAiRealtimeTranslationConfig config,
    LiveRealtimeTranscriptCommitTarget? transcriptCommitTarget,
  }) async {
    _isDisposed = false;
    _cancelPendingReconnect();
    _activeConfig = config;
    _activeTranscriptCommitTarget = transcriptCommitTarget;
    await _closeRealtimeResources(graceful: false, finishTranscript: true);

    final credential = await credentialStore.readCredentialForNetworkUse();
    if (credential == null || credential.isEmpty) {
      sessionController.markCredentialInvalid();
      return LiveRealtimeStartResult.missingCredential;
    }

    await sessionController.startMeeting();
    if (sessionController.state.phase != LiveSessionPhase.listening) {
      return LiveRealtimeStartResult.permissionNotGranted;
    }

    try {
      final realtimeSession = await realtimeGateway.connect(
        config: config,
        credential: credential,
      );
      _bindRealtimeSession(
        realtimeSession,
        transcriptCommitTarget: transcriptCommitTarget,
        resetTranscriptCommitter: true,
      );
      await captureGateway.start(
        MicrophoneCaptureConfig.openAiRealtime(
          sampleRateHz: config.inputAudioRate,
        ),
      );
      diagnostics.info(
        'live_realtime.streaming_started',
        fields: {
          'operation': 'realtime.streaming.start',
          'model': config.profile.model,
          'realtimeProfile': config.profile.name,
          'targetLanguage': config.targetLanguageCode,
          'result': 'started',
        },
      );
      return LiveRealtimeStartResult.started;
    } catch (error) {
      await _closeRealtimeResources(graceful: false, finishTranscript: true);
      sessionController.applyRealtimeRecoveryDecision(
        reconnectPolicy.plan(
          failure: OpenAiRealtimeFailure.fromSocketError(error),
          retryAttempt: sessionController.state.realtimeRetryAttempt + 1,
        ),
      );
      return LiveRealtimeStartResult.failed;
    }
  }

  void handleAppLifecycleState(AppLifecycleState lifecycleState) {
    sessionController.handleAppLifecycleState(lifecycleState);
    switch (lifecycleState) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _cancelPendingReconnect();
        unawaited(
          _closeRealtimeResources(graceful: false, finishTranscript: true),
        );
      case AppLifecycleState.resumed:
        break;
    }
  }

  Future<void> stop() async {
    _cancelPendingReconnect();
    _activeConfig = null;
    _activeTranscriptCommitTarget = null;
    await _closeRealtimeResources(graceful: true, finishTranscript: true);
    sessionController.stopMeeting();
  }

  void dispose() {
    _isDisposed = true;
    _cancelPendingReconnect();
    _activeConfig = null;
    _activeTranscriptCommitTarget = null;
    unawaited(_closeRealtimeResources(graceful: false, finishTranscript: true));
  }

  void _bindRealtimeSession(
    RealtimeTranslationSession realtimeSession, {
    required LiveRealtimeTranscriptCommitTarget? transcriptCommitTarget,
    required bool resetTranscriptCommitter,
  }) {
    _realtimeSession = realtimeSession;
    if (resetTranscriptCommitter) {
      _transcriptCommitter = transcriptCommitTarget == null
          ? null
          : LiveRealtimeTranscriptCommitter(transcriptCommitTarget);
    } else if (_transcriptCommitter == null && transcriptCommitTarget != null) {
      _transcriptCommitter = LiveRealtimeTranscriptCommitter(
        transcriptCommitTarget,
      );
    }
    _realtimeSubscription = realtimeSession.events.listen(
      _handleRealtimeEvent,
      onError: (error) {
        unawaited(
          _handleRealtimeFailure(
            OpenAiRealtimeFailure.fromSocketError(error),
            allowReconnect: true,
          ),
        );
      },
    );
    _captureSubscription = captureGateway.chunks.listen(
      (chunk) => realtimeSession.appendPcm16Audio(chunk.bytes),
      onError: (error) {
        unawaited(
          _handleRealtimeFailure(
            OpenAiRealtimeFailure(
              kind: OpenAiRealtimeFailureKind.fatal,
              diagnosticCode: error.runtimeType.toString(),
            ),
            allowReconnect: true,
          ),
        );
      },
    );
  }

  void _handleRealtimeEvent(OpenAiRealtimeEvent event) {
    if (_closingIntentionally) {
      return;
    }

    switch (event) {
      case OpenAiRealtimeTranscriptDelta():
        _commitTranscript(_transcriptCommitter?.commitDelta(event));
      case OpenAiRealtimeTranscriptCompleted():
        _commitTranscript(_transcriptCommitter?.commitCompleted(event));
      case OpenAiRealtimeError():
        unawaited(
          _handleRealtimeFailure(
            OpenAiRealtimeFailure.fromRealtimeError(event),
            allowReconnect: true,
          ),
        );
      case OpenAiRealtimeSessionClosed():
        unawaited(
          _handleRealtimeFailure(
            OpenAiRealtimeFailure.sessionClosed(),
            allowReconnect: true,
          ),
        );
      default:
        break;
    }
  }

  void _commitTranscript(Future<void>? commit) {
    if (commit == null) {
      return;
    }

    unawaited(
      commit.catchError((Object error, StackTrace stackTrace) {
        diagnostics.warning(
          'live_realtime.transcript_commit_failed',
          fields: {
            'operation': 'realtime.transcript.commit',
            'result': 'failed',
            'errorCode': error.runtimeType.toString(),
          },
        );
      }),
    );
  }

  Future<void> _handleRealtimeFailure(
    OpenAiRealtimeFailure failure, {
    required bool allowReconnect,
  }) async {
    if (_handlingFailure || _closingIntentionally) {
      return;
    }

    _handlingFailure = true;
    try {
      final decision = reconnectPolicy.plan(
        failure: failure,
        retryAttempt: sessionController.state.realtimeRetryAttempt + 1,
      );
      final shouldScheduleReconnect = allowReconnect && decision.shouldRetry;
      await _closeRealtimeResources(
        graceful: false,
        finishTranscript: !shouldScheduleReconnect,
      );
      sessionController.applyRealtimeRecoveryDecision(decision);
      if (shouldScheduleReconnect) {
        _scheduleReconnect(decision);
      }
    } finally {
      _handlingFailure = false;
    }
  }

  void _scheduleReconnect(OpenAiRealtimeReconnectDecision decision) {
    final config = _activeConfig;
    if (config == null || _isDisposed) {
      return;
    }

    final generation = ++_reconnectGeneration;
    final transcriptCommitTarget = _activeTranscriptCommitTarget;
    unawaited(
      _reconnectAfterBackoff(
        generation: generation,
        decision: decision,
        config: config,
        transcriptCommitTarget: transcriptCommitTarget,
      ),
    );
  }

  Future<void> _reconnectAfterBackoff({
    required int generation,
    required OpenAiRealtimeReconnectDecision decision,
    required OpenAiRealtimeTranslationConfig config,
    required LiveRealtimeTranscriptCommitTarget? transcriptCommitTarget,
  }) async {
    await reconnectDelay(decision.delay);
    if (_isDisposed || generation != _reconnectGeneration) {
      return;
    }

    try {
      final credential = await credentialStore.readCredentialForNetworkUse();
      if (credential == null || credential.isEmpty) {
        await _handleRealtimeFailure(
          const OpenAiRealtimeFailure(
            kind: OpenAiRealtimeFailureKind.credentialRejected,
            diagnosticCode: 'credential_missing',
          ),
          allowReconnect: false,
        );
        return;
      }

      final realtimeSession = await realtimeGateway.connect(
        config: config,
        credential: credential,
      );
      if (_isDisposed || generation != _reconnectGeneration) {
        await realtimeSession.closeImmediately();
        return;
      }

      _bindRealtimeSession(
        realtimeSession,
        transcriptCommitTarget: transcriptCommitTarget,
        resetTranscriptCommitter: false,
      );
      await captureGateway.start(
        MicrophoneCaptureConfig.openAiRealtime(
          sampleRateHz: config.inputAudioRate,
        ),
      );
      sessionController.markRealtimeRecovered();
      diagnostics.info(
        'live_realtime.reconnect_succeeded',
        fields: {
          'operation': 'realtime.reconnect',
          'model': config.profile.model,
          'realtimeProfile': config.profile.name,
          'targetLanguage': config.targetLanguageCode,
          'retryAttempt': decision.retryAttempt,
          'result': 'success',
        },
      );
    } catch (error) {
      if (_isDisposed || generation != _reconnectGeneration) {
        return;
      }
      await _handleRealtimeFailure(
        OpenAiRealtimeFailure.fromSocketError(error),
        allowReconnect: true,
      );
    }
  }

  void _cancelPendingReconnect() {
    _reconnectGeneration += 1;
  }

  Future<void> _closeRealtimeResources({
    required bool graceful,
    required bool finishTranscript,
  }) async {
    final realtimeSession = _realtimeSession;
    final realtimeSubscription = _realtimeSubscription;
    final captureSubscription = _captureSubscription;
    final transcriptCommitter = _transcriptCommitter;
    _realtimeSession = null;
    _realtimeSubscription = null;
    _captureSubscription = null;
    if (finishTranscript) {
      _transcriptCommitter = null;
    }

    _closingIntentionally = true;
    try {
      await captureSubscription?.cancel();
      await captureGateway.stop();
      await realtimeSubscription?.cancel();
      if (graceful) {
        await realtimeSession?.closeGracefully();
      } else {
        await realtimeSession?.closeImmediately();
      }
      if (finishTranscript) {
        await transcriptCommitter?.finish(interrupted: !graceful);
      }
    } finally {
      _closingIntentionally = false;
    }
  }
}
