import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../diagnostics/privacy_safe_diagnostics.dart';
import 'openai_configuration.dart';

typedef RealtimeWebSocketFactory =
    Future<WebSocket> Function(Uri uri, Map<String, dynamic> headers);

abstract interface class RealtimeTranslationGateway {
  Future<RealtimeTranslationSession> connect({
    required OpenAiRealtimeTranslationConfig config,
    required String credential,
  });
}

abstract interface class RealtimeTranslationSession {
  Stream<OpenAiRealtimeEvent> get events;

  void sendSessionUpdate();

  void appendPcm16Audio(List<int> pcm16Audio);

  void commitInputAudioBuffer();

  void createResponse();

  Future<void> closeGracefully();

  Future<void> closeImmediately();
}

enum OpenAiRealtimeTranslationProfile { primaryRealtime2, dedicatedTranslation }

extension OpenAiRealtimeTranslationProfileDetails
    on OpenAiRealtimeTranslationProfile {
  String get model {
    return switch (this) {
      OpenAiRealtimeTranslationProfile.primaryRealtime2 =>
        OpenAiConfiguration.realtimeModel,
      OpenAiRealtimeTranslationProfile.dedicatedTranslation =>
        OpenAiConfiguration.translationFallbackModel,
    };
  }

  String get path {
    return switch (this) {
      OpenAiRealtimeTranslationProfile.primaryRealtime2 =>
        OpenAiConfiguration.realtimeWebSocketPath,
      OpenAiRealtimeTranslationProfile.dedicatedTranslation =>
        OpenAiConfiguration.translationWebSocketPath,
    };
  }

  String get appendAudioEventType {
    return switch (this) {
      OpenAiRealtimeTranslationProfile.primaryRealtime2 =>
        'input_audio_buffer.append',
      OpenAiRealtimeTranslationProfile.dedicatedTranslation =>
        'session.input_audio_buffer.append',
    };
  }

  bool get supportsGracefulClose {
    return this == OpenAiRealtimeTranslationProfile.dedicatedTranslation;
  }

  bool get usesStandardConversationLifecycle {
    return this == OpenAiRealtimeTranslationProfile.primaryRealtime2;
  }
}

class OpenAiRealtimeTranslationConfig {
  const OpenAiRealtimeTranslationConfig({
    required this.targetLanguageCode,
    this.sourceLanguageCode = 'auto',
    this.profile = OpenAiRealtimeTranslationProfile.primaryRealtime2,
    this.inputAudioRate = 24000,
    this.outputVoice = 'marin',
  });

  final String sourceLanguageCode;
  final String targetLanguageCode;
  final OpenAiRealtimeTranslationProfile profile;
  final int inputAudioRate;
  final String outputVoice;

  Uri webSocketUri({Uri? baseUri}) {
    final base =
        baseUri ?? Uri.parse(OpenAiConfiguration.realtimeWebSocketBaseUrl);
    final path = _joinPath(base.path, profile.path);
    return base.replace(path: path, queryParameters: {'model': profile.model});
  }

  Map<String, Object?> initialSessionUpdate() {
    return switch (profile) {
      OpenAiRealtimeTranslationProfile.primaryRealtime2 =>
        _primaryRealtime2SessionUpdate(),
      OpenAiRealtimeTranslationProfile.dedicatedTranslation =>
        _dedicatedTranslationSessionUpdate(),
    };
  }

  Map<String, Object?> audioAppendEvent(List<int> pcm16Audio) {
    return {
      'type': profile.appendAudioEventType,
      'audio': base64Encode(pcm16Audio),
    };
  }

  Map<String, Object?>? inputAudioCommitEvent() {
    if (!profile.usesStandardConversationLifecycle) {
      return null;
    }

    return {'type': 'input_audio_buffer.commit'};
  }

  Map<String, Object?>? responseCreateEvent() {
    if (!profile.usesStandardConversationLifecycle) {
      return null;
    }

    return {'type': 'response.create'};
  }

  Map<String, Object?>? gracefulCloseEvent() {
    if (!profile.supportsGracefulClose) {
      return null;
    }

    return {'type': 'session.close'};
  }

  Map<String, Object?> _primaryRealtime2SessionUpdate() {
    final sourceLabel = sourceLanguageCode == 'auto'
        ? 'auto-detected source language'
        : sourceLanguageCode;
    return {
      'type': 'session.update',
      'session': {
        'type': 'realtime',
        'model': OpenAiConfiguration.realtimeModel,
        'output_modalities': ['audio'],
        'audio': {
          'input': {
            'format': {'type': 'audio/pcm', 'rate': inputAudioRate},
            'turn_detection': {'type': 'semantic_vad'},
          },
          'output': {
            'format': {'type': 'audio/pcm', 'rate': inputAudioRate},
            'voice': outputVoice,
          },
        },
        'instructions':
            'Translate incoming speech from $sourceLabel into '
            '$targetLanguageCode. Return translated audio and transcript '
            'deltas only. Preserve names, numbers, dates, and meeting terms.',
      },
    };
  }

