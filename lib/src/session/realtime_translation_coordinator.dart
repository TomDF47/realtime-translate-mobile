import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../diagnostics/privacy_safe_diagnostics.dart';
import '../openai/openai_credential_store.dart';
import '../openai/openai_realtime_resilience.dart';
import '../openai/openai_realtime_translation.dart';
import 'live_session_controller.dart';
import 'microphone_capture.dart';
import 'microphone_permission.dart';
import 'realtime_transcript_committer.dart';
import 'translated_audio_playback.dart';

typedef LiveRealtimeReconnectDelay = Future<void> Function(Duration delay);
typedef LiveRealtimeTranscriptCommitted = void Function();

enum LiveRealtimeStartResult {
  started,
  missingCredential,
  permissionNotGranted,
  failed,
}

class LiveRealtimeDebugProofResult {
  const LiveRealtimeDebugProofResult({
    required this.transcriptEventCount,
    required this.playbackChunkCount,
    required this.simulatedReconnectCount,
  });

  final int transcriptEventCount;
  final int playbackChunkCount;
  final int simulatedReconnectCount;
}

class LiveRealtimeTranslationCoordinator {
  LiveRealtimeTranslationCoordinator({
    required this.sessionController,
    required this.credentialStore,
    required this.captureGateway,
    required this.realtimeGateway,
    TranslatedAudioPlaybackGateway? playbackGateway,
    this.reconnectPolicy = const OpenAiRealtimeReconnectPolicy(),
    this.reconnectDelay,
    this.connectionTimeout = const Duration(seconds: 12),
    this.diagnostics = const PrivacySafeDiagnostics(),
    this.onTranscriptCommitted,
  }) : playbackGateway =
           playbackGateway ?? NoopTranslatedAudioPlaybackGateway();

  final LiveSessionController sessionController;
  final OpenAiCredentialStore credentialStore;
  final MicrophoneCaptureGateway captureGateway;
  final RealtimeTranslationGateway realtimeGateway;
  final TranslatedAudioPlaybackGateway playbackGateway;
  final OpenAiRealtimeReconnectPolicy reconnectPolicy;
  final LiveRealtimeReconnectDelay? reconnectDelay;
  final Duration connectionTimeout;
  final PrivacySafeDiagnostics diagnostics;
  final LiveRealtimeTranscriptCommitted? onTranscriptCommitted;

  RealtimeTranslationSession? _realtimeSession;
  StreamSubscription<MicrophonePcm16Chunk>? _captureSubscription;
  StreamSubscription<OpenAiRealtimeEvent>? _realtimeSubscription;
  LiveRealtimeTranscriptCommitter? _transcriptCommitter;
  OpenAiRealtimeTranslationConfig? _activeConfig;
  LiveRealtimeTranscriptCommitTarget? _activeTranscriptCommitTarget;
  bool _closingIntentionally = false;
  bool _processTranscriptsDuringIntentionalClose = false;
  bool _handlingFailure = false;
  bool _isDisposed = false;
  bool _translationOutputEnabled = true;
  bool _readAloudOutputEnabled = true;
  int _reconnectGeneration = 0;
  Timer? _pendingReconnectTimer;
  Completer<void>? _pendingReconnectDelay;

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
    if (sessionController.state.microphonePermission !=
        MicrophonePermissionStatus.granted) {
      return LiveRealtimeStartResult.permissionNotGranted;
    }

