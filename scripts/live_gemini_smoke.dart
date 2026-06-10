import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:realtime_translate_mobile/src/openai/openai_configuration.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final realKeyMode = args.contains('--setup-complete');
  if (realKeyMode) {
    final credential = Platform.environment['GEMINI_API_KEY']?.trim();
    if (credential == null || credential.isEmpty) {
      stderr.writeln(
        'gemini-smoke setupComplete=skipped reason=missing_GEMINI_API_KEY',
      );
      exitCode = 2;
      return;
    }
    await _runSetupCompleteSmoke(credential: credential);
    return;
  }

  await _runInvalidKeyAuthSmoke();
}

Future<void> _runInvalidKeyAuthSmoke() async {
  const invalidCredential = 'invalid-local-gemini-placeholder';
  final result = await _attemptSetup(
    credential: invalidCredential,
    targetLanguageCode: 'ar',
    allowInvalidKeySetupClose: true,
  );

  if (result.expectedAuthFailure) {
    stdout.writeln(
      'gemini-smoke invalidKeyAuth=passed model=${GeminiConfiguration.liveTranslateModel} targetLanguage=ar result=${result.safeCode}',
    );
    return;
  }

  stderr.writeln(
    'gemini-smoke invalidKeyAuth=failed model=${GeminiConfiguration.liveTranslateModel} targetLanguage=ar result=${result.safeCode}',
  );
  exitCode = 1;
}

Future<void> _runSetupCompleteSmoke({required String credential}) async {
  final result = await _attemptSetup(
    credential: credential,
    targetLanguageCode: 'en',
    allowInvalidKeySetupClose: false,
  );

  if (result.setupComplete) {
    stdout.writeln(
      'gemini-smoke setupComplete=passed model=${GeminiConfiguration.liveTranslateModel} targetLanguage=en',
    );
    return;
  }

  stderr.writeln(
    'gemini-smoke setupComplete=failed model=${GeminiConfiguration.liveTranslateModel} targetLanguage=en result=${result.safeCode}',
  );
  exitCode = 1;
}

Future<_SmokeResult> _attemptSetup({
  required String credential,
  required String targetLanguageCode,
  required bool allowInvalidKeySetupClose,
}) async {
  WebSocket? socket;
  final uri = Uri.parse(
    '${GeminiConfiguration.liveTranslateWebSocketBaseUrl}${GeminiConfiguration.liveTranslateWebSocketPath}',
  ).replace(queryParameters: {'key': credential});

  try {
    socket = await WebSocket.connect(
      uri.toString(),
    ).timeout(const Duration(seconds: 15));
    final firstEvent = socket
        .map(_decodeJson)
        .where((event) => event is Map<String, Object?>)
        .cast<Map<String, Object?>>()
        .first
        .timeout(const Duration(seconds: 15));
    socket.add(
      jsonEncode(
        GeminiLiveTranslationMessages.setup(
          targetLanguageCode: targetLanguageCode,
        ),
      ),
    );
    final message = await firstEvent;
    if (_isSetupComplete(message)) {
      return const _SmokeResult.setupComplete();
    }
    if (_isAuthFailureMessage(message)) {
      return const _SmokeResult.expectedAuthFailure('auth_rejected_message');
    }
    return const _SmokeResult.failure('unexpected_message');
  } on WebSocketException catch (error) {
    final code = _safeWebSocketCode(error.message);
    if (code == 'http_401' || code == 'http_403' || code == 'unauthorized') {
      return _SmokeResult.expectedAuthFailure(code);
    }
    return _SmokeResult.failure(code);
  } on TimeoutException {
    return const _SmokeResult.failure('timeout');
  } on SocketException {
    return const _SmokeResult.failure('socket_exception');
  } on HandshakeException {
    return const _SmokeResult.failure('handshake_exception');
  } on StateError catch (error) {
    if (allowInvalidKeySetupClose && _isExpectedAuthSetupClose(error)) {
      return const _SmokeResult.expectedAuthFailure('auth_rejected_close');
    }
    return const _SmokeResult.failure('state_error');
  } catch (error) {
    final code = error.runtimeType.toString();
    if (code.toLowerCase().contains('unauthorized')) {
      return const _SmokeResult.expectedAuthFailure('unauthorized');
    }
    return _SmokeResult.failure(code);
  } finally {
    await socket?.close();
  }
}

bool _isExpectedAuthSetupClose(StateError error) {
  final message = error.message.toLowerCase();
  return message.contains('no element') ||
      message.contains('stream has already closed') ||
      message.contains('stream closed before first event');
}

String _safeWebSocketCode(String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('401')) {
    return 'http_401';
  }
  if (normalized.contains('403')) {
    return 'http_403';
  }
  if (normalized.contains('unauthorized') ||
      normalized.contains('permission_denied') ||
      normalized.contains('forbidden') ||
      normalized.contains('api key') ||
      normalized.contains('apikey')) {
    return 'unauthorized';
  }
  return 'websocket_exception';
}

Object? _decodeJson(dynamic message) {
  if (message is! String) {
    return null;
  }
  try {
    return jsonDecode(message);
  } on FormatException {
    return null;
  }
}

bool _isSetupComplete(Map<String, Object?> message) {
  return message.containsKey('setupComplete');
}

bool _isAuthFailureMessage(Map<String, Object?> message) {
  final serialized = jsonEncode(message).toLowerCase();
  return serialized.contains('unauthorized') ||
      serialized.contains('permission_denied') ||
      serialized.contains('api key') ||
      serialized.contains('apikey') ||
      serialized.contains('forbidden') ||
      serialized.contains('401') ||
      serialized.contains('403');
}

void _printUsage() {
  stdout.writeln('Usage: dart run scripts/live_gemini_smoke.dart [mode]');
  stdout.writeln('');
  stdout.writeln('Modes:');
  stdout.writeln(
    '  default            Connect with a fixed invalid key and expect auth failure.',
  );
  stdout.writeln(
    '  --setup-complete   Require GEMINI_API_KEY and expect setupComplete.',
  );
  stdout.writeln('');
  stdout.writeln(
    'Output is redacted: no credential, transcript, audio, or response payload is printed.',
  );
}

class _SmokeResult {
  const _SmokeResult._({
    required this.safeCode,
    required this.expectedAuthFailure,
    required this.setupComplete,
  });

  const _SmokeResult.expectedAuthFailure(String safeCode)
    : this._(
        safeCode: safeCode,
        expectedAuthFailure: true,
        setupComplete: false,
      );

  const _SmokeResult.setupComplete()
    : this._(
        safeCode: 'setup_complete',
        expectedAuthFailure: false,
        setupComplete: true,
      );

  const _SmokeResult.failure(String safeCode)
    : this._(
        safeCode: safeCode,
        expectedAuthFailure: false,
        setupComplete: false,
      );

  final String safeCode;
  final bool expectedAuthFailure;
  final bool setupComplete;
}
