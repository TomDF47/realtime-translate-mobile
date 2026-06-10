import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/session/microphone_capture.dart';

void main() {
  test('OpenAI realtime capture config emits 24 kHz mono PCM16 chunks', () {
    const config = MicrophoneCaptureConfig.openAiRealtime();

    expect(config.sampleRateHz, 24000);
    expect(config.channelCount, 1);
    expect(config.chunkDuration, const Duration(milliseconds: 200));
    expect(config.bytesPerChunk, 9600);
    expect(config.toMethodArguments(), {
      'sampleRateHz': 24000,
      'channelCount': 1,
      'chunkDurationMs': 200,
    });
  });

  test('Gemini live translate capture config emits 16 kHz 100 ms chunks', () {
    const config = MicrophoneCaptureConfig.geminiLiveTranslate();

    expect(config.sampleRateHz, 16000);
    expect(config.channelCount, 1);
    expect(config.chunkDuration, const Duration(milliseconds: 100));
    expect(config.bytesPerChunk, 3200);
    expect(config.toMethodArguments(), {
      'sampleRateHz': 16000,
      'channelCount': 1,
      'chunkDurationMs': 100,
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
