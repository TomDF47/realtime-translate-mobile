import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/diagnostics/realtime_event_debug_recorder.dart';

void main() {
  test('captures content-free shape of a source transcript event', () {
    final sink = MemoryRealtimeEventDebugSink();
    final recorder = RealtimeEventDebugRecorder(enabled: true, sink: sink);

    recorder.recordRawMessage(
      jsonEncode({
        'type': 'session.input_transcript.delta',
        'delta': 'Buongiorno, come stai?',
        'item_id': 'item_abc123',
        'language': 'IT',
      }),
    );

    final record = sink.records.single;
    expect(record.type, 'session.input_transcript.delta');
    expect(record.keys, containsAll(<String>['type', 'delta', 'item_id', 'language']));
    expect(record.deltaLength, 'Buongiorno, come stai?'.length);
    expect(record.languageCode, 'it');
    expect(record.hasItemId, isTrue);
  });

  test('never serializes transcript or audio content', () {
    final sink = MemoryRealtimeEventDebugSink();
    final recorder = RealtimeEventDebugRecorder(enabled: true, sink: sink);
    const secretSource = 'TOP SECRET ORIGINAL SPEECH';
    const secretTranslation = 'TOP SECRET TRANSLATION';
    const secretAudio = 'QUJDREVGR0g=';

    recorder.recordRawMessage(
      jsonEncode({
        'type': 'session.output_transcript.delta',
        'delta': secretTranslation,
        'transcript': secretSource,
        'audio': secretAudio,
      }),
    );

    final line = sink.records.single.toLogLine();
    expect(line, isNot(contains(secretSource)));
    expect(line, isNot(contains(secretTranslation)));
    expect(line, isNot(contains(secretAudio)));
    // The safe shape (type + lengths) is present.
    expect(line, contains('session.output_transcript.delta'));
    expect(line, contains('"deltaLen":${secretTranslation.length}'));
    expect(line, contains('"transcriptLen":${secretSource.length}'));
    expect(line, contains('"audioLen":${secretAudio.length}'));
  });

  test('extracts nested language metadata and item ids', () {
    final sink = MemoryRealtimeEventDebugSink();
    final recorder = RealtimeEventDebugRecorder(enabled: true, sink: sink);

    recorder.recordRawMessage(
      jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item': {'id': 'item_99', 'language': 'en'},
      }),
    );

    final record = sink.records.single;
    expect(record.languageCode, 'en');
    expect(record.hasItemId, isTrue);
    expect(record.nestedKeys['item'], containsAll(<String>['id', 'language']));
  });

  test('records malformed and non-string frames by shape only', () {
    final sink = MemoryRealtimeEventDebugSink();
    final recorder = RealtimeEventDebugRecorder(enabled: true, sink: sink);

    recorder.recordRawMessage('not json at all');
    recorder.recordRawMessage(<int>[1, 2, 3]);

    expect(sink.records[0].type, '<unparsable>');
    expect(sink.records[1].type, startsWith('<non-string:'));
  });

  test('is a no-op when disabled', () {
    final sink = MemoryRealtimeEventDebugSink();
    final recorder = RealtimeEventDebugRecorder(enabled: false, sink: sink);

    recorder.recordRawMessage(
      jsonEncode({'type': 'session.output_transcript.delta', 'delta': 'hi'}),
    );

    expect(sink.records, isEmpty);
  });
}
