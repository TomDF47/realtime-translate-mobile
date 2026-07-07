import 'dart:math' as math;

import 'openai_realtime_transcription.dart';
import 'openai_realtime_translation.dart';

enum OpenAiRealtimeFailureKind {
  credentialExpired,
  credentialRejected,
  configurationRejected,
  unsupportedLanguage,
  retryableNetwork,
  transientOpenAiError,
  rateLimited,
  lifecycleInterrupted,
  fatal,
}

extension OpenAiRealtimeFailureKindDetails on OpenAiRealtimeFailureKind {
  bool get isRetryable {
    return switch (this) {
      OpenAiRealtimeFailureKind.retryableNetwork ||
      OpenAiRealtimeFailureKind.transientOpenAiError ||
      OpenAiRealtimeFailureKind.rateLimited ||
      OpenAiRealtimeFailureKind.lifecycleInterrupted => true,
      _ => false,
    };
  }

  bool get isCredentialFailure {
    return switch (this) {
      OpenAiRealtimeFailureKind.credentialExpired ||
      OpenAiRealtimeFailureKind.credentialRejected => true,
      _ => false,
    };
  }
}

class OpenAiRealtimeFailure {
  const OpenAiRealtimeFailure({
    required this.kind,
    required this.diagnosticCode,
  });

  factory OpenAiRealtimeFailure.fromRealtimeError(OpenAiRealtimeError error) {
    return OpenAiRealtimeFailure.classifyCode(error.code ?? error.type);
  }

  factory OpenAiRealtimeFailure.fromSocketError(Object error) {
    if (error is OpenAiRealtimeStartupException) {
      return OpenAiRealtimeFailure.classifyCode(error.code);
    }
    if (error is OpenAiRealtimeTranscriptionStartupException) {
      return OpenAiRealtimeFailure.classifyCode(error.code);
    }

    final diagnosticCode = _socketDiagnosticCode(error);
    final classified = OpenAiRealtimeFailure.classifyCode(diagnosticCode);
    if (classified.kind != OpenAiRealtimeFailureKind.fatal) {
      return classified;
    }

    return OpenAiRealtimeFailure(
      kind: OpenAiRealtimeFailureKind.retryableNetwork,
      diagnosticCode: diagnosticCode,
    );
  }

  factory OpenAiRealtimeFailure.sessionClosed() {
    return const OpenAiRealtimeFailure(
      kind: OpenAiRealtimeFailureKind.retryableNetwork,
      diagnosticCode: 'socket.closed',
    );
  }

  factory OpenAiRealtimeFailure.lifecycleInterrupted() {
    return const OpenAiRealtimeFailure(
      kind: OpenAiRealtimeFailureKind.lifecycleInterrupted,
      diagnosticCode: 'app.lifecycle_interrupted',
    );
  }

