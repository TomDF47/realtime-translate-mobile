import 'package:flutter/services.dart';

import '../diagnostics/privacy_safe_diagnostics.dart';

enum SpokenTranslationRouteSide { source, target }

class SpokenTranslationUtterance {
  const SpokenTranslationUtterance({
    required this.id,
    required this.routeSide,
    required this.sourceLanguageCode,
    required this.outputLanguageCode,
    required this.text,
  });

  final String id;
  final SpokenTranslationRouteSide routeSide;
  final String sourceLanguageCode;
  final String outputLanguageCode;
  final String text;

  Map<String, Object> toMethodArguments() {
    return {
      'utteranceId': id,
      'routeSide': routeSide.name,
      'sourceLanguageCode': sourceLanguageCode,
      'outputLanguageCode': outputLanguageCode,
      'text': text,
    };
  }
}

abstract interface class SpokenTranslationOutputGateway {
  bool get isSpeaking;

  Future<void> speak(SpokenTranslationUtterance utterance);

  Future<void> stop();
}

class MethodChannelSpokenTranslationOutputGateway
    implements SpokenTranslationOutputGateway {
  MethodChannelSpokenTranslationOutputGateway({
    this.methodChannel = const MethodChannel(
      'realtime_translate_mobile/spoken_translation_output',
    ),
    this.diagnostics = const PrivacySafeDiagnostics(),
  });

  final MethodChannel methodChannel;
  final PrivacySafeDiagnostics diagnostics;
  bool _isSpeaking = false;
  bool _nativeOutputAvailable = true;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Future<void> speak(SpokenTranslationUtterance utterance) async {
    final text = utterance.text.trim();
    if (text.isEmpty) {
      return;
    }

    _isSpeaking = true;
    try {
      await methodChannel.invokeMethod<void>(
        'speak',
        utterance.toMethodArguments(),
      );
      _nativeOutputAvailable = true;
      diagnostics.info(
        'spoken_output.completed',
        fields: {
          'operation': 'spokenOutput.speak',
          'resource': 'spokenOutput',
          'result': 'completed',
          'targetLanguage': utterance.outputLanguageCode,
        },
      );
    } on MissingPluginException {
      _nativeOutputAvailable = false;
      diagnostics.warning(
        'spoken_output.unavailable',
        fields: {
          'operation': 'spokenOutput.speak',
          'resource': 'spokenOutput',
          'result': 'missingPlugin',
          'targetLanguage': utterance.outputLanguageCode,
        },
      );
    } finally {
      _isSpeaking = false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isSpeaking && !_nativeOutputAvailable) {
      return;
    }

    try {
      if (_nativeOutputAvailable) {
        await methodChannel.invokeMethod<void>('stop');
      }
    } on MissingPluginException {
      _nativeOutputAvailable = false;
      diagnostics.warning(
        'spoken_output.unavailable',
        fields: {
          'operation': 'spokenOutput.stop',
          'resource': 'spokenOutput',
          'result': 'missingPlugin',
        },
      );
    } finally {
      _isSpeaking = false;
      diagnostics.info(
        'spoken_output.stopped',
        fields: {
          'operation': 'spokenOutput.stop',
          'resource': 'spokenOutput',
          'result': 'stopped',
        },
      );
    }
  }
}

class NoopSpokenTranslationOutputGateway
    implements SpokenTranslationOutputGateway {
  bool _isSpeaking = false;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Future<void> speak(SpokenTranslationUtterance utterance) async {
    _isSpeaking = false;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
  }
}
