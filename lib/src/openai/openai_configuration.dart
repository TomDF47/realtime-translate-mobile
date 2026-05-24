abstract final class OpenAiConfiguration {
  static const apiBaseUrl = 'https://api.openai.com/v1';
  static const realtimeModel = 'gpt-realtime-2';
  static const translationFallbackModel = 'gpt-realtime-translate';
  static const aiChatModel = 'gpt-5.5';
  static const aiChatReasoningEffort = 'medium';
  static const summaryModel = 'gpt-5.5';
  static const summaryReasoningEffort = 'xhigh';

  static const realtimeCallsEndpoint = '$apiBaseUrl/realtime/calls';
  static const translationClientSecretsEndpoint =
      '$apiBaseUrl/realtime/translations/client_secrets';
  static const responsesEndpoint = '$apiBaseUrl/responses';
}
