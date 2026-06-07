import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../diagnostics/privacy_safe_diagnostics.dart';
import '../diagnostics/realtime_event_debug_recorder.dart';
import 'openai_configuration.dart';

typedef RealtimeTranscriptionWebSocketFactory =
    Future<WebSocket> Function(Uri uri, Map<String, dynamic> headers);

abstract interface class AudioTranscriptionGateway {
  Future<AudioTranscriptionSession> connect({
    required OpenAiRealtimeTranscriptionConfig config,
    required String credential,
  });
}

abstract interface class AudioTranscriptionSession {
  Stream<OpenAiRealtimeTranscriptionEvent> get events;

  void sendSessionUpdate();

  void appendPcm16Audio(List<int> pcm16Audio);

  void commitInputAudioBuffer();

  Future<void> closeImmediately();
}

class OpenAiRealtimeTranscriptionConfig {
  const OpenAiRealtimeTranscriptionConfig({
    this.inputAudioRate = 24000,
    this.languageHint,
    this.transcriptionDelay,
    this.transcriptionModel = OpenAiConfiguration.translationTranscriptionModel,
  });

  final int inputAudioRate;
  final String? languageHint;
  final String? transcriptionDelay;
  final String transcriptionModel;

  Uri webSocketUri({Uri? baseUri}) {
    final base =
        baseUri ?? Uri.parse(OpenAiConfiguration.realtimeWebSocketBaseUrl);
    final path = _joinPath(base.path, OpenAiConfiguration.realtimeWebSocketPath);
    return base.replace(path: path, queryParameters: {'model': transcriptionModel});
  }

  Map<String, Object?> initialSessionUpdate() {
    final hint = languageHint?.trim().toLowerCase();
    final delay = transcriptionDelay?.trim().toLowerCase();
    return {
      'type': 'session.update',
      'session': {
        'type': 'transcription',
        'audio': {
          'input': {
            'format': {'type': 'audio/pcm', 'rate': inputAudioRate},
            'transcription': {
              'model': transcriptionModel,
              if (hint != null && hint.isNotEmpty && hint != 'auto')
                'language': hint,
              if (delay != null && delay.isNotEmpty) 'delay': delay,
            },
            // gpt-realtime-whisper transcription sessions require manual
            // commits, so app-side batching owns the turn boundary.
            'turn_detection': null,
          },
        },
      },
    };
  }

  Map<String, Object?> audioAppendEvent(List<int> pcm16Audio) {
    return {
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm16Audio),
    };
  }

  Map<String, Object?> inputAudioCommitEvent() {
    return {'type': 'input_audio_buffer.commit'};
  }
}

class OpenAiRealtimeTranscriptionGateway implements AudioTranscriptionGateway {
  OpenAiRealtimeTranscriptionGateway({
    Uri? webSocketBaseUri,
    RealtimeTranscriptionWebSocketFactory? webSocketFactory,
    this.diagnostics = const PrivacySafeDiagnostics(),
    this.debugRecorder = const RealtimeEventDebugRecorder(),
  }) : webSocketBaseUri =
           webSocketBaseUri ??
           Uri.parse(OpenAiConfiguration.realtimeWebSocketBaseUrl),
       _webSocketFactory =
           webSocketFactory ??
           ((uri, headers) {
             return WebSocket.connect(uri.toString(), headers: headers);
           });

  final Uri webSocketBaseUri;
  final PrivacySafeDiagnostics diagnostics;
  final RealtimeEventDebugRecorder debugRecorder;
  final RealtimeTranscriptionWebSocketFactory _webSocketFactory;