    RealtimeTranslationSession? realtimeSession;
    try {
      realtimeSession = await _connectWithTimeout(
        config: config,
        credential: credential,
      );
      await playbackGateway.start(
        TranslatedAudioPlaybackConfig.openAiRealtime(
          sampleRateHz: config.inputAudioRate,
        ),
      );
      _bindRealtimeSession(
        realtimeSession,
        transcriptCommitTarget: transcriptCommitTarget,
        resetTranscriptCommitter: true,
      );
      realtimeSession = null;
      await captureGateway.start(
        MicrophoneCaptureConfig.openAiRealtime(
          sampleRateHz: config.inputAudioRate,
        ),
      );
      sessionController.markRealtimeStarted();
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
      await realtimeSession?.closeImmediately();
      await _closeRealtimeResources(graceful: false, finishTranscript: true);
      final decision = reconnectPolicy.plan(
        failure: OpenAiRealtimeFailure.fromSocketError(error),
        retryAttempt: sessionController.state.realtimeRetryAttempt + 1,
      );
      sessionController.applyRealtimeRecoveryDecision(decision);
      if (decision.shouldRetry) {
        _scheduleReconnect(decision);
      }
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
        if (sessionController.state.phase == LiveSessionPhase.reconnecting &&
            sessionController.state.realtimeFailureKind ==
                OpenAiRealtimeFailureKind.lifecycleInterrupted) {
          final retryAttempt = sessionController.state.realtimeRetryAttempt <= 0
              ? 1
              : sessionController.state.realtimeRetryAttempt;
          _scheduleReconnect(
            OpenAiRealtimeReconnectDecision(
              action: OpenAiRealtimeRecoveryAction.reconnectAfterBackoff,
              failure: OpenAiRealtimeFailure.lifecycleInterrupted(),
              retryAttempt: retryAttempt,
              delay: Duration.zero,
            ),
          );
        }
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

  Future<void> discardActiveSession() async {
    _cancelPendingReconnect();
    _activeConfig = null;
    _activeTranscriptCommitTarget = null;
    await _closeRealtimeResources(graceful: false, finishTranscript: false);
    _transcriptCommitter = null;
    sessionController.stopMeeting();
  }

  Future<void> pauseReadAloudOutput() {
    _readAloudOutputEnabled = false;
    return playbackGateway.stop(clearQueue: true);
  }

  void setRuntimeOutputOptions({
    required bool translationOutputEnabled,
    required bool readAloudOutputEnabled,
  }) {
    _translationOutputEnabled = translationOutputEnabled;
    _readAloudOutputEnabled = readAloudOutputEnabled;
  }

  Future<LiveRealtimeDebugProofResult>
  debugInjectGeneratedSpeechStyleReconnectProof() async {
    var assertEnabled = false;
    assert(() {
      assertEnabled = true;
      return true;
    }());
    if (!assertEnabled) {
      throw UnsupportedError('Debug realtime proof is disabled in release.');
    }
    if (_transcriptCommitter == null) {
      throw StateError('Debug realtime proof requires an active meeting.');
    }

    _handleRealtimeEvent(
      const OpenAiRealtimeTranscriptDelta(
        type: 'session.input_transcript.delta',
        kind: OpenAiRealtimeTranscriptKind.source,
        delta: 'Generated ',
      ),
    );
    _handleRealtimeEvent(
      const OpenAiRealtimeTranscriptDelta(
        type: 'session.input_transcript.delta',
        kind: OpenAiRealtimeTranscriptKind.source,
        delta: 'speech',
      ),
    );
    _handleRealtimeEvent(
      const OpenAiRealtimeTranscriptCompleted(
        type: 'session.input_transcript.done',
        kind: OpenAiRealtimeTranscriptKind.source,
        transcript: 'Generated speech',
      ),
    );
    _handleRealtimeEvent(
      OpenAiRealtimeAudioDelta(
        type: 'session.output_audio.delta',
        base64Audio: base64Encode([1, 2, 3, 4]),
      ),
    );
    await _drainDebugProofQueue();

    final config = _activeConfig;
    await playbackGateway.stop(clearQueue: true);
    await playbackGateway.start(
      TranslatedAudioPlaybackConfig.openAiRealtime(
        sampleRateHz: config?.inputAudioRate ?? 24000,
      ),
    );

    _handleRealtimeEvent(
      OpenAiRealtimeAudioDelta(
        type: 'session.output_audio.delta',
        base64Audio: base64Encode([5, 6, 7, 8]),
      ),
    );
    _handleRealtimeEvent(
      const OpenAiRealtimeTranscriptDelta(
        type: 'session.output_transcript.delta',
        kind: OpenAiRealtimeTranscriptKind.translation,
        delta: 'Generated ',
      ),
    );
    _handleRealtimeEvent(
      const OpenAiRealtimeTranscriptCompleted(
        type: 'session.output_transcript.done',
        kind: OpenAiRealtimeTranscriptKind.translation,
        transcript: 'Generated translation.',
      ),
    );
    await _drainDebugProofQueue();

    return const LiveRealtimeDebugProofResult(
      transcriptEventCount: 5,
      playbackChunkCount: 1,
      simulatedReconnectCount: 1,
    );
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
    if (_closingIntentionally &&
        (!_processTranscriptsDuringIntentionalClose ||
            event is! OpenAiRealtimeTranscriptDelta &&
                event is! OpenAiRealtimeTranscriptCompleted)) {
      return;
    }

    switch (event) {
      case OpenAiRealtimeTranscriptDelta():
        if (!_shouldHandleTranscript(event.kind)) {
          return;
        }
        _commitTranscript(_transcriptCommitter?.commitDelta(event));
      case OpenAiRealtimeTranscriptCompleted():
        if (!_shouldHandleTranscript(event.kind)) {
          return;
        }
        _commitTranscript(_transcriptCommitter?.commitCompleted(event));
      case OpenAiRealtimeAudioDelta():
        if (!_shouldHandleTranslatedAudio()) {
          return;
        }
        _enqueueTranslatedAudio(event);
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

  bool _shouldHandleTranscript(OpenAiRealtimeTranscriptKind kind) {
    if (kind == OpenAiRealtimeTranscriptKind.source) {
      return true;
    }

    return _translationOutputEnabled &&
        (_activeConfig?.translationOutputEnabled ?? true);
  }

  bool _shouldHandleTranslatedAudio() {
    final config = _activeConfig;
    if (config == null) {
      return true;
    }

    return _translationOutputEnabled &&
        _readAloudOutputEnabled &&
        config.translationOutputEnabled &&
        config.readAloudOutputEnabled;
  }

  void _commitTranscript(Future<void>? commit) {
    if (commit == null) {
      return;
    }

    unawaited(
      commit
          .then((_) {
            onTranscriptCommitted?.call();
          })
          .catchError((Object error, StackTrace stackTrace) {
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

  void _enqueueTranslatedAudio(OpenAiRealtimeAudioDelta event) {
    unawaited(
      _decodeAndEnqueueTranslatedAudio(event).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        diagnostics.warning(
          'live_realtime.playback_enqueue_failed',
          fields: {
            'operation': 'realtime.playback.enqueue',
            'result': 'failed',
            'errorCode': error.runtimeType.toString(),
          },
        );
        unawaited(
          _handleRealtimeFailure(
            const OpenAiRealtimeFailure(
              kind: OpenAiRealtimeFailureKind.fatal,
              diagnosticCode: 'playback_enqueue_failed',
            ),
            allowReconnect: false,
          ),
        );
      }),
    );
  }

  Future<void> _decodeAndEnqueueTranslatedAudio(
    OpenAiRealtimeAudioDelta event,
  ) async {
    final bytes = base64Decode(event.base64Audio);
    if (bytes.isEmpty) {
      return;
    }

    final config = _activeConfig;
    await playbackGateway.enqueuePcm16(
      TranslatedAudioPcm16Chunk(
        bytes: Uint8List.fromList(bytes),
        sampleRateHz: config?.inputAudioRate ?? 24000,
        channelCount: 1,
      ),
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

    _clearPendingReconnectDelay();
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
    await _waitForReconnectDelay(decision.delay);
    if (_isDisposed || generation != _reconnectGeneration) {
      return;
    }

    RealtimeTranslationSession? realtimeSession;
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

      realtimeSession = await _connectWithTimeout(
        config: config,
        credential: credential,
      );
      if (_isDisposed || generation != _reconnectGeneration) {
        await realtimeSession.closeImmediately();
        return;
      }

      await playbackGateway.start(
        TranslatedAudioPlaybackConfig.openAiRealtime(
          sampleRateHz: config.inputAudioRate,
        ),
      );
      if (_isDisposed || generation != _reconnectGeneration) {
        await playbackGateway.stop(clearQueue: true);
        await realtimeSession.closeImmediately();
        return;
      }

      _bindRealtimeSession(
        realtimeSession,
        transcriptCommitTarget: transcriptCommitTarget,
        resetTranscriptCommitter: false,
      );
      realtimeSession = null;
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
      await realtimeSession?.closeImmediately();
      await _handleRealtimeFailure(
        OpenAiRealtimeFailure.fromSocketError(error),
        allowReconnect: true,
      );
    }
  }

  void _cancelPendingReconnect() {
    _reconnectGeneration += 1;
    _clearPendingReconnectDelay();
  }

  void _clearPendingReconnectDelay() {
    final pendingTimer = _pendingReconnectTimer;
    final pendingDelay = _pendingReconnectDelay;
    _pendingReconnectTimer = null;
    _pendingReconnectDelay = null;
    pendingTimer?.cancel();
    if (pendingDelay != null && !pendingDelay.isCompleted) {
      pendingDelay.complete();
    }
  }

  Future<void> _waitForReconnectDelay(Duration delay) {
    final injectedReconnectDelay = reconnectDelay;
    if (injectedReconnectDelay != null) {
      return injectedReconnectDelay(delay);
    }
    if (delay <= Duration.zero) {
      return Future<void>.value();
    }

    final delayCompleter = Completer<void>();
    _pendingReconnectDelay = delayCompleter;
    _pendingReconnectTimer = Timer(delay, () {
      if (_pendingReconnectDelay == delayCompleter) {
        _pendingReconnectTimer = null;
        _pendingReconnectDelay = null;
      }
      if (!delayCompleter.isCompleted) {
        delayCompleter.complete();
      }
    });
    return delayCompleter.future;
  }

  Future<RealtimeTranslationSession> _connectWithTimeout({
    required OpenAiRealtimeTranslationConfig config,
    required String credential,
  }) {
    return realtimeGateway
        .connect(config: config, credential: credential)
        .timeout(
          connectionTimeout,
          onTimeout: () {
            throw const LiveRealtimeConnectTimeoutException();
          },
        );
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

    _closingIntentionally = true;
    _processTranscriptsDuringIntentionalClose = graceful && finishTranscript;
    try {
      await captureGateway.stop();
      await _cancelSubscription(captureSubscription);
      await playbackGateway.stop(clearQueue: true);
      if (realtimeSession == null) {
        await _cancelSubscription(realtimeSubscription);
      } else if (graceful) {
        await realtimeSession.closeGracefully();
        await realtimeSubscription?.cancel();
      } else {
        await _cancelSubscription(realtimeSubscription);
        await realtimeSession.closeImmediately();
      }
      if (finishTranscript) {
        await transcriptCommitter?.finish(interrupted: !graceful);
        if (identical(_transcriptCommitter, transcriptCommitter)) {
          _transcriptCommitter = null;
        }
      }
    } finally {
      _closingIntentionally = false;
      _processTranscriptsDuringIntentionalClose = false;
    }
  }

  Future<void> _drainDebugProofQueue() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _cancelSubscription(StreamSubscription<dynamic>? subscription) {
    if (subscription == null) {
      return Future<void>.value();
    }

    return subscription.cancel().timeout(
      const Duration(milliseconds: 250),
      onTimeout: () {},
    );
  }
}

class LiveRealtimeConnectTimeoutException implements Exception {
  const LiveRealtimeConnectTimeoutException();
}
