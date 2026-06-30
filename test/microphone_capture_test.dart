import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/session/microphone_capture.dart';

void main() {
  test('OpenAI realtime capture config emits 24 kHz mono PCM16 chunks', () {
    const config = MicrophoneCaptureConfig.openAiRealtime();

    expect(config.sampleRateHz, 24000);
    expect(config.channelCount, 1);
    expect(config.chunkDuration, const Duration(milliseconds: 200));
    expect(config.androidAudioSource, AndroidAudioSource.voiceRecognition);
    expect(config.androidInputEffectsEnabled, isTrue);
    expect(config.bytesPerChunk, 9600);
    expect(config.toMethodArguments(), {
      'sampleRateHz': 24000,
      'channelCount': 1,
      'chunkDurationMs': 200,
      'androidAudioSource': 'voiceRecognition',
      'androidInputEffectsEnabled': true,
    });
  });

  test('room transcription capture disables phone-call input processing', () {
    const config = MicrophoneCaptureConfig.roomTranscription();

    expect(config.sampleRateHz, 24000);
    expect(config.channelCount, 1);
    expect(config.chunkDuration, const Duration(milliseconds: 200));
    expect(config.androidAudioSource, AndroidAudioSource.room);
    expect(config.androidInputEffectsEnabled, isFalse);
    expect(config.toMethodArguments(), {
      'sampleRateHz': 24000,
      'channelCount': 1,
      'chunkDurationMs': 200,
      'androidAudioSource': 'room',
      'androidInputEffectsEnabled': false,
    });
  });

  test('parses PCM16 platform chunk without treating bytes as text', () {
    final chunk = MicrophonePcm16Chunk.fromPlatformEvent({
      'bytes': Uint8List.fromList([0, 1, 2, 3]),
      'sampleRateHz': 24000,
      'channelCount': 1,
      'chunkDurationMs': 200,
    });

    expect(chunk.bytes, [0, 1, 2, 3]);
    expect(chunk.sampleRateHz, 24000);
    expect(chunk.channelCount, 1);
    expect(chunk.duration, const Duration(milliseconds: 200));
  });
}