  @override
  Future<AudioTranscriptionSession> connect({
    required OpenAiRealtimeTranscriptionConfig config,
    required String credential,
  }) async {
    final uri = config.webSocketUri(baseUri: webSocketBaseUri);
    diagnostics.info(
      'openai.realtime_transcription_connect_started',
      fields: {
        'operation': 'realtimeTranscription.connect',
        'endpoint': uri.host,
        'model': config.transcriptionModel,
      },
    );

    final socket = await _webSocketFactory(uri, {
      HttpHeaders.authorizationHeader: 'Bearer $credential',
    });
    final session = OpenAiRealtimeTranscriptionSession._(
      socket: socket,
      config: config,
      diagnostics: diagnostics,
      debugRecorder: debugRecorder,
    );
    try {
      session.sendSessionUpdate();
      await session.waitUntilReady();
    } catch (error, stackTrace) {
      _closeTranscriptionStartupSessionNonBlocking(session);
      Error.throwWithStackTrace(error, stackTrace);
    }
    diagnostics.info(
      'openai.realtime_transcription_connect_succeeded',
      fields: {
        'operation': 'realtimeTranscription.connect',
        'endpoint': uri.host,
        'model': config.transcriptionModel,
        'result': 'success',
      },
    );
    return session;
  }
}

class OpenAiRealtimeTranscriptionSession implements AudioTranscriptionSession {
  OpenAiRealtimeTranscriptionSession._({
    required this._socket,
    required this.config,
    required this.diagnostics,
    this.debugRecorder = const RealtimeEventDebugRecorder(),
  }) {
    _subscription = _socket.listen(
      _handleSocketMessage,
      onError: _handleSocketError,
      onDone: _handleSocketDone,
      cancelOnError: false,
    );
  }

  final OpenAiRealtimeTranscriptionConfig config;
  final PrivacySafeDiagnostics diagnostics;
  final RealtimeEventDebugRecorder debugRecorder;
  final WebSocket _socket;
  late final StreamSubscription<dynamic> _subscription;
  final StreamController<OpenAiRealtimeTranscriptionEvent> _events =
      StreamController<OpenAiRealtimeTranscriptionEvent>();
  final Completer<void> _ready = Completer<void>();
  bool _isClosed = false;

  @override
  Stream<OpenAiRealtimeTranscriptionEvent> get events => _events.stream;

  Future<void> waitUntilReady() => _ready.future;

  @override
  void sendSessionUpdate() {
    _send(config.initialSessionUpdate());
  }

  @override
  void appendPcm16Audio(List<int> pcm16Audio) {
    _send(config.audioAppendEvent(pcm16Audio));
  }

  @override
  void commitInputAudioBuffer() {
    _send(config.inputAudioCommitEvent());
  }

  @override
  Future<void> closeImmediately() async {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    try {
      await _socket.close();
    } finally {
      await _subscription.cancel();
      await _closeEventStream();
    }
  }

  Future<void> _closeEventStream() async {
    if (_events.isClosed) {
      return;
    }

    if (_events.hasListener) {
      await _events.close();
      return;
    }

    unawaited(_events.close());
  }

  void _send(Map<String, Object?> event) {
    _socket.add(jsonEncode(event));
  }

  void _handleSocketMessage(dynamic message) {
    debugRecorder.recordRawMessage(message);
    final event = OpenAiRealtimeTranscriptionEventParser.parseMessage(message);
    if (event == null || _events.isClosed) {
      return;
    }

    _emitEvent(event);
    if (event is OpenAiRealtimeTranscriptionSessionClosed) {
      unawaited(closeImmediately());
    }
  }

  void _handleSocketError(Object error) {
    if (_events.isClosed) {
      return;
    }

    diagnostics.warning(
      'openai.realtime_transcription_socket_error',
      fields: {
        'operation': 'realtimeTranscription.receive',
        'model': config.transcriptionModel,
        'errorCode': error.runtimeType.toString(),
        'result': 'socketError',
      },
    );
    _emitEvent(
      OpenAiRealtimeTranscriptionError(
        type: 'socket.error',
        code: error.runtimeType.toString(),
        eventId: null,
        param: null,
      ),
    );
  }

