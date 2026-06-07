import 'dart:math' as math;
import 'dart:typed_data';

import 'microphone_capture.dart';

enum RealtimeTranscriptionCommitReason { pause, hardCap, manualFlush }

class RealtimeTranscriptionBatchDecision {
  const RealtimeTranscriptionBatchDecision._({this.reason});

  const RealtimeTranscriptionBatchDecision.none() : this._();

  const RealtimeTranscriptionBatchDecision.commit(
    RealtimeTranscriptionCommitReason reason,
  ) : this._(reason: reason);

  final RealtimeTranscriptionCommitReason? reason;

  bool get shouldCommit => reason != null;
}

class RealtimeTranscriptionBatchController {
  RealtimeTranscriptionBatchController({
    required this.minSpeechDuration,
    required this.pauseAfterSpeech,
    required this.hardCap,
    required this.speechRmsThreshold,
    required this.speechPeakThreshold,
    required this.silenceRmsThreshold,
    required this.silencePeakThreshold,
  });

  factory RealtimeTranscriptionBatchController.roomConversation() {
    return RealtimeTranscriptionBatchController(
      minSpeechDuration: const Duration(milliseconds: 400),
      pauseAfterSpeech: const Duration(milliseconds: 700),
      hardCap: const Duration(seconds: 6),
      speechRmsThreshold: 180,
      speechPeakThreshold: 900,
      silenceRmsThreshold: 120,
      silencePeakThreshold: 600,
    );
  }

  final Duration minSpeechDuration;
  final Duration pauseAfterSpeech;
  final Duration hardCap;
  final int speechRmsThreshold;
  final int speechPeakThreshold;
  final int silenceRmsThreshold;
  final int silencePeakThreshold;

  Duration _uncommittedDuration = Duration.zero;
  Duration _speechDuration = Duration.zero;
  Duration _silenceAfterSpeech = Duration.zero;
  bool _hasHeardSpeech = false;
  bool _hasUncommittedAudio = false;

  bool get hasUncommittedAudio => _hasUncommittedAudio;

  RealtimeTranscriptionBatchDecision add(MicrophonePcm16Chunk chunk) {
    _hasUncommittedAudio = true;
    _uncommittedDuration += chunk.duration;

    final level = _level(chunk.bytes);
    final isSpeech =
        level.peak >= speechPeakThreshold || level.rms >= speechRmsThreshold;
    final isSilence =
        level.peak <= silencePeakThreshold && level.rms <= silenceRmsThreshold;

    if (isSpeech) {
      _hasHeardSpeech = true;
      _speechDuration += chunk.duration;
      _silenceAfterSpeech = Duration.zero;
    } else if (_hasHeardSpeech && isSilence) {
      _silenceAfterSpeech += chunk.duration;
    }

    if (_hasHeardSpeech &&
        _speechDuration >= minSpeechDuration &&
        _silenceAfterSpeech >= pauseAfterSpeech) {
      return _commit(RealtimeTranscriptionCommitReason.pause);
    }

    if (_uncommittedDuration >= hardCap) {
      return _commit(RealtimeTranscriptionCommitReason.hardCap);
    }

    return const RealtimeTranscriptionBatchDecision.none();
  }

  RealtimeTranscriptionBatchDecision flush() {
    if (!_hasUncommittedAudio) {
      return const RealtimeTranscriptionBatchDecision.none();
    }

    return _commit(RealtimeTranscriptionCommitReason.manualFlush);
  }

  void reset() {
    _uncommittedDuration = Duration.zero;
    _speechDuration = Duration.zero;
    _silenceAfterSpeech = Duration.zero;
    _hasHeardSpeech = false;
    _hasUncommittedAudio = false;
  }

  RealtimeTranscriptionBatchDecision _commit(
    RealtimeTranscriptionCommitReason reason,
  ) {
    reset();
    return RealtimeTranscriptionBatchDecision.commit(reason);
  }

  _PcmLevel _level(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final sampleCount = data.lengthInBytes ~/ 2;
    if (sampleCount == 0) {
      return const _PcmLevel(rms: 0, peak: 0);
    }

    var squareSum = 0;
    var peak = 0;
    for (var offset = 0; offset + 1 < data.lengthInBytes; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      final magnitude = sample.abs();
      if (magnitude > peak) {
        peak = magnitude;
      }
      squareSum += sample * sample;
    }

    return _PcmLevel(
      rms: math.sqrt(squareSum / sampleCount).round(),
      peak: peak,
    );
  }
}

class _PcmLevel {
  const _PcmLevel({required this.rms, required this.peak});

  final int rms;
  final int peak;
}
