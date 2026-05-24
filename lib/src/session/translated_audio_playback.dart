import 'dart:async';
import 'dart:typed_data';

import '../diagnostics/privacy_safe_diagnostics.dart';

class TranslatedAudioPlaybackConfig {
  const TranslatedAudioPlaybackConfig({
    required this.sampleRateHz,
    this.channelCount = 1,
  });

  const TranslatedAudioPlaybackConfig.openAiRealtime({int sampleRateHz = 24000})
    : this(sampleRateHz: sampleRateHz);

  final int sampleRateHz;
  final int channelCount;
}

class TranslatedAudioPcm16Chunk {
  const TranslatedAudioPcm16Chunk({
    required this.bytes,
    required this.sampleRateHz,
    required this.channelCount,
  });

  final Uint8List bytes;
  final int sampleRateHz;
  final int channelCount;
}

abstract interface class TranslatedAudioPlaybackGateway {
  bool get isOpen;

  Future<void> start(TranslatedAudioPlaybackConfig config);

  Future<void> enqueuePcm16(TranslatedAudioPcm16Chunk chunk);

  Future<void> stop({required bool clearQueue});
}

class NoopTranslatedAudioPlaybackGateway
    implements TranslatedAudioPlaybackGateway {
  NoopTranslatedAudioPlaybackGateway({
    this.diagnostics = const PrivacySafeDiagnostics(),
  });

  final PrivacySafeDiagnostics diagnostics;
  bool _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> start(TranslatedAudioPlaybackConfig config) async {
    if (_isOpen) {
      return;
    }

    _isOpen = true;
    diagnostics.info(
      'translated_playback.started',
      fields: {
        'operation': 'translatedPlayback.start',
        'resource': 'translatedPlayback',
        'result': 'started',
      },
    );
  }

  @override
  Future<void> enqueuePcm16(TranslatedAudioPcm16Chunk chunk) async {
    if (!_isOpen) {
      throw StateError('Translated audio playback is not open.');
    }

    // Native playback is a later Android/iOS output concern. This gateway
    // keeps the coordinator path live without retaining audio-derived data.
  }

  @override
  Future<void> stop({required bool clearQueue}) async {
    if (!_isOpen) {
      return;
    }

    _isOpen = false;
    diagnostics.info(
      'translated_playback.stopped',
      fields: {
        'operation': 'translatedPlayback.stop',
        'resource': 'translatedPlayback',
        'result': clearQueue ? 'cleared' : 'stopped',
      },
    );
  }
}