  void _handleSocketDone() {
    if (_events.isClosed) {
      return;
    }

    final closeReason = _socket.closeReason;
    if (closeReason != null && closeReason.isNotEmpty) {
      _emitEvent(
        OpenAiRealtimeTranscriptionError(
          type: 'socket.closed',
          code: closeReason,
          eventId: null,
          param: null,
        ),
      );
    }

    _emitEvent(
      const OpenAiRealtimeTranscriptionSessionClosed(type: 'socket.closed'),
    );
    unawaited(_events.close());
  }

  void _emitEvent(OpenAiRealtimeTranscriptionEvent event) {
    if (_events.isClosed) {
      return;
    }

    if (!_ready.isCompleted) {
      if (event is OpenAiRealtimeTranscriptionSessionLifecycleEvent &&
          event.type == 'session.updated') {
        _ready.complete();
      } else if (event is OpenAiRealtimeTranscriptionError) {
        _ready.completeError(
          OpenAiRealtimeTranscriptionStartupException.fromError(event),
        );
      } else if (event is OpenAiRealtimeTranscriptionSessionClosed) {
        _ready.completeError(
          const OpenAiRealtimeTranscriptionStartupException('socket.closed'),
        );
      }
    }

    _events.add(event);
  }
}

void _closeTranscriptionStartupSessionNonBlocking(
  OpenAiRealtimeTranscriptionSession session,
) {
  unawaited(
    session
        .closeImmediately()
        .timeout(const Duration(milliseconds: 250), onTimeout: () {})
        .catchError((Object error, StackTrace stackTrace) {}),
  );
}

sealed class OpenAiRealtimeTranscriptionEvent {
  const OpenAiRealtimeTranscriptionEvent({required this.type});

  final String type;
}

class OpenAiRealtimeTranscriptionSessionLifecycleEvent
    extends OpenAiRealtimeTranscriptionEvent {
  const OpenAiRealtimeTranscriptionSessionLifecycleEvent({required super.type});
}

class OpenAiRealtimeTranscriptionDelta
    extends OpenAiRealtimeTranscriptionEvent {
  const OpenAiRealtimeTranscriptionDelta({
    required super.type,
    required this.delta,
    this.itemId,
    this.languageCode,
  });

  final String delta;
  final String? itemId;
  final String? languageCode;
}

class OpenAiRealtimeTranscriptionCompleted
    extends OpenAiRealtimeTranscriptionEvent {
  const OpenAiRealtimeTranscriptionCompleted({
    required super.type,
    required this.transcript,
    this.itemId,
    this.languageCode,
  });

  final String transcript;
  final String? itemId;
  final String? languageCode;
}

class OpenAiRealtimeTranscriptionBufferCommitted
    extends OpenAiRealtimeTranscriptionEvent {
  const OpenAiRealtimeTranscriptionBufferCommitted({
    required super.type,
    this.itemId,
  });

  final String? itemId;
}

class OpenAiRealtimeTranscriptionError
    extends OpenAiRealtimeTranscriptionEvent {
  const OpenAiRealtimeTranscriptionError({
    required super.type,
    required this.code,
    required this.eventId,
    required this.param,
  });

  final String? code;
  final String? eventId;
  final String? param;
}

class OpenAiRealtimeTranscriptionStartupException implements Exception {
  const OpenAiRealtimeTranscriptionStartupException(this.code);

  factory OpenAiRealtimeTranscriptionStartupException.fromError(
    OpenAiRealtimeTranscriptionError error,
  ) {
    return OpenAiRealtimeTranscriptionStartupException(error.code ?? error.type);
  }

  final String code;

  @override
  String toString() => 'OpenAiRealtimeTranscriptionStartupException($code)';
}

class OpenAiRealtimeTranscriptionSessionClosed
    extends OpenAiRealtimeTranscriptionEvent {
  const OpenAiRealtimeTranscriptionSessionClosed({required super.type});
}

