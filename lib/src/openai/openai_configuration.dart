abstract final class OpenAiConfiguration {
  static const apiBaseUrl = 'https://api.openai.com/v1';
  static const realtimeModel = 'gpt-realtime-2';
  static const translationFallbackModel = 'gpt-realtime-translate';
  static const realtimeTranscriptionModel = 'gpt-realtime-whisper';

  /// Streaming transcription model used to emit the source/original transcript
  /// on the dedicated `/v1/realtime/translations` endpoint. Configuring
  /// `audio.input.transcription` with this model is what makes the endpoint
  /// send `session.input_transcript.delta`/`.done` events; without it the
  /// session streams translated audio and output transcript only.
  static const translationTranscriptionModel = 'gpt-realtime-whisper';

  /// Realtime input noise-reduction profile recommended by the official
  /// Realtime Translation guide for near-field (single speaker, close mic)
  /// capture such as a phone held by the speaker.
  static const realtimeInputNoiseReduction = 'near_field';
  static const aiChatModel = 'gpt-5.5';
  static const aiChatReasoningEffort = 'medium';
  static const summaryModel = 'gpt-5.5';
  static const summaryReasoningEffort = 'xhigh';

  static const realtimeWebSocketBaseUrl = 'wss://api.openai.com/v1';
  static const realtimeWebSocketPath = '/realtime';
  static const translationWebSocketPath = '/realtime/translations';
  static const realtimeCallsEndpoint = '$apiBaseUrl/realtime/calls';
  static const translationClientSecretsEndpoint =
      '$apiBaseUrl/realtime/translations/client_secrets';
  static const responsesEndpoint = '$apiBaseUrl/responses';
}

abstract final class GeminiConfiguration {
  static const liveTranslateModel = 'gemini-3.5-live-translate-preview';
  static const liveTranslateWebSocketBaseUrl =
      'wss://generativelanguage.googleapis.com';
  static const liveTranslateWebSocketPath =
      '/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
  static const liveTranslateInputAudioRate = 16000;
  static const liveTranslateOutputAudioRate = 24000;
  static const liveTranslateAudioChunkDuration = Duration(milliseconds: 100);
  static const liveTranslateAudioMimeType = 'audio/pcm;rate=16000';
}