  factory OpenAiRealtimeFailure.classifyCode(String? rawCode) {
    final code = _normalizeCode(rawCode);
    if (code.isEmpty) {
      return const OpenAiRealtimeFailure(
        kind: OpenAiRealtimeFailureKind.fatal,
        diagnosticCode: 'unknown',
      );
    }

    if (_containsAny(code, const [
      'session_expired',
      'expired_session',
      'token_expired',
      'client_secret_expired',
      'credential_expired',
    ])) {
      return OpenAiRealtimeFailure(
        kind: OpenAiRealtimeFailureKind.credentialExpired,
        diagnosticCode: code,
      );
    }

    if (_containsAny(code, const [
      'invalid_api_key',
      'authentication',
      'unauthorized',
      'forbidden',
      'invalid_client_secret',
      'credential_rejected',
      'insufficient_quota',
      'payment_required',
      'billing',
      'quota_exceeded',
      'model_not_found',
      'model_access',
      'permission_denied',
      'access_denied',
      'not_authorized',
      'project_not_found',
      'organization_not_found',
      '401',
      '403',
      '404',
    ])) {
      return OpenAiRealtimeFailure(
        kind: OpenAiRealtimeFailureKind.credentialRejected,
        diagnosticCode: code,
      );
    }

    if (_containsAny(code, const [
      'invalid_request',
      'invalid_event',
      'invalid_session',
      'invalid_value',
      'invalid_type',
      'missing_required',
      'missing_parameter',
      'unknown_parameter',
      'unknown_field',
      'unsupported_model',
      'unsupported_session',
      'unsupported_format',
      'bad_request',
      '400',
    ])) {
      return OpenAiRealtimeFailure(
        kind: OpenAiRealtimeFailureKind.configurationRejected,
        diagnosticCode: code,
      );
    }

    if (_containsAny(code, const [
      'unsupported_language',
      'unsupported_output_language',
      'unsupported_audio_language',
      'invalid_language',
      'language_not_supported',
    ])) {
      return OpenAiRealtimeFailure(
        kind: OpenAiRealtimeFailureKind.unsupportedLanguage,
        diagnosticCode: code,
      );
    }

    if (_containsAny(code, const [
      'rate_limit',
      'rate_limited',
      'too_many_requests',
      '429',
    ])) {
      return OpenAiRealtimeFailure(
        kind: OpenAiRealtimeFailureKind.rateLimited,
        diagnosticCode: code,
      );
    }

    if (_containsAny(code, const [
      'socket',
      'network',
      'connection',
      'timeout',
    ])) {
      return OpenAiRealtimeFailure(
        kind: OpenAiRealtimeFailureKind.retryableNetwork,
        diagnosticCode: code,
      );
    }

    if (_containsAny(code, const [
      'server_error',
      'internal_error',
      'service_unavailable',
      'temporarily_unavailable',
      'overloaded',
      '500',
      '502',
      '503',
      '504',
    ])) {
      return OpenAiRealtimeFailure(
        kind: OpenAiRealtimeFailureKind.transientOpenAiError,
        diagnosticCode: code,
      );
    }

    return OpenAiRealtimeFailure(
      kind: OpenAiRealtimeFailureKind.fatal,
      diagnosticCode: code,
    );
  }

  final OpenAiRealtimeFailureKind kind;
  final String diagnosticCode;
}

enum OpenAiRealtimeRecoveryAction {
  reconnectAfterBackoff,
  credentialInvalid,
  unsupportedLanguage,
  offline,
  fatalError,
}

class OpenAiRealtimeReconnectDecision {
  const OpenAiRealtimeReconnectDecision({
    required this.action,
    required this.failure,
    required this.retryAttempt,
    required this.delay,
  });

  final OpenAiRealtimeRecoveryAction action;
  final OpenAiRealtimeFailure failure;
  final int retryAttempt;
  final Duration delay;

  bool get shouldRetry =>
      action == OpenAiRealtimeRecoveryAction.reconnectAfterBackoff;

  String get userFacingNotice {
    return switch (action) {
      OpenAiRealtimeRecoveryAction.reconnectAfterBackoff => switch (failure
          .kind) {
        OpenAiRealtimeFailureKind.rateLimited =>
          'OpenAI is rate limiting this live session. Retrying shortly.',
        OpenAiRealtimeFailureKind.transientOpenAiError =>
          'OpenAI realtime is temporarily unavailable. Retrying shortly.',
        OpenAiRealtimeFailureKind.lifecycleInterrupted =>
          'Live translation was interrupted by the app lifecycle. Reconnecting shortly.',
        _ => 'Connection interrupted. Reconnecting to OpenAI shortly.',
      },
      OpenAiRealtimeRecoveryAction.credentialInvalid =>
        'OpenAI credential or project access was rejected. Update the credential stored on this device.',
      OpenAiRealtimeRecoveryAction.unsupportedLanguage =>
        'The selected language is not available for this realtime route.',
      OpenAiRealtimeRecoveryAction.offline => switch (failure.kind) {
        OpenAiRealtimeFailureKind.lifecycleInterrupted =>
          'The app could not resume the live session. Live translation is paused.',
        _ => 'Network connection appears offline. Live translation is paused.',
      },
      OpenAiRealtimeRecoveryAction.fatalError => switch (failure.kind) {
        OpenAiRealtimeFailureKind.configurationRejected =>
          'OpenAI rejected the realtime session setup. Install the latest debug build or share the sanitized diagnostics.',
        OpenAiRealtimeFailureKind.rateLimited =>
          'OpenAI rate limits persisted after retries. Restart when quota is available.',
        OpenAiRealtimeFailureKind.transientOpenAiError =>
          'OpenAI realtime remained unavailable after retries. Restart when ready.',
        _ => 'OpenAI realtime session stopped. Restart the meeting when ready.',
      },
    };
  }
}

