import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../diagnostics/privacy_safe_diagnostics.dart';
import '../language/language_support.dart';
import '../openai/openai_credential_store.dart';
import '../openai/openai_realtime_resilience.dart';
import '../openai/openai_realtime_translation.dart';
import '../openai/openai_text_interpreter.dart';
import '../storage/local_storage_models.dart';
import 'bidirectional_interpreter_routing.dart';
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
    this.connectionTimeout = const Duration(seconds: 20),
    this.startupStepTimeout = const Duration(seconds: 10),
    this.diagnostics = const PrivacySafeDiagnostics(),
    TextInterpreterGateway? textInterpreterGateway,
    this.onTranscriptCommitted,
    this.enableBidirectionalReverseSession = false,
  }) : playbackGateway =
           playbackGateway ?? NoopTranslatedAudioPlaybackGateway(),
       textInterpreterGateway =
           textInterpreterGateway ?? OpenAiResponsesTextInterpreterGateway();

  final LiveSessionController sessionController;
  final OpenAiCredentialStore credentialStore;
  final MicrophoneCaptureGateway captureGateway;
  final RealtimeTranslationGateway realtimeGateway;
  final TranslatedAudioPlaybackGateway playbackGateway;
  final OpenAiRealtimeReconnectPolicy reconnectPolicy;
  final LiveRealtimeReconnectDelay? reconnectDelay;
  final Duration connectionTimeout;

  /// Upper bound for each post-connect bring-up step (translated-audio
  /// playback start and microphone capture start). These steps are platform
  /// channel calls that can otherwise hang indefinitely and pin the session in
  /// [LiveSessionPhase.connecting] with no user-visible recovery.
  final Duration startupStepTimeout;

  final PrivacySafeDiagnostics diagnostics;
  final TextInterpreterGateway textInterpreterGateway;
  final LiveRealtimeTranscriptCommitted? onTranscriptCommitted;

  /// When true, once the language pair is locked the coordinator opens a second
  /// dedicated translation session whose output language is the OTHER detected
  /// language, so the reverse speaker also hears live translated audio.
  ///
  /// This follows OpenAI's documented two-party pattern ("for a two-person
  /// call, this usually means two translation sessions: A-to-B and B-to-A").
  /// The reverse session is audio-only (source transcription disabled) so it
  /// never writes duplicate transcript rows, and it is best-effort: a
  /// reverse-session failure never disturbs the primary interpreter path.
  /// Reverse-direction TEXT is still produced by the direct OpenAI text path,
  /// which is the single writer for that direction.
  final bool enableBidirectionalReverseSession;

  RealtimeTranslationSession? _realtimeSession;
  StreamSubscription<MicrophonePcm16Chunk>? _captureSubscription;
  StreamSubscription<OpenAiRealtimeEvent>? _realtimeSubscription;
  LiveRealtimeTranscriptCommitter? _transcriptCommitter;
  OpenAiRealtimeTranslationConfig? _activeConfig;
  LiveRealtimeTranscriptCommitTarget? _activeTranscriptCommitTarget;
  String? _activeInterpreterMeetingId;
  String? _activeInterpreterRouteKey;
  BidirectionalInterpreterRuntime _bidirectionalRuntime =
      BidirectionalInterpreterRuntime();
  // Optional reverse-direction (audio-only) session for true bidirectional
  // translated audio. See [enableBidirectionalReverseSession].
  RealtimeTranslationSession? _reverseSession;
  StreamSubscription<OpenAiRealtimeEvent>? _reverseEventSubscription;
  StreamSubscription<MicrophonePcm16Chunk>? _reverseCaptureSubscription;
  bool _reverseStarting = false;
  int _reverseGeneration = 0;
  final List<_RealtimeSourceTurn> _completedSourceTurns =
      <_RealtimeSourceTurn>[];
  final Set<String> _fallbackInFlightEntryIds = <String>{};
  final Set<String> _fallbackCompletedEntryIds = <String>{};
  final Set<String> _fallbackAuthoritativeEntryIds = <String>{};
  bool _sourceQueuedAfterFallbackAuthoritativeEntry = false;
  // Presence-only counters that prove what the dedicated translation wire
  // actually delivered for the active session, without retaining any
  // transcript content. They back the "translation arrived but original
  // source never did" detection and the privacy-safe session-end signal
  // summary; never store transcript/translation text here.
  int _sourceTranscriptTurns = 0;
  int _outputTranscriptTurns = 0;
  int _sourcelessFinalTurns = 0;
  // Ids of entries that finalized translation-only (translated text, empty
  // original) and were counted in [_sourcelessFinalTurns]. The dedicated
  // translation wire can deliver a turn's translation before its source, so
  // such an entry is only provisionally sourceless: if the SAME row later
  // backfills original text, it is a valid turn, not the round-3 failure, and
  // must be uncounted so the release-checkable signal stays accurate.
  final Set<String> _sourcelessFinalEntryIds = <String>{};
  bool _closingIntentionally = false;
  bool _processTranscriptsDuringIntentionalClose = false;
  bool _handlingFailure = false;
  bool _isDisposed = false;
  bool _translationOutputEnabled = true;
  bool _readAloudOutputEnabled = true;
  int _startGeneration = 0;
  int _reconnectGeneration = 0;
  Timer? _pendingReconnectTimer;
  Completer<void>? _pendingReconnectDelay;

  bool get isStreaming {
    return _realtimeSession != null && captureGateway.isCapturing;
  }

  /// User-facing interpreter status/header label derived from the languages the
  /// runtime has actually detected on committed source turns.
  ///
  /// This is the single runtime source of truth for the live header so it stays
  /// consistent with transcript block language attribution. It reports the
  /// listening state, then the single heard-language waiting state, then the
  /// locked two-language pair state once a second distinct language is
  /// detected. It never defaults an unknown source to the target language.
  String get interpreterRouteLabel => _bidirectionalRuntime.routeLabel;

  /// Content-free snapshot of which realtime transcript signals the active
  /// session has actually received. Exposes only counts and a derived state,
  /// never any transcript/translation text, so smoke and release checks can
  /// assert that source (original) transcript turns arrived and were not
  /// silently replaced by translation-only output.
  RealtimeTranscriptSignalSnapshot get transcriptSignalSnapshot {
    return RealtimeTranscriptSignalSnapshot(
      sourceTurnCount: _sourceTranscriptTurns,
      outputTurnCount: _outputTranscriptTurns,
      sourcelessFinalCount: _sourcelessFinalTurns,
    );
  }

  Future<LiveRealtimeStartResult> start({
    required OpenAiRealtimeTranslationConfig config,
    LiveRealtimeTranscriptCommitTarget? transcriptCommitTarget,
  }) async {
    _isDisposed = false;
    final startGeneration = ++_startGeneration;
    _cancelPendingReconnect();
    final manualRouteKey = _manualInterpreterRouteKey(
      config: config,
      transcriptCommitTarget: transcriptCommitTarget,
    );
    await _closeRealtimeResources(graceful: false, finishTranscript: true);
    if (!_isCurrentStart(startGeneration)) {
      return LiveRealtimeStartResult.failed;
    }

    _resetInterpreterRuntimeIfNeeded(
      meetingId: transcriptCommitTarget?.meetingId,
      routeKey: manualRouteKey,
    );
    _activeConfig = config;
    _activeTranscriptCommitTarget = transcriptCommitTarget;
    _seedInterpreterRuntimeFromManualRoute(
      config: config,
      transcriptCommitTarget: transcriptCommitTarget,
    );

    final credential = await credentialStore.readCredentialForNetworkUse();
    if (!_isCurrentStart(startGeneration)) {
      return LiveRealtimeStartResult.failed;
    }
    if (credential == null || credential.isEmpty) {
      sessionController.markCredentialInvalid();
      return LiveRealtimeStartResult.missingCredential;
    }

    await sessionController.startMeeting();
    if (!_isCurrentStart(startGeneration)) {
      return LiveRealtimeStartResult.failed;
    }
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
      if (!_isCurrentStart(startGeneration)) {
        await realtimeSession.closeImmediately();
        return LiveRealtimeStartResult.failed;
      }
      await _startPlaybackQueue(config);
      if (!_isCurrentStart(startGeneration)) {
        await playbackGateway.stop(clearQueue: true);
        await realtimeSession.closeImmediately();
        return LiveRealtimeStartResult.failed;
      }
      _bindRealtimeSession(
        realtimeSession,
        transcriptCommitTarget: transcriptCommitTarget,
        resetTranscriptCommitter: true,
      );
      realtimeSession = null;
      await _startMicrophoneCapture(config);
      if (!_isCurrentStart(startGeneration)) {
        await _closeRealtimeResources(graceful: false, finishTranscript: false);
        return LiveRealtimeStartResult.failed;
      }
      sessionController.markRealtimeStarted();
      _maybeStartReverseSession();
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
      if (!_isCurrentStart(startGeneration)) {
        return LiveRealtimeStartResult.failed;
      }
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
        _startGeneration += 1;
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
    _startGeneration += 1;
    _cancelPendingReconnect();
    _activeConfig = null;
    _activeTranscriptCommitTarget = null;
    _resetInterpreterRuntimeIfNeeded(meetingId: null, routeKey: null);
    await _closeRealtimeResources(graceful: true, finishTranscript: true);
    sessionController.stopMeeting();
  }

  Future<void> pauseListening() async {
    _startGeneration += 1;
    _cancelPendingReconnect();
    sessionController.pauseListening();
    await _closeRealtimeResources(graceful: true, finishTranscript: true);
  }

  Future<LiveRealtimeStartResult> resumeListening() async {
    final config = _activeConfig;
    if (config == null) {
      return LiveRealtimeStartResult.failed;
    }

    return start(
      config: config,
      transcriptCommitTarget: _activeTranscriptCommitTarget,
    );
  }

  Future<void> discardActiveSession() async {
    _startGeneration += 1;
    _cancelPendingReconnect();
    _activeConfig = null;
    _activeTranscriptCommitTarget = null;
    _resetInterpreterRuntimeIfNeeded(meetingId: null, routeKey: null);
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
    _startGeneration += 1;
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
        if (event.kind == OpenAiRealtimeTranscriptKind.source) {
          _noteSourceQueuedAfterFallbackAuthoritativeEntry(event);
        }
        if (_shouldSuppressRealtimeTranslationForFallback(event)) {
          return;
        }
        _commitTranscript(
          _transcriptCommitter?.commitDelta(
            event,
            forceNewSegment: _shouldStartNewRealtimeTranslationAfterFallback(
              event,
            ),
          ),
        );
      case OpenAiRealtimeTranscriptCompleted():
        if (!_shouldHandleTranscript(event.kind)) {
          return;
        }
        if (event.kind == OpenAiRealtimeTranscriptKind.source) {
          _noteSourceQueuedAfterFallbackAuthoritativeEntry(event);
          _commitSourceTranscriptAndMaybeFallback(event);
          return;
        }
        if (_shouldSuppressRealtimeTranslationForFallback(event)) {
          return;
        }
        _commitTranslationCompletion(
          _transcriptCommitter?.commitCompleted(
            event,
            forceNewSegment: _shouldStartNewRealtimeTranslationAfterFallback(
              event,
            ),
          ),
        );
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

  void _commitTranscript(Future<StoredTranscriptEntry?>? commit) {
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

  void _commitTranslationCompletion(Future<StoredTranscriptEntry?>? commit) {
    if (commit == null) {
      return;
    }

    unawaited(
      commit
          .then((entry) {
            onTranscriptCommitted?.call();
            if (entry == null) {
              return;
            }
            if (entry.translatedText.trim().isNotEmpty) {
              _outputTranscriptTurns += 1;
            }
            // A finalized card that carries translated output but no original
            // source text is the "translation arrived but original source
            // never did" failure mode from Tom's installed-app retest. Surface
            // it as a privacy-safe, content-free signal so a release check can
            // detect it instead of the UI silently showing a misleading
            // completed card with "Original speech pending".
            //
            // This is provisional: on the dedicated translation wire a turn's
            // translation can finalize before its source arrives. The entry id
            // is tracked so that, if this same row later backfills original
            // text, [_commitSourceTranscriptAndMaybeFallback] uncounts it
            // (the valid translation-first ordering must not leave the
            // release-checkable signal tripped). Each entry is counted at most
            // once: a still-partial row can receive more than one output
            // `.done` (a refinement/re-emission) before its source arrives, so
            // counting per completion would over-count and a single backfill
            // reversal could not zero it again.
            if (entry.translatedText.trim().isNotEmpty &&
                entry.originalText.trim().isEmpty &&
                _sourcelessFinalEntryIds.add(entry.id)) {
              _sourcelessFinalTurns += 1;
              diagnostics.warning(
                'live_realtime.translation_without_source',
                fields: {
                  'operation': 'realtime.transcript.signal',
                  'signalState': 'translation_without_source',
                  'hasSourceSignal': _sourceTranscriptTurns > 0,
                  'hasOutputSignal': _outputTranscriptTurns > 0,
                  'sourceTurnCount': _sourceTranscriptTurns,
                  'outputTurnCount': _outputTranscriptTurns,
                  'sourcelessFinalCount': _sourcelessFinalTurns,
                },
              );
            }
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

  void _commitSourceTranscriptAndMaybeFallback(
    OpenAiRealtimeTranscriptCompleted event,
  ) {
    final commit = _transcriptCommitter?.commitCompleted(event);
    if (commit == null) {
      return;
    }

    unawaited(
      commit
          .then((entry) {
            onTranscriptCommitted?.call();
            if (entry == null) {
              return;
            }
            if (entry.originalText.trim().isNotEmpty) {
              _sourceTranscriptTurns += 1;
              _clearSourcelessFinalForBackfilledEntry(entry);
            }
            _trackSourceTurnForFallback(entry);
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

  void _trackSourceTurnForFallback(StoredTranscriptEntry entry) {
    final sourceCode = entry.languageCode.trim().toLowerCase();
    if (sourceCode.isEmpty ||
        sourceCode == 'auto' ||
        entry.originalText.trim().isEmpty) {
      return;
    }

    _bidirectionalRuntime.recordDetectedLanguage(
      code: sourceCode,
      label: _languageLabelForCode(sourceCode),
    );
    _completedSourceTurns.add(
      _RealtimeSourceTurn(entry: entry, sourceLanguageCode: sourceCode),
    );
    if (!_bidirectionalRuntime.isPairLocked) {
      return;
    }

    _maybeStartReverseSession();
    for (final turn in List<_RealtimeSourceTurn>.of(_completedSourceTurns)) {
      _requestDirectFallbackIfNeeded(turn);
    }
  }

  void _requestDirectFallbackIfNeeded(_RealtimeSourceTurn turn) {
    final direction = _bidirectionalRuntime.directionForSource(
      turn.sourceLanguageCode,
    );
    if (direction == null) {
      return;
    }

    // The single dedicated translation session is configured for ONE output
    // language (the primary target). When a turn's source language already IS
    // that output language, the session stays silent for it (the model does
    // not translate speech that is already in the output language), so the
    // reverse direction's TEXT must come from the direct OpenAI text path. This
    // also covers non-realtime output targets (for example Arabic) that always
    // use the text path. It is independent of whether a live reverse-audio
    // session is up, so reverse-direction text appears reliably either way.
    final primaryTarget = _activeConfig?.targetLanguageCode.trim().toLowerCase();
    final sourceMatchesPrimaryOutput =
        primaryTarget != null && turn.sourceLanguageCode == primaryTarget;
    final isTextOnlyTarget =
        direction.routePlan.type == TranslationRouteType.directOpenAiFallback;
    if (!sourceMatchesPrimaryOutput && !isTextOnlyTarget) {
      return;
    }

    if (_fallbackInFlightEntryIds.contains(turn.entry.id) ||
        _fallbackCompletedEntryIds.contains(turn.entry.id)) {
      return;
    }

    _fallbackAuthoritativeEntryIds.add(turn.entry.id);
    _fallbackInFlightEntryIds.add(turn.entry.id);
    unawaited(_translateTextFallbackTurn(turn, direction));
  }

  /// Opens the reverse-direction audio session once the pair is locked.
  ///
  /// The reverse session's output language is the detected language that is NOT
  /// the primary session's output target, so the primary speaker's words are
  /// translated back into the other participant's language as live audio. It is
  /// audio-only (source transcription disabled) and best-effort.
  void _maybeStartReverseSession() {
    if (!enableBidirectionalReverseSession) {
      return;
    }
    if (_reverseSession != null || _reverseStarting) {
      return;
    }
    final config = _activeConfig;
    if (config == null || !_bidirectionalRuntime.isPairLocked) {
      return;
    }

    final primaryTarget = config.targetLanguageCode.trim().toLowerCase();
    String? reverseTarget;
    for (final code in _bidirectionalRuntime.languageCodes) {
      final normalized = code.trim().toLowerCase();
      if (normalized.isNotEmpty && normalized != primaryTarget) {
        reverseTarget = normalized;
        break;
      }
    }
    // Only open a realtime reverse-audio session for a documented output
    // language; a non-realtime output language keeps the reverse-direction text
    // path only.
    if (reverseTarget == null || !_isRealtimeOutputLanguage(reverseTarget)) {
      return;
    }

    _reverseStarting = true;
    unawaited(_startReverseSession(config: config, reverseTarget: reverseTarget));
  }

  bool _isRealtimeOutputLanguage(String code) {
    try {
      return LanguageSupport.languageByCode(code).supportsRealtimeTarget;
    } on ArgumentError {
      return false;
    }
  }

  Future<void> _startReverseSession({
    required OpenAiRealtimeTranslationConfig config,
    required String reverseTarget,
  }) async {
    final generation = ++_reverseGeneration;
    RealtimeTranslationSession? session;
    try {
      final credential = await credentialStore.readCredentialForNetworkUse();
      if (credential == null || credential.isEmpty) {
        _reverseStarting = false;
        return;
      }
      final primaryTarget = config.targetLanguageCode.trim().toLowerCase();
      final reverseConfig = config.copyWith(
        targetLanguageCode: reverseTarget,
        sourceLanguageCode: primaryTarget,
        sourceTranscriptionEnabled: false,
      );
      session = await _connectWithTimeout(
        config: reverseConfig,
        credential: credential,
      );
      if (_isDisposed || generation != _reverseGeneration) {
        await session.closeImmediately();
        _reverseStarting = false;
        return;
      }

      _reverseSession = session;
      final boundSession = session;
      _reverseEventSubscription = session.events.listen(
        _handleReverseEvent,
        onError: (Object error) {
          unawaited(_handleReverseSessionDrop());
        },
      );
      _reverseCaptureSubscription = captureGateway.chunks.listen(
        (chunk) => boundSession.appendPcm16Audio(chunk.bytes),
        onError: (Object error) {
          unawaited(_handleReverseSessionDrop());
        },
      );
      _reverseStarting = false;
      diagnostics.info(
        'live_realtime.reverse_session_started',
        fields: {
          'operation': 'realtime.reverse.start',
          'realtimeProfile': reverseConfig.profile.name,
          'targetLanguage': reverseTarget,
          'result': 'started',
        },
      );
    } catch (error) {
      _reverseStarting = false;
      await session?.closeImmediately();
      diagnostics.warning(
        'live_realtime.reverse_session_failed',
        fields: {
          'operation': 'realtime.reverse.start',
          'targetLanguage': reverseTarget,
          'result': 'failed',
          'errorCode': error.runtimeType.toString(),
        },
      );
    }
  }

  void _handleReverseEvent(OpenAiRealtimeEvent event) {
    if (_closingIntentionally) {
      return;
    }

    switch (event) {
      case OpenAiRealtimeAudioDelta():
        if (_shouldHandleTranslatedAudio()) {
          _enqueueTranslatedAudio(event);
        }
      case OpenAiRealtimeError():
        unawaited(_handleReverseSessionDrop());
      case OpenAiRealtimeSessionClosed():
        unawaited(_handleReverseSessionDrop());
      default:
        // Reverse session is audio-only: it has source transcription disabled,
        // so it does not write transcript rows. Translated-transcript deltas it
        // may emit are ignored here because the reverse-direction TEXT is owned
        // by the direct OpenAI text path (the single writer for that row).
        break;
    }
  }

  /// Tears down the reverse session without disturbing the primary path. The
  /// next locked-pair source turn re-arms [_maybeStartReverseSession].
  Future<void> _handleReverseSessionDrop() async {
    final session = _reverseSession;
    final eventSubscription = _reverseEventSubscription;
    final captureSubscription = _reverseCaptureSubscription;
    _reverseSession = null;
    _reverseEventSubscription = null;
    _reverseCaptureSubscription = null;
    _reverseStarting = false;
    await _cancelSubscription(eventSubscription);
    await _cancelSubscription(captureSubscription);
    await session?.closeImmediately();
  }

  Future<void> _closeReverseSession() async {
    _reverseGeneration += 1;
    await _handleReverseSessionDrop();
  }

  bool _shouldSuppressRealtimeTranslationForFallback(
    OpenAiRealtimeEvent event,
  ) {
    final itemId = switch (event) {
      OpenAiRealtimeTranscriptDelta(
        kind: OpenAiRealtimeTranscriptKind.translation,
        :final itemId,
      ) =>
        itemId,
      OpenAiRealtimeTranscriptCompleted(
        kind: OpenAiRealtimeTranscriptKind.translation,
        :final itemId,
      ) =>
        itemId,
      _ => null,
    };
    if (itemId == null || itemId.isEmpty) {
      return false;
    }

    final entryId = _transcriptCommitter?.entryIdForRealtimeItem(itemId);
    return _fallbackAuthoritativeEntryIds.contains(entryId);
  }

  bool _shouldStartNewRealtimeTranslationAfterFallback(
    OpenAiRealtimeEvent event,
  ) {
    final itemId = switch (event) {
      OpenAiRealtimeTranscriptDelta(
        kind: OpenAiRealtimeTranscriptKind.translation,
        :final itemId,
      ) =>
        itemId,
      OpenAiRealtimeTranscriptCompleted(
        kind: OpenAiRealtimeTranscriptKind.translation,
        :final itemId,
      ) =>
        itemId,
      _ => null,
    };
    if (itemId != null && itemId.isNotEmpty) {
      _sourceQueuedAfterFallbackAuthoritativeEntry = false;
      final entryId = _transcriptCommitter?.entryIdForRealtimeItem(itemId);
      return entryId != null &&
          _fallbackAuthoritativeEntryIds.contains(entryId);
    }

    final isTranslation = switch (event) {
      OpenAiRealtimeTranscriptDelta(
        kind: OpenAiRealtimeTranscriptKind.translation,
      ) =>
        true,
      OpenAiRealtimeTranscriptCompleted(
        kind: OpenAiRealtimeTranscriptKind.translation,
      ) =>
        true,
      _ => false,
    };
    if (!isTranslation) {
      return false;
    }

    if (_sourceQueuedAfterFallbackAuthoritativeEntry) {
      _sourceQueuedAfterFallbackAuthoritativeEntry = false;
      return false;
    }

    final currentEntryId = _transcriptCommitter?.currentEntryId;
    return currentEntryId != null &&
        _fallbackAuthoritativeEntryIds.contains(currentEntryId);
  }

  void _noteSourceQueuedAfterFallbackAuthoritativeEntry(
    OpenAiRealtimeEvent event,
  ) {
    final currentEntryId = _transcriptCommitter?.currentEntryId;
    if (currentEntryId == null ||
        !_fallbackAuthoritativeEntryIds.contains(currentEntryId)) {
      return;
    }

    final itemId = switch (event) {
      OpenAiRealtimeTranscriptDelta(
        kind: OpenAiRealtimeTranscriptKind.source,
        :final itemId,
      ) =>
        itemId,
      OpenAiRealtimeTranscriptCompleted(
        kind: OpenAiRealtimeTranscriptKind.source,
        :final itemId,
      ) =>
        itemId,
      _ => null,
    };
    if (itemId != null && itemId.isNotEmpty) {
      final eventEntryId = _transcriptCommitter?.entryIdForRealtimeItem(itemId);
      if (eventEntryId == currentEntryId) {
        return;
      }
    }

    _sourceQueuedAfterFallbackAuthoritativeEntry = true;
  }

  Future<void> _translateTextFallbackTurn(
    _RealtimeSourceTurn turn,
    BidirectionalInterpreterDirection direction,
  ) async {
    try {
      final credential = await credentialStore.readCredentialForNetworkUse();
      if (credential == null || credential.isEmpty) {
        sessionController.markCredentialInvalid();
        return;
      }
      final result = await textInterpreterGateway.interpretTurn(
        request: TextInterpreterTurnRequest(
          text: turn.entry.originalText,
          knownLanguageCodes: _bidirectionalRuntime.languageCodes,
          sourceLanguageCode: direction.sourceLanguageCode,
          targetLanguageCode: direction.targetLanguageCode,
          routeType: TranslationRouteType.directOpenAiFallback,
        ),
        credential: credential,
      );
      final translatedText = result.translatedText?.trim();
      if (translatedText == null || translatedText.isEmpty) {
        return;
      }

      final target = _activeTranscriptCommitTarget;
      if (target == null || turn.entry.meetingId.isEmpty) {
        return;
      }
      await target.repository.upsertTranscriptEntry(
        meetingId: turn.entry.meetingId,
        updatedAt: target.now().toUtc(),
        entry: turn.entry.copyWith(
          translatedText: translatedText,
          status: 'final',
        ),
      );
      _fallbackCompletedEntryIds.add(turn.entry.id);
      onTranscriptCommitted?.call();
    } on TextInterpreterCredentialException {
      sessionController.markCredentialInvalid();
    } catch (error) {
      diagnostics.warning(
        'live_realtime.text_fallback_failed',
        fields: {
          'operation': 'textInterpreter.interpretTurn',
          'result': 'failed',
          'errorCode': error.runtimeType.toString(),
        },
      );
    } finally {
      _fallbackInFlightEntryIds.remove(turn.entry.id);
    }
  }

  String? _manualInterpreterRouteKey({
    required OpenAiRealtimeTranslationConfig config,
    required LiveRealtimeTranscriptCommitTarget? transcriptCommitTarget,
  }) {
    final sourceCode =
        transcriptCommitTarget?.sourceLanguageCode ?? config.sourceLanguageCode;
    final targetCode =
        transcriptCommitTarget?.targetLanguageCode ?? config.targetLanguageCode;
    final normalizedSource = sourceCode.trim().toLowerCase();
    final normalizedTarget = targetCode.trim().toLowerCase();
    if (normalizedSource.isEmpty ||
        normalizedTarget.isEmpty ||
        normalizedSource == 'auto' ||
        normalizedTarget == 'auto' ||
        normalizedSource == normalizedTarget) {
      return null;
    }

    return '$normalizedSource->$normalizedTarget';
  }

  void _seedInterpreterRuntimeFromManualRoute({
    required OpenAiRealtimeTranslationConfig config,
    required LiveRealtimeTranscriptCommitTarget? transcriptCommitTarget,
  }) {
    final sourceCode =
        transcriptCommitTarget?.sourceLanguageCode ?? config.sourceLanguageCode;
    final targetCode =
        transcriptCommitTarget?.targetLanguageCode ?? config.targetLanguageCode;
    final normalizedSource = sourceCode.trim().toLowerCase();
    final normalizedTarget = targetCode.trim().toLowerCase();
    if (normalizedSource.isEmpty ||
        normalizedTarget.isEmpty ||
        normalizedSource == 'auto' ||
        normalizedTarget == 'auto' ||
        normalizedSource == normalizedTarget) {
      return;
    }

    _bidirectionalRuntime.recordDetectedLanguage(
      code: normalizedSource,
      label: _languageLabelForCode(normalizedSource),
    );
    _bidirectionalRuntime.recordDetectedLanguage(
      code: normalizedTarget,
      label: _languageLabelForCode(normalizedTarget),
    );
  }

  void _resetInterpreterRuntimeIfNeeded({
    required String? meetingId,
    required String? routeKey,
  }) {
    if (_activeInterpreterMeetingId == meetingId &&
        _activeInterpreterRouteKey == routeKey) {
      return;
    }

    _activeInterpreterMeetingId = meetingId;
    _activeInterpreterRouteKey = routeKey;
    _bidirectionalRuntime = BidirectionalInterpreterRuntime();
    _completedSourceTurns.clear();
    _fallbackInFlightEntryIds.clear();
    _fallbackCompletedEntryIds.clear();
    _fallbackAuthoritativeEntryIds.clear();
    _sourceQueuedAfterFallbackAuthoritativeEntry = false;
    _resetTranscriptSignalCounters();
  }

  /// Reverses a provisional translation-only count once the same row backfills
  /// original text.
  ///
  /// On the dedicated `/v1/realtime/translations` wire a turn's translation
  /// can finalize before its source arrives, so the translation completion
  /// provisionally counts the row as sourceless. When the matching source
  /// completion later writes original text into the SAME entry id, that turn
  /// is valid (not the round-3 "translation arrived but source never did"
  /// failure), so its sourceless-final count is reversed. This keeps
  /// [transcriptSignalSnapshot] accurate: after a valid backfill,
  /// `sourcelessFinalCount` returns to its prior value and
  /// `translationArrivedWithoutSource`/`hasSourcelessFinal` are not left
  /// falsely tripped.
  void _clearSourcelessFinalForBackfilledEntry(StoredTranscriptEntry entry) {
    if (!_sourcelessFinalEntryIds.remove(entry.id)) {
      return;
    }
    if (_sourcelessFinalTurns > 0) {
      _sourcelessFinalTurns -= 1;
    }
  }

  void _resetTranscriptSignalCounters() {
    _sourceTranscriptTurns = 0;
    _outputTranscriptTurns = 0;
    _sourcelessFinalTurns = 0;
    _sourcelessFinalEntryIds.clear();
  }

  String _languageLabelForCode(String code) {
    try {
      return LanguageSupport.languageByCode(code).name;
    } on ArgumentError {
      return code.toUpperCase();
    }
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

  bool _isCurrentStart(int generation) {
    return !_isDisposed && generation == _startGeneration;
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

      await _startPlaybackQueue(config);
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
      await _startMicrophoneCapture(config);
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

  Future<void> _startPlaybackQueue(OpenAiRealtimeTranslationConfig config) {
    return playbackGateway
        .start(
          TranslatedAudioPlaybackConfig.openAiRealtime(
            sampleRateHz: config.inputAudioRate,
          ),
        )
        .timeout(
          startupStepTimeout,
          onTimeout: () {
            throw const LiveRealtimeStartupTimeoutException(
              'translatedPlayback.start',
            );
          },
        );
  }

  Future<void> _startMicrophoneCapture(OpenAiRealtimeTranslationConfig config) {
    return captureGateway
        .start(
          MicrophoneCaptureConfig.openAiRealtime(
            sampleRateHz: config.inputAudioRate,
          ),
        )
        .timeout(
          startupStepTimeout,
          onTimeout: () {
            throw const LiveRealtimeStartupTimeoutException(
              'microphone.capture.start',
            );
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
      await _closeReverseSession();
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

/// Thrown when a post-connect live-session bring-up step (translated-audio
/// playback start or microphone capture start) exceeds [startupStepTimeout].
///
/// The [step] string is a sanitized operation name only; it never carries
/// credential, transcript, audio, or translation content. The message contains
/// the word "timeout" so it classifies as a retryable network-style failure via
/// [OpenAiRealtimeFailure.fromSocketError], routing the session into the
/// existing bounded reconnect/offline recovery path instead of an indefinite
/// `connecting` stall.
class LiveRealtimeStartupTimeoutException implements Exception {
  const LiveRealtimeStartupTimeoutException(this.step);

  final String step;

  @override
  String toString() => 'LiveRealtimeStartupTimeoutException($step)';
}

/// Content-free summary of which realtime transcript signals a session has
/// received. Carries only counts/derived flags so it can be logged, asserted
/// in smoke checks, or surfaced in diagnostics without ever exposing
/// transcript or translation content.
class RealtimeTranscriptSignalSnapshot {
  const RealtimeTranscriptSignalSnapshot({
    required this.sourceTurnCount,
    required this.outputTurnCount,
    required this.sourcelessFinalCount,
  });

  /// Number of finalized source (original) transcript turns that carried text.
  final int sourceTurnCount;

  /// Number of finalized translation (output) transcript commits that carried
  /// text. This counts output `.done` finalizations, not unique visible cards;
  /// a long turn that crosses readable-block rolls can finalize output more
  /// than once. It is a presence signal, so callers should only rely on
  /// whether it is greater than zero.
  final int outputTurnCount;

  /// Number of finalized cards that had translated output but never received
  /// any original/source text (the "translation arrived but source never did"
  /// failure mode).
  final int sourcelessFinalCount;

  /// True when at least one source/original transcript turn arrived.
  bool get hasSourceSignal => sourceTurnCount > 0;

  /// True when at least one translation/output transcript turn arrived.
  bool get hasOutputSignal => outputTurnCount > 0;

  /// True when any finalized card carried translated output but never received
  /// its own original/source text.
  ///
  /// This is the release-checkable failure state for the round-3 regression,
  /// where the FIRST card had source + translation but LATER cards lost the
  /// original while still translating. It is derived from
  /// [sourcelessFinalCount] so it stays true even once an earlier source turn
  /// has set [hasSourceSignal]; the all-output/no-source heuristic alone
  /// cannot detect "first source works, later source missing".
  bool get hasSourcelessFinal => sourcelessFinalCount > 0;

  /// True when translation output arrived but at least one finalized card had
  /// no original/source text, i.e. cards would render "Original speech
  /// pending" permanently.
  ///
  /// Covers both the all-output/no-source case ([hasOutputSignal] with no
  /// [hasSourceSignal]) and the round-3 case where an earlier turn had source
  /// but a later turn finalized translation-only ([hasSourcelessFinal]).
  bool get translationArrivedWithoutSource =>
      hasSourcelessFinal || (hasOutputSignal && !hasSourceSignal);
}

class _RealtimeSourceTurn {
  const _RealtimeSourceTurn({
    required this.entry,
    required this.sourceLanguageCode,
  });

  final StoredTranscriptEntry entry;
  final String sourceLanguageCode;
}