class OpenAiRealtimeTranscriptionUnknownEvent
    extends OpenAiRealtimeTranscriptionEvent {
  const OpenAiRealtimeTranscriptionUnknownEvent({required super.type});
}

abstract final class OpenAiRealtimeTranscriptionEventParser {
  static OpenAiRealtimeTranscriptionEvent? parseMessage(dynamic message) {
    if (message is! String) {
      return null;
    }

    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    return parse(decoded);
  }

  static OpenAiRealtimeTranscriptionEvent? parse(Map<String, dynamic> event) {
    final type = event['type'];
    if (type is! String || type.isEmpty) {
      return null;
    }

    if (type == 'session.created' || type == 'session.updated') {
      return OpenAiRealtimeTranscriptionSessionLifecycleEvent(type: type);
    }

    if (type == 'session.closed' || type == 'socket.closed') {
      return OpenAiRealtimeTranscriptionSessionClosed(type: type);
    }

    if (type == 'error') {
      final error = event['error'];
      final code = error is Map<String, dynamic>
          ? error['code']
          : event['code'];
      final eventId = error is Map<String, dynamic>
          ? error['event_id']
          : event['event_id'];
      final param = error is Map<String, dynamic>
          ? error['param']
          : event['param'];
      return OpenAiRealtimeTranscriptionError(
        type: type,
        code: code is String ? code : null,
        eventId: eventId is String ? eventId : null,
        param: param is String ? param : null,
      );
    }

    if (type == 'input_audio_buffer.committed') {
      return OpenAiRealtimeTranscriptionBufferCommitted(
        type: type,
        itemId: _optionalItemId(event),
      );
    }

    final delta = _optionalDelta(event);
    if (delta != null && type.contains('input_audio_transcription.delta')) {
      return OpenAiRealtimeTranscriptionDelta(
        type: type,
        delta: delta,
        itemId: _optionalItemId(event),
        languageCode: _optionalLanguageCode(event),
      );
    }

    final transcript = _optionalTranscript(event);
    if (transcript != null &&
        type.contains('input_audio_transcription.completed')) {
      return OpenAiRealtimeTranscriptionCompleted(
        type: type,
        transcript: transcript,
        itemId: _optionalItemId(event),
        languageCode: _optionalLanguageCode(event),
      );
    }

    return OpenAiRealtimeTranscriptionUnknownEvent(type: type);
  }

  static String? _optionalTranscript(Map<String, dynamic> event) {
    final transcript = event['transcript'] ?? event['text'];
    if (transcript is String && transcript.trim().isNotEmpty) {
      return transcript.trim();
    }

    return null;
  }

  static String? _optionalDelta(Map<String, dynamic> event) {
    final delta = event['delta'] ?? event['text'];
    if (delta is String && delta.trim().isNotEmpty) {
      return delta;
    }

    return null;
  }

  static String? _optionalItemId(Map<String, dynamic> event) {
    final itemId = event['item_id'] ?? event['itemId'];
    if (itemId is String && itemId.trim().isNotEmpty) {
      return itemId.trim();
    }

    final item = event['item'];
    if (item is Map<String, dynamic>) {
      final nestedItemId = item['id'];
      if (nestedItemId is String && nestedItemId.trim().isNotEmpty) {
        return nestedItemId.trim();
      }
    }

    return null;
  }

  static String? _optionalLanguageCode(Map<String, dynamic> event) {
    final language = event['language'] ?? event['language_code'];
    if (language is String && language.trim().isNotEmpty) {
      return language.trim().toLowerCase();
    }

    return null;
  }
}

String _joinPath(String basePath, String childPath) {
  final normalizedBase = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  final normalizedChild = childPath.startsWith('/')
      ? childPath.substring(1)
      : childPath;
  if (normalizedBase.isEmpty) {
    return '/$normalizedChild';
  }
  return '$normalizedBase/$normalizedChild';
}
