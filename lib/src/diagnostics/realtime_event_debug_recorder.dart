import 'dart:convert';
import 'dart:developer' as developer;

/// Compile-time switch for the realtime wire-event recorder.
///
/// This is a developer-only ground-truth tool: it is OFF unless a build
/// explicitly opts in with
///
/// ```bash
/// flutter build apk --debug --dart-define=LIVE_TRANSLATE_DEBUG_EVENTS=true
/// ```
///
/// When off, [RealtimeEventDebugRecorder.recordRawMessage] is a no-op and the
/// const default sink is never invoked, so release builds carry no overhead and
/// emit nothing.
const bool kLiveTranslateDebugEvents = bool.fromEnvironment(
  'LIVE_TRANSLATE_DEBUG_EVENTS',
);

/// Stable, greppable prefix for every emitted line. Capture with, for example:
///
/// ```bash
/// adb logcat | grep LIVE_TX_EVENT
/// ```
const String kRealtimeEventLogPrefix = 'LIVE_TX_EVENT';

/// Content-free description of a single realtime wire event.
///
/// This intentionally captures only the *shape* of an event so a real
/// `/v1/realtime/translations` session can be characterized without ever
/// logging speech, transcript text, translated text, or audio bytes:
///
/// - [type]: the protocol event `type` string (for example
///   `session.input_transcript.delta`). Not user content.
/// - [keys]: the set of top-level JSON keys present. Field names only.
/// - [nestedKeys]: keys found inside common nested objects (`item`,
///   `transcript`, `audio`, `delta`). Field names only.
/// - [deltaLength] / [transcriptLength] / [audioLength]: character lengths of
///   the corresponding payload fields, never their values.
/// - [languageCode]: a detected language code such as `en`/`it` if the event
///   carries one. A language code is not sensitive and is exactly the signal
///   needed to confirm whether the wire surfaces source-language metadata.
/// - [hasItemId]: whether the event carried any item id, without its value.
class RealtimeEventDebugRecord {
  const RealtimeEventDebugRecord({
    required this.type,
    required this.keys,
    this.nestedKeys = const {},
    this.deltaLength,
    this.transcriptLength,
    this.audioLength,
    this.languageCode,
    this.hasItemId = false,
  });

  final String type;
  final List<String> keys;
  final Map<String, List<String>> nestedKeys;
  final int? deltaLength;
  final int? transcriptLength;
  final int? audioLength;
  final String? languageCode;
  final bool hasItemId;

  /// Privacy-safe JSON representation. Only the content-free fields above are
  /// serialized; payload values are never included.
  Map<String, Object?> toJson() {
    return {
      'type': type,
      'keys': keys,
      if (nestedKeys.isNotEmpty) 'nestedKeys': nestedKeys,
      if (deltaLength != null) 'deltaLen': deltaLength,
      if (transcriptLength != null) 'transcriptLen': transcriptLength,
      if (audioLength != null) 'audioLen': audioLength,
      if (languageCode != null) 'lang': languageCode,
      'hasItemId': hasItemId,
    };
  }

  String toLogLine() => '$kRealtimeEventLogPrefix ${jsonEncode(toJson())}';
}

/// Destination for [RealtimeEventDebugRecord]s.
abstract interface class RealtimeEventDebugSink {
  void add(RealtimeEventDebugRecord record);
}

/// Emits each record to the platform log via `dart:developer`. On Android these
/// lines appear in `adb logcat`, so the captured ground-truth log can be shared
/// without persisting any transcript/audio payload on the device.
class DeveloperLogRealtimeEventDebugSink implements RealtimeEventDebugSink {
  const DeveloperLogRealtimeEventDebugSink();

  @override
  void add(RealtimeEventDebugRecord record) {
    developer.log(record.toLogLine(), name: kRealtimeEventLogPrefix);
  }
}

/// In-memory sink for tests.
class MemoryRealtimeEventDebugSink implements RealtimeEventDebugSink {
  final List<RealtimeEventDebugRecord> records = [];

  @override
  void add(RealtimeEventDebugRecord record) => records.add(record);
}

/// Inspects raw realtime wire messages and emits a content-free shape record
/// for each one when [enabled].
class RealtimeEventDebugRecorder {
  const RealtimeEventDebugRecorder({
    this.enabled = kLiveTranslateDebugEvents,
    this.sink = const DeveloperLogRealtimeEventDebugSink(),
  });

  final bool enabled;
  final RealtimeEventDebugSink sink;

  void recordRawMessage(Object? message) {
    if (!enabled) {
      return;
    }

    if (message is! String) {
      sink.add(
        RealtimeEventDebugRecord(
          type: '<non-string:${message.runtimeType}>',
          keys: const [],
        ),
      );
      return;
    }

    Map<String, dynamic>? decoded;
    try {
      final Object? json = jsonDecode(message);
      if (json is Map<String, dynamic>) {
        decoded = json;
      }
    } catch (_) {
      // Malformed frames are recorded by shape only, never by content.
    }

    if (decoded == null) {
      sink.add(
        const RealtimeEventDebugRecord(type: '<unparsable>', keys: []),
      );
      return;
    }

    final type = decoded['type'];
    sink.add(
      RealtimeEventDebugRecord(
        type: type is String && type.isNotEmpty ? type : '<no-type>',
        keys: decoded.keys.toList()..sort(),
        nestedKeys: _nestedKeys(decoded),
        deltaLength: _stringLength(decoded['delta']),
        transcriptLength:
            _stringLength(decoded['transcript']) ??
            _stringLength(decoded['text']),
        audioLength: _stringLength(decoded['audio']),
        languageCode: _extractLanguageCode(decoded),
        hasItemId: _hasItemId(decoded),
      ),
    );
  }

  static int? _stringLength(Object? value) {
    return value is String ? value.length : null;
  }

  static Map<String, List<String>> _nestedKeys(Map<String, dynamic> event) {
    final result = <String, List<String>>{};
    for (final key in const ['item', 'transcript', 'audio', 'delta', 'error']) {
      final value = event[key];
      if (value is Map<String, dynamic>) {
        result[key] = value.keys.toList()..sort();
      }
    }
    return result;
  }

  static bool _hasItemId(Map<String, dynamic> event) {
    if (event['item_id'] is String || event['itemId'] is String) {
      return true;
    }
    final item = event['item'];
    return item is Map<String, dynamic> && item['id'] is String;
  }

  static String? _extractLanguageCode(Map<String, dynamic> event) {
    final direct = event['language'] ?? event['language_code'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim().toLowerCase();
    }
    for (final key in const ['transcript', 'audio', 'item', 'metadata']) {
      final value = event[key];
      if (value is Map<String, dynamic>) {
        final nested = value['language'] ?? value['language_code'];
        if (nested is String && nested.trim().isNotEmpty) {
          return nested.trim().toLowerCase();
        }
      }
    }
    return null;
  }
}