  Map<String, Object?> _dedicatedTranslationSessionUpdate() {
    return {
      'type': 'session.update',
      'session': {
        'audio': {
          'output': {'language': targetLanguageCode},
        },
      },
    };
  }
}

class OpenAiRealtimeTranslationGateway implements RealtimeTranslationGateway {
  OpenAiRealtimeTranslationGateway({
    Uri? webSocketBaseUri,
    RealtimeWebSocketFactory? webSocketFactory,
    this.diagnostics = const PrivacySafeDiagnostics(),
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
  final RealtimeWebSocketFactory _webSocketFactory;

  @override
  Future<OpenAiRealtimeTranslationSession> connect({
    required OpenAiRealtimeTranslationConfig config,
    required String credential,
  }) async {
    final uri = config.webSocketUri(baseUri: webSocketBaseUri);
    diagnostics.info(
      'openai.realtime_connect_started',
      fields: {
        'operation': 'realtime.connect',
        'endpoint': uri.host,
        'model': config.profile.model,
        'realtimeProfile': config.profile.name,
        'targetLanguage': config.targetLanguageCode,
      },
    );

    final socket = await _webSocketFactory(uri, {
      HttpHeaders.authorizationHeader: 'Bearer $credential',
    });
    final session = OpenAiRealtimeTranslationSession._(
      socket: socket,
      config: config,
      diagnostics: diagnostics,
    );
    session.sendSessionUpdate();
    diagnostics.info(
      'openai.realtime_connect_succeeded',
      fields: {
        'operation': 'realtime.connect',
        'endpoint': uri.host,
        'model': config.profile.model,
        'realtimeProfile': config.profile.name,
        'targetLanguage': config.targetLanguageCode,
        'result': 'success',
      },
    );
    return session;
  }
}

class OpenAiRealtimeTranslationSession implements RealtimeTranslationSession {
  OpenAiRealtimeTranslationSession._({
    required this._socket,
    required this.config,
    required this.diagnostics,
  }) {
    _subscription = _socket.listen(
      _handleSocketMessage,
      onError: _handleSocketError,
      onDone: _handleSocketDone,
      cancelOnError: false,
    );
  }

  final OpenAiRealtimeTranslationConfig config;
  final PrivacySafeDiagnostics diagnostics;
  final WebSocket _socket;
  late final StreamSubscription<dynamic> _subscription;
  final StreamController<OpenAiRealtimeEvent> _events =
      StreamController<OpenAiRealtimeEvent>.broadcast();
  bool _closeSent = false;
  bool _isClosed = false;

  @override
  Stream<OpenAiRealtimeEvent> get events => _events.stream;

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
    final event = config.inputAudioCommitEvent();
    if (event == null) {
      return;
    }

    _send(event);
  }

  @override
  void createResponse() {
    final event = config.responseCreateEvent();
    if (event == null) {
      return;
    }

    _send(event);
  }

  @override
  Future<void> closeGracefully() async {
    if (_closeSent) {
      return;
    }

    _closeSent = true;
    final closeEvent = config.gracefulCloseEvent();
    if (closeEvent != null) {
      _send(closeEvent);
    }
    await closeImmediately();
  }

  @override
  Future<void> closeImmediately() async {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    await _subscription.cancel();
    await _socket.close();
    await _events.close();
  }

  void _send(Map<String, Object?> event) {
    _socket.add(jsonEncode(event));
  }

  void _handleSocketMessage(dynamic message) {
    final event = OpenAiRealtimeEventParser.parseMessage(message);
    if (event == null || _events.isClosed) {
      return;
    }

    _events.add(event);
    if (event is OpenAiRealtimeSessionClosed) {
      unawaited(closeImmediately());
    }
  }

  void _handleSocketError(Object error) {
    if (_events.isClosed) {
      return;
    }

    diagnostics.warning(
      'openai.realtime_socket_error',
      fields: {
        'operation': 'realtime.receive',
        'model': config.profile.model,
        'realtimeProfile': config.profile.name,
        'targetLanguage': config.targetLanguageCode,
        'errorCode': error.runtimeType.toString(),
        'result': 'socketError',
      },
    );
    _events.add(
      OpenAiRealtimeError(
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

    _events.add(const OpenAiRealtimeSessionClosed(type: 'socket.closed'));
    unawaited(_events.close());
  }
}

enum OpenAiRealtimeTranscriptKind { source, translation }

sealed class OpenAiRealtimeEvent {
  const OpenAiRealtimeEvent({required this.type});

  final String type;
}

class OpenAiRealtimeSessionLifecycleEvent extends OpenAiRealtimeEvent {
  const OpenAiRealtimeSessionLifecycleEvent({required super.type});
}

class OpenAiRealtimeTranscriptDelta extends OpenAiRealtimeEvent {
  const OpenAiRealtimeTranscriptDelta({
    required super.type,
    required this.kind,
    required this.delta,
  });

  final OpenAiRealtimeTranscriptKind kind;
  final String delta;
}

class OpenAiRealtimeTranscriptCompleted extends OpenAiRealtimeEvent {
  const OpenAiRealtimeTranscriptCompleted({
    required super.type,
    required this.kind,
    required this.transcript,
  });

  final OpenAiRealtimeTranscriptKind kind;
  final String? transcript;
}

class OpenAiRealtimeAudioDelta extends OpenAiRealtimeEvent {
  const OpenAiRealtimeAudioDelta({
    required super.type,
    required this.base64Audio,
  });

  final String base64Audio;
}

class OpenAiRealtimeError extends OpenAiRealtimeEvent {
  const OpenAiRealtimeError({
    required super.type,
    required this.code,
    required this.eventId,
    required this.param,
  });

  final String? code;
  final String? eventId;
  final String? param;
}

class OpenAiRealtimeSessionClosed extends OpenAiRealtimeEvent {
  const OpenAiRealtimeSessionClosed({required super.type});
}

class OpenAiRealtimeUnknownEvent extends OpenAiRealtimeEvent {
  const OpenAiRealtimeUnknownEvent({required super.type});
}

abstract final class OpenAiRealtimeEventParser {
  static OpenAiRealtimeEvent? parseMessage(dynamic message) {
    if (message is! String) {
      return null;
    }

    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    return parse(decoded);
  }

  static OpenAiRealtimeEvent? parse(Map<String, dynamic> event) {
    final type = event['type'];
    if (type is! String || type.isEmpty) {
      return null;
    }

    if (type == 'session.created' || type == 'session.updated') {
      return OpenAiRealtimeSessionLifecycleEvent(type: type);
    }

    if (type == 'session.closed' || type == 'socket.closed') {
      return OpenAiRealtimeSessionClosed(type: type);
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
      return OpenAiRealtimeError(
        type: type,
        code: code is String ? code : null,
        eventId: eventId is String ? eventId : null,
        param: param is String ? param : null,
      );
    }

    final delta = event['delta'];
    if (delta is String && delta.isNotEmpty) {
      if (_isAudioDelta(type)) {
        return OpenAiRealtimeAudioDelta(type: type, base64Audio: delta);
      }

      if (_isSourceTranscriptDelta(type)) {
        return OpenAiRealtimeTranscriptDelta(
          type: type,
          kind: OpenAiRealtimeTranscriptKind.source,
          delta: delta,
        );
      }

      if (_isTranslationTranscriptDelta(type)) {
        return OpenAiRealtimeTranscriptDelta(
          type: type,
          kind: OpenAiRealtimeTranscriptKind.translation,
          delta: delta,
        );
      }
    }

    if (_isSourceTranscriptCompleted(type)) {
      return OpenAiRealtimeTranscriptCompleted(
        type: type,
        kind: OpenAiRealtimeTranscriptKind.source,
        transcript: _optionalTranscript(event),
      );
    }

    if (_isTranslationTranscriptCompleted(type)) {
      return OpenAiRealtimeTranscriptCompleted(
        type: type,
        kind: OpenAiRealtimeTranscriptKind.translation,
        transcript: _optionalTranscript(event),
      );
    }

    return OpenAiRealtimeUnknownEvent(type: type);
  }

  static bool _isAudioDelta(String type) {
    return type == 'session.output_audio.delta' ||
        type == 'response.output_audio.delta';
  }

  static bool _isSourceTranscriptDelta(String type) {
    return type == 'session.input_transcript.delta' ||
        type.contains('input_audio_transcription.delta');
  }

  static bool _isTranslationTranscriptDelta(String type) {
    return type == 'session.output_transcript.delta' ||
        type == 'response.output_audio_transcript.delta';
  }

  static bool _isSourceTranscriptCompleted(String type) {
    return type == 'session.input_transcript.done' ||
        type == 'conversation.item.input_audio_transcription.completed';
  }

  static bool _isTranslationTranscriptCompleted(String type) {
    return type == 'session.output_transcript.done' ||
        type == 'response.output_audio_transcript.done';
  }

  static String? _optionalTranscript(Map<String, dynamic> event) {
    final transcript = event['transcript'] ?? event['text'];
    if (transcript is String && transcript.trim().isNotEmpty) {
      return transcript;
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
