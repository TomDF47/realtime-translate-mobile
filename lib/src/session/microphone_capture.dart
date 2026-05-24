import 'dart:async';

import 'package:flutter/services.dart';

import '../diagnostics/privacy_safe_diagnostics.dart';

class MicrophoneCaptureConfig {
  const MicrophoneCaptureConfig({
    required this.sampleRateHz,
    this.channelCount = 1,
    this.chunkDuration = const Duration(milliseconds: 200),
  });

  const MicrophoneCaptureConfig.openAiRealtime({int sampleRateHz = 24000})
    : this(sampleRateHz: sampleRateHz);

  final int sampleRateHz;
  final int channelCount;
  final Duration chunkDuration;

  int get bytesPerSample => 2;

  int get bytesPerChunk {
    return sampleRateHz *
        channelCount *
        bytesPerSample *
        chunkDuration.inMilliseconds ~/
        Duration.millisecondsPerSecond;
  }

  Map<String, Object> toMethodArguments() {
    return {
      'sampleRateHz': sampleRateHz,
      'channelCount': channelCount,
      'chunkDurationMs': chunkDuration.inMilliseconds,
    };
  }
}

class MicrophonePcm16Chunk {
  const MicrophonePcm16Chunk({
    required this.bytes,
    required this.sampleRateHz,
    required this.channelCount,
    required this.duration,
  });

  final Uint8List bytes;
  final int sampleRateHz;
  final int channelCount;
  final Duration duration;

  static MicrophonePcm16Chunk fromPlatformEvent(Object? event) {
    if (event is! Map<Object?, Object?>) {
      throw const FormatException('Microphone chunk event must be a map.');
    }

    final bytesValue = event['bytes'];
    final sampleRateHz = event['sampleRateHz'];
    final channelCount = event['channelCount'];
    final chunkDurationMs = event['chunkDurationMs'];

    if (sampleRateHz is! int ||
        channelCount is! int ||
        chunkDurationMs is! int) {
      throw const FormatException('Microphone chunk metadata is invalid.');
    }

    return MicrophonePcm16Chunk(
      bytes: switch (bytesValue) {
        Uint8List value => value,
        List<int> value => Uint8List.fromList(value),
        _ => throw const FormatException('Microphone chunk bytes are invalid.'),
      },
      sampleRateHz: sampleRateHz,
      channelCount: channelCount,
      duration: Duration(milliseconds: chunkDurationMs),
    );
  }
}

abstract interface class MicrophoneCaptureGateway {
  Stream<MicrophonePcm16Chunk> get chunks;

  bool get isCapturing;

  Future<void> start(MicrophoneCaptureConfig config);

  Future<void> stop();
}

class MethodChannelMicrophoneCaptureGateway
    implements MicrophoneCaptureGateway {
  MethodChannelMicrophoneCaptureGateway({
    this.methodChannel = const MethodChannel(
      'realtime_translate_mobile/microphone_capture',
    ),
    this.eventChannel = const EventChannel(
      'realtime_translate_mobile/microphone_capture_events',
    ),
    this.diagnostics = const PrivacySafeDiagnostics(),
  });

  final MethodChannel methodChannel;
  final EventChannel eventChannel;
  final PrivacySafeDiagnostics diagnostics;

  late final Stream<MicrophonePcm16Chunk> _chunks = eventChannel
      .receiveBroadcastStream()
      .map(MicrophonePcm16Chunk.fromPlatformEvent)
      .asBroadcastStream();
  bool _isCapturing = false;

  @override
  Stream<MicrophonePcm16Chunk> get chunks => _chunks;

  @override
  bool get isCapturing => _isCapturing;

  @override
  Future<void> start(MicrophoneCaptureConfig config) async {
    if (_isCapturing) {
      return;
    }

    try {
      await methodChannel.invokeMethod<void>(
        'start',
        config.toMethodArguments(),
      );
      _isCapturing = true;
      diagnostics.info(
        'microphone.capture_started',
        fields: {
          'operation': 'microphone.capture.start',
          'resource': 'microphoneCapture',
          'result': 'started',
        },
      );
    } on MissingPluginException {
      diagnostics.warning(
        'microphone.capture_unavailable',
        fields: {
          'operation': 'microphone.capture.start',
          'resource': 'microphoneCapture',
          'result': 'missingPlugin',
        },
      );
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isCapturing) {
      return;
    }

    try {
      await methodChannel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Non-Android shells may not have a capture plugin yet.
    } finally {
      _isCapturing = false;
      diagnostics.info(
        'microphone.capture_stopped',
        fields: {
          'operation': 'microphone.capture.stop',
          'resource': 'microphoneCapture',
          'result': 'stopped',
        },
      );
    }
  }
}
