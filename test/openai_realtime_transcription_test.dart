import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_configuration.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_transcription.dart';

void main() {
  test('builds manual-commit transcription-only realtime config', () {
    const config = OpenAiRealtimeTranscriptionConfig(
      inputAudioRate: 24000,
      languageHint: 'en',
    );

    final uri = config.webSocketUri();
    final sessionUpdate = config.initialSessionUpdate();
    final serialized = jsonEncode(sessionUpdate);

    expect(uri.scheme, 'wss');
    expect(uri.host, 'api.openai.com');
    expect(uri.path, '/v1/realtime');
    expect(uri.queryParameters, {
      'model': OpenAiConfiguration.translationTranscriptionModel,
    });
    expect(sessionUpdate['type'], 'session.update');
    expect(serialized, contains('"type":"transcription"'));
    expect(serialized, contains('"type":"audio/pcm"'));
    expect(serialized, contains('"rate":24000'));
    expect(
      serialized,
      contains('"model":"${OpenAiConfiguration.translationTranscriptionModel}"'),
    );
    expect(serialized, contains('"language":"en"'));
    expect(serialized, contains('"turn_detection":null'));
    expect(serialized, isNot(contains('placeholder-local-openai-credential')));
    expect(config.audioAppendEvent([1, 2, 3]), {
      'type': 'input_audio_buffer.append',
      'audio': 'AQID',
    });
    expect(config.inputAudioCommitEvent(), {
      'type': 'input_audio_buffer.commit',
    });
  });

  test('omits transcription language hint by default', () {
    const config = OpenAiRealtimeTranscriptionConfig(inputAudioRate: 24000);

    final serialized = jsonEncode(config.initialSessionUpdate());

    expect(serialized, isNot(contains('"language"')));
  });

  test('parses transcription completion events with item ids', () {
    final event = OpenAiRealtimeTranscriptionEventParser.parse({
      'type': 'conversation.item.input_audio_transcription.completed',
      'item_id': 'item_123',
      'transcript': 'Hello from the table',
      'language': 'en',
    });

    expect(event, isA<OpenAiRealtimeTranscriptionCompleted>());
    final completed = event! as OpenAiRealtimeTranscriptionCompleted;
    expect(completed.itemId, 'item_123');
    expect(completed.transcript, 'Hello from the table');
    expect(completed.languageCode, 'en');
  });
}