class OpenAiRealtimeReconnectPolicy {
  const OpenAiRealtimeReconnectPolicy({
    this.maxAttempts = 4,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 8),
    this.jitterRatio = 0.2,
  }) : assert(maxAttempts > 0),
       assert(jitterRatio >= 0);

  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final double jitterRatio;

  bool canRetry(int retryAttempt) {
    return retryAttempt >= 1 && retryAttempt <= maxAttempts;
  }

  Duration delayForAttempt(int retryAttempt, {double jitterSample = 0.5}) {
    final safeAttempt = retryAttempt < 1 ? 1 : retryAttempt;
    var delayMs = math.max(0, initialDelay.inMilliseconds);
    for (var attempt = 1; attempt < safeAttempt; attempt++) {
      delayMs *= 2;
    }

    final cappedMs = math.min(delayMs, math.max(0, maxDelay.inMilliseconds));
    final boundedJitterRatio = jitterRatio.clamp(0.0, 1.0);
    final boundedSample = jitterSample.clamp(0.0, 1.0);
    final jitterOffset =
        ((boundedSample * 2) - 1) * cappedMs * boundedJitterRatio;
    final jitteredMs = math.max(0, (cappedMs + jitterOffset).round());
    return Duration(milliseconds: jitteredMs);
  }

  OpenAiRealtimeReconnectDecision plan({
    required OpenAiRealtimeFailure failure,
    required int retryAttempt,
    double jitterSample = 0.5,
  }) {
    if (failure.kind.isCredentialFailure) {
      return OpenAiRealtimeReconnectDecision(
        action: OpenAiRealtimeRecoveryAction.credentialInvalid,
        failure: failure,
        retryAttempt: retryAttempt,
        delay: Duration.zero,
      );
    }

    if (failure.kind == OpenAiRealtimeFailureKind.unsupportedLanguage) {
      return OpenAiRealtimeReconnectDecision(
        action: OpenAiRealtimeRecoveryAction.unsupportedLanguage,
        failure: failure,
        retryAttempt: retryAttempt,
        delay: Duration.zero,
      );
    }

    if (!failure.kind.isRetryable) {
      return OpenAiRealtimeReconnectDecision(
        action: OpenAiRealtimeRecoveryAction.fatalError,
        failure: failure,
        retryAttempt: retryAttempt,
        delay: Duration.zero,
      );
    }

    if (canRetry(retryAttempt)) {
      return OpenAiRealtimeReconnectDecision(
        action: OpenAiRealtimeRecoveryAction.reconnectAfterBackoff,
        failure: failure,
        retryAttempt: retryAttempt,
        delay: delayForAttempt(retryAttempt, jitterSample: jitterSample),
      );
    }

    final exhaustedAction =
        failure.kind == OpenAiRealtimeFailureKind.retryableNetwork ||
            failure.kind == OpenAiRealtimeFailureKind.lifecycleInterrupted
        ? OpenAiRealtimeRecoveryAction.offline
        : OpenAiRealtimeRecoveryAction.fatalError;
    return OpenAiRealtimeReconnectDecision(
      action: exhaustedAction,
      failure: failure,
      retryAttempt: retryAttempt,
      delay: Duration.zero,
    );
  }
}

bool _containsAny(String code, Iterable<String> needles) {
  return needles.any(code.contains);
}

String _normalizeCode(String? rawCode) {
  if (rawCode == null) {
    return '';
  }

  return rawCode.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9_.:-]+'),
    '_',
  );
}

String _socketDiagnosticCode(Object error) {
  final raw = '${error.runtimeType} $error'.toLowerCase();
  for (final status in const [
    '401',
    '403',
    '404',
    '429',
    '500',
    '502',
    '503',
    '504',
  ]) {
    if (raw.contains(status)) {
      return 'socket.http_$status';
    }
  }

  if (_containsAny(raw, const ['unauthorized', 'authentication'])) {
    return 'socket.unauthorized';
  }
  if (raw.contains('forbidden')) {
    return 'socket.forbidden';
  }
  if (_containsAny(raw, const ['too many requests', 'rate limit'])) {
    return 'socket.rate_limited';
  }
  if (_containsAny(raw, const ['timeout', 'connection', 'network', 'socket'])) {
    return 'socket.connection_error';
  }

  return error.runtimeType.toString();
}
