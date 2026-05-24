import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_resilience.dart';
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

  test('classifies websocket upgrade auth failures as credential rejection', () {
    final failure = OpenAiRealtimeFailure.fromSocketError(
      Exception(
        'WebSocketException: Connection was not upgraded to websocket, '
        'HTTP status code: 401',
      ),
    );

    expect(failure.kind, OpenAiRealtimeFailureKind.credentialRejected);
    expect(failure.diagnosticCode, 'socket.http_401');
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
