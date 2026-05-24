import 'dart:async';

import 'package:flutter/services.dart';

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

  Map<String, Object> toMethodArguments() {
    return {'sampleRateHz': sampleRateHz, 'channelCount': channelCount};
  }
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

  Map<String, Object> toMethodArguments() {
    return {
      'bytes': bytes,
      'sampleRateHz': sampleRateHz,
      'channelCount': channelCount,
    };
  }
}

abstract interface class TranslatedAudioPlaybackGateway {
  bool get isOpen;

  Future<void> start(TranslatedAudioPlaybackConfig config);

  Future<void> enqueuePcm16(TranslatedAudioPcm16Chunk chunk);

  Future<void> stop({required bool clearQueue});
}

class MethodChannelTranslatedAudioPlaybackGateway
    implements TranslatedAudioPlaybackGateway {
  MethodChannelTranslatedAudioPlaybackGateway({
    this.methodChannel = const MethodChannel(
      'realtime_translate_mobile/translated_audio_playback',
    ),
    this.diagnostics = const PrivacySafeDiagnostics(),
  });

  final MethodChannel methodChannel;
  final PrivacySafeDiagnostics diagnostics;
  bool _isOpen = false;
  bool _nativePlaybackAvailable = true;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> start(TranslatedAudioPlaybackConfig config) async {
    if (_isOpen) {
      return;
    }

    try {
      await methodChannel.invokeMethod<void>(
        'start',
        config.toMethodArguments(),
      );
      _nativePlaybackAvailable = true;
      diagnostics.info(
        'translated_playback.started',
        fields: {
          'operation': 'translatedPlayback.start',
          'resource': 'translatedPlayback',
          'result': 'nativeStarted',
        },
      );
    } on MissingPluginException {
      _nativePlaybackAvailable = false;
      diagnostics.warning(
        'translated_playback.unavailable',
        fields: {
          'operation': 'translatedPlayback.start',
          'resource': 'translatedPlayback',
          'result': 'missingPlugin',
        },
      );
    }

    _isOpen = true;
  }

  @override
  Future<void> enqueuePcm16(TranslatedAudioPcm16Chunk chunk) async {
    if (!_isOpen) {
      throw StateError('Translated audio playback is not open.');
    }

    if (!_nativePlaybackAvailable) {
      return;
    }

    try {
      await methodChannel.invokeMethod<void>(
        'enqueuePcm16',
        chunk.toMethodArguments(),
      );
    } on MissingPluginException {
      _nativePlaybackAvailable = false;
      diagnostics.warning(
        'translated_playback.unavailable',
        fields: {
          'operation': 'translatedPlayback.enqueue',
          'resource': 'translatedPlayback',
          'result': 'missingPlugin',
        },
      );
    }
  }

  @override
  Future<void> stop({required bool clearQueue}) async {
    if (!_isOpen) {
      return;
    }

    try {
      if (_nativePlaybackAvailable) {
        await methodChannel.invokeMethod<void>('stop', {
          'clearQueue': clearQueue,
        });
      }
    } on MissingPluginException {
      diagnostics.warning(
        'translated_playback.unavailable',
        fields: {
          'operation': 'translatedPlayback.stop',
          'resource': 'translatedPlayback',
          'result': 'missingPlugin',
        },
      );
    } finally {
      _isOpen = false;
      _nativePlaybackAvailable = true;
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

    // Kept for tests and non-Android shells that deliberately avoid binding
    // speaker output while preserving the coordinator path.
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
