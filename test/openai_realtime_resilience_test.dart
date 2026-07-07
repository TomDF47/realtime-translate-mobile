import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_resilience.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_transcription.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';

void main() {
  test('classifies direct OpenAI realtime failures without raw payloads', () {
    expect(
      OpenAiRealtimeFailure.classifyCode('invalid_api_key').kind,
      OpenAiRealtimeFailureKind.credentialRejected,
    );
    expect(
      OpenAiRealtimeFailure.classifyCode('session_expired').kind,
      OpenAiRealtimeFailureKind.credentialExpired,
    );
    expect(
      OpenAiRealtimeFailure.classifyCode('unsupported_output_language').kind,
      OpenAiRealtimeFailureKind.unsupportedLanguage,
    );
    expect(
      OpenAiRealtimeFailure.classifyCode('rate_limit_exceeded').kind,
      OpenAiRealtimeFailureKind.rateLimited,
    );
    expect(
      OpenAiRealtimeFailure.classifyCode('service_unavailable').kind,
      OpenAiRealtimeFailureKind.transientOpenAiError,
    );
    expect(
      OpenAiRealtimeFailure.classifyCode('invalid_request_error').kind,
      OpenAiRealtimeFailureKind.configurationRejected,
    );
    expect(
      OpenAiRealtimeFailure.sessionClosed().kind,
      OpenAiRealtimeFailureKind.retryableNetwork,
    );
  });

  test('classifies parsed realtime error events', () {
    final event = OpenAiRealtimeEventParser.parse({
      'type': 'error',
      'error': {'code': 'authentication_error', 'event_id': 'event-1'},
    });

    final failure = OpenAiRealtimeFailure.fromRealtimeError(
      event! as OpenAiRealtimeError,
    );

    expect(failure.kind, OpenAiRealtimeFailureKind.credentialRejected);
    expect(failure.diagnosticCode, 'authentication_error');
  });

  test(
    'classifies websocket upgrade auth failures as credential rejection',
    () {
      final failure = OpenAiRealtimeFailure.fromSocketError(
        Exception(
          'WebSocketException: Connection was not upgraded to websocket, '
          'HTTP status code: 401',
        ),
      );

      expect(failure.kind, OpenAiRealtimeFailureKind.credentialRejected);
      expect(failure.diagnosticCode, 'socket.http_401');
    },
  );

  test(
    'classifies websocket upgrade model access failures as credential rejection',
    () {
      final failure = OpenAiRealtimeFailure.fromSocketError(
        Exception(
          'WebSocketException: Connection was not upgraded to websocket, '
          'HTTP status code: 404',
        ),
      );

      expect(failure.kind, OpenAiRealtimeFailureKind.credentialRejected);
      expect(failure.diagnosticCode, 'socket.http_404');
    },
  );

  test('classifies startup exception code directly', () {
    final failure = OpenAiRealtimeFailure.fromSocketError(
      const OpenAiRealtimeStartupException('invalid_api_key'),
    );

    expect(failure.kind, OpenAiRealtimeFailureKind.credentialRejected);
    expect(failure.diagnosticCode, 'invalid_api_key');
  });

  test('classifies transcription startup exception code directly', () {
    final authFailure = OpenAiRealtimeFailure.fromSocketError(
      const OpenAiRealtimeTranscriptionStartupException('invalid_api_key'),
    );
    final quotaFailure = OpenAiRealtimeFailure.fromSocketError(
      const OpenAiRealtimeTranscriptionStartupException('insufficient_quota'),
    );
    final modelFailure = OpenAiRealtimeFailure.fromSocketError(
      const OpenAiRealtimeTranscriptionStartupException('model_not_found'),
    );
    final projectAccessFailure = OpenAiRealtimeFailure.fromSocketError(
      const OpenAiRealtimeTranscriptionStartupException('permission_denied'),
    );

    expect(authFailure.kind, OpenAiRealtimeFailureKind.credentialRejected);
    expect(authFailure.diagnosticCode, 'invalid_api_key');
    expect(quotaFailure.kind, OpenAiRealtimeFailureKind.credentialRejected);
    expect(quotaFailure.diagnosticCode, 'insufficient_quota');
    expect(modelFailure.kind, OpenAiRealtimeFailureKind.credentialRejected);
    expect(modelFailure.diagnosticCode, 'model_not_found');
    expect(
      projectAccessFailure.kind,
      OpenAiRealtimeFailureKind.credentialRejected,
    );
    expect(projectAccessFailure.diagnosticCode, 'permission_denied');
  });

  test('realtime configuration rejection has actionable fatal notice', () {
    const policy = OpenAiRealtimeReconnectPolicy();
    final decision = policy.plan(
      failure: OpenAiRealtimeFailure.classifyCode('invalid_request_error'),
      retryAttempt: 1,
    );

    expect(decision.action, OpenAiRealtimeRecoveryAction.fatalError);
    expect(
      decision.failure.kind,
      OpenAiRealtimeFailureKind.configurationRejected,
    );
    expect(
      decision.userFacingNotice,
      'OpenAI rejected the realtime session setup. Install the latest debug build or share the sanitized diagnostics.',
    );
  });

  test('plans bounded exponential backoff with deterministic jitter', () {
    const policy = OpenAiRealtimeReconnectPolicy(
      maxAttempts: 3,
      initialDelay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 3),
      jitterRatio: 0.2,
    );
    final failure = OpenAiRealtimeFailure.sessionClosed();

    final first = policy.plan(
      failure: failure,
      retryAttempt: 1,
      jitterSample: 1,
    );
    final third = policy.plan(
      failure: failure,
      retryAttempt: 3,
      jitterSample: 0,
    );
    final exhausted = policy.plan(
      failure: failure,
      retryAttempt: 4,
      jitterSample: 0.5,
    );

    expect(first.action, OpenAiRealtimeRecoveryAction.reconnectAfterBackoff);
    expect(first.delay, const Duration(milliseconds: 1200));
    expect(third.delay, const Duration(milliseconds: 2400));
    expect(exhausted.action, OpenAiRealtimeRecoveryAction.offline);
    expect(exhausted.delay, Duration.zero);
  });

  test(
    'does not retry credential, unsupported-language, or fatal failures',
    () {
      const policy = OpenAiRealtimeReconnectPolicy();

      expect(
        policy
            .plan(
              failure: OpenAiRealtimeFailure.classifyCode('invalid_api_key'),
              retryAttempt: 1,
            )
            .action,
        OpenAiRealtimeRecoveryAction.credentialInvalid,
      );
      expect(
        policy
            .plan(
              failure: OpenAiRealtimeFailure.classifyCode(
                'unsupported_language',
              ),
              retryAttempt: 1,
            )
            .action,
        OpenAiRealtimeRecoveryAction.unsupportedLanguage,
      );
      expect(
        policy
            .plan(
              failure: OpenAiRealtimeFailure.classifyCode('invalid_request'),
              retryAttempt: 1,
            )
            .action,
        OpenAiRealtimeRecoveryAction.fatalError,
      );
    },
  );
}
