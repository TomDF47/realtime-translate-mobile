import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/session/microphone_capture.dart';
import 'package:realtime_translate_mobile/src/session/realtime_transcription_batcher.dart';

void main() {
  test('commits after speech followed by a pause', () {
    final batcher = RealtimeTranscriptionBatchController(
      minSpeechDuration: const Duration(milliseconds: 400),
      pauseAfterSpeech: const Duration(milliseconds: 600),
      hardCap: const Duration(seconds: 6),
      speechRmsThreshold: 100,
      speechPeakThreshold: 150,
      silenceRmsThreshold: 80,
      silencePeakThreshold: 100,
    );

    expect(batcher.add(_chunk(amplitude: 600)), isNot(_commits));
    expect(batcher.add(_chunk(amplitude: 600)), isNot(_commits));
    expect(batcher.add(_chunk(amplitude: 0)), isNot(_commits));
    expect(batcher.add(_chunk(amplitude: 0)), isNot(_commits));

    final decision = batcher.add(_chunk(amplitude: 0));

    expect(decision.shouldCommit, isTrue);
    expect(decision.reason, RealtimeTranscriptionCommitReason.pause);
    expect(batcher.hasUncommittedAudio, isFalse);
  });

  test('commits at the hard cap even without confident speech', () {
    final batcher = RealtimeTranscriptionBatchController(
      minSpeechDuration: const Duration(milliseconds: 400),
      pauseAfterSpeech: const Duration(milliseconds: 600),
      hardCap: const Duration(milliseconds: 600),
      speechRmsThreshold: 1000,
      speechPeakThreshold: 2000,
      silenceRmsThreshold: 500,
      silencePeakThreshold: 800,
    );

    expect(batcher.add(_chunk(amplitude: 40)), isNot(_commits));
    expect(batcher.add(_chunk(amplitude: 40)), isNot(_commits));

    final decision = batcher.add(_chunk(amplitude: 40));

    expect(decision.shouldCommit, isTrue);
    expect(decision.reason, RealtimeTranscriptionCommitReason.hardCap);
  });

  test('manual flush commits any uncommitted audio', () {
    final batcher = RealtimeTranscriptionBatchController.roomConversation();

    expect(batcher.flush().shouldCommit, isFalse);

    batcher.add(_chunk(amplitude: 0));
    final decision = batcher.flush();

    expect(decision.shouldCommit, isTrue);
    expect(decision.reason, RealtimeTranscriptionCommitReason.manualFlush);
  });
}

final Matcher _commits = isA<RealtimeTranscriptionBatchDecision>().having(
  (decision) => decision.shouldCommit,
  'shouldCommit',
  isTrue,
);

MicrophonePcm16Chunk _chunk({required int amplitude}) {
  final bytes = Uint8List(9600);
  for (var offset = 0; offset < bytes.length; offset += 2) {
    bytes[offset] = amplitude & 0xff;
    bytes[offset + 1] = (amplitude >> 8) & 0xff;
  }
  return MicrophonePcm16Chunk(
    bytes: bytes,
    sampleRateHz: 24000,
    channelCount: 1,
    duration: const Duration(milliseconds: 200),
  );
}
