import 'dart:async';

import 'package:flutter/widgets.dart';

import '../diagnostics/privacy_safe_diagnostics.dart';
import '../openai/openai_credential_store.dart';
import '../openai/openai_realtime_resilience.dart';
import '../openai/openai_realtime_translation.dart';
import 'live_session_controller.dart';
import 'microphone_capture.dart';
import 'realtime_transcript_committer.dart';

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
    this.diagnostics = const PrivacySafeDiagnostics(),
  });

  final LiveSessionController sessionController;
  final OpenAiCredentialStore credentialStore;
  final MicrophoneCaptureGateway captureGateway;
  final RealtimeTranslationGateway realtimeGateway;
  final OpenAiRealtimeReconnectPolicy reconnectPolicy;
  final PrivacySafeDiagnostics diagnostics;

  RealtimeTranslationSession? _realtimeSession;
  StreamSubscription<MicrophonePcm16Chunk>? _captureSubscription;
  StreamSubscription<OpenAiRealtimeEvent>? _realtimeSubscription;
  LiveRealtimeTranscriptCommitter? _transcriptCommitter;
  bool _closingIntentionally = false;
  bool _handlingFailure = false;

  bool get isStreaming {
    return _realtimeSession != null && captureGateway.isCapturing;
  }

  Future<LiveRealtimeStartResult> start({
    required OpenAiRealtimeTranslationConfig config,
    LiveRealtimeTranscriptCommitTarget? transcriptCommitTarget,
  }) async {
    await _closeRealtimeResources(graceful: false);

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
      _realtimeSession = realtimeSession;
      _transcriptCommitter = transcriptCommitTarget == null
          ? null
          : LiveRealtimeTranscriptCommitter(transcriptCommitTarget);
      _realtimeSubscription = realtimeSession.events.listen(
        _handleRealtimeEvent,
        onError: (error) {
          unawaited(
            _handleRealtimeFailure(
              OpenAiRealtimeFailure.fromSocketError(error),
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
            ),
          );
        },
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
      await _closeRealtimeResources(graceful: false);
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
        unawaited(_closeRealtimeResources(graceful: false));
      case AppLifecycleState.resumed:
        break;
    }
  }

  Future<void> stop() async {
    await _closeRealtimeResources(graceful: true);
    sessionController.stopMeeting();
  }

  void dispose() {
    unawaited(_closeRealtimeResources(graceful: false));
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
          ),
        );
      case OpenAiRealtimeSessionClosed():
        unawaited(
          _handleRealtimeFailure(OpenAiRealtimeFailure.sessionClosed()),
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

  Future<void> _handleRealtimeFailure(OpenAiRealtimeFailure failure) async {
    if (_handlingFailure || _closingIntentionally) {
      return;
    }

    _handlingFailure = true;
    try {
      await _closeRealtimeResources(graceful: false);
      sessionController.applyRealtimeRecoveryDecision(
        reconnectPolicy.plan(
          failure: failure,
          retryAttempt: sessionController.state.realtimeRetryAttempt + 1,
        ),
      );
    } finally {
      _handlingFailure = false;
    }
  }

  Future<void> _closeRealtimeResources({required bool graceful}) async {
    final realtimeSession = _realtimeSession;
    final realtimeSubscription = _realtimeSubscription;
    final captureSubscription = _captureSubscription;
    final transcriptCommitter = _transcriptCommitter;
    _realtimeSession = null;
    _realtimeSubscription = null;
    _captureSubscription = null;
    _transcriptCommitter = null;

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
      await transcriptCommitter?.finish(interrupted: !graceful);
    } finally {
      _closingIntentionally = false;
    }
  }
}
