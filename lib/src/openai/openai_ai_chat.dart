import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../diagnostics/privacy_safe_diagnostics.dart';
import '../storage/local_storage_models.dart';
import '../ui/live_translate_models.dart';
import 'openai_configuration.dart';

typedef HttpClientFactory = HttpClient Function();

class AiChatContext {
  const AiChatContext({required this.scope, required this.meetings});

  final AiChatScope scope;
  final List<AiChatContextMeeting> meetings;

  int get transcriptEntryCount {
    return meetings.fold<int>(
      0,
      (count, meeting) => count + meeting.entries.length,
    );
  }

  bool get hasTranscriptContext => transcriptEntryCount > 0;

  String toPromptContext() {
    if (meetings.isEmpty) {
      return 'No local meetings are available for this scope.';
    }

    final lines = <String>[];
    for (final meeting in meetings) {
      lines
        ..add('Meeting: ${meeting.title}')
        ..add(
          'Route: ${meeting.sourceLanguageLabel} -> '
          '${meeting.targetLanguageLabel}',
        );
      if (meeting.entries.isEmpty) {
        lines.add('No transcript lines stored for this meeting.');
      } else {
        for (final entry in meeting.entries) {
          lines
            ..add('[${entry.timestampLabel}] ${entry.languageCode}')
            ..add('Original: ${entry.originalText}')
            ..add('Translation: ${entry.translatedText}');
          if (entry.speakerLabel != null && entry.speakerLabel!.isNotEmpty) {
            lines.add('Speaker: ${entry.speakerLabel}');
          }
        }
      }
      lines.add('');
    }

    return lines.join('\n').trim();
  }
}

class AiChatContextMeeting {
  const AiChatContextMeeting({
    required this.id,
    required this.title,
    required this.sourceLanguageLabel,
    required this.targetLanguageLabel,
    required this.entries,
  });

  final String id;
  final String title;
  final String sourceLanguageLabel;
  final String targetLanguageLabel;
  final List<AiChatContextEntry> entries;
}

class AiChatContextEntry {
  const AiChatContextEntry({
    required this.timestampLabel,
    required this.languageCode,
    required this.originalText,
    required this.translatedText,
    required this.speakerLabel,
  });

  final String timestampLabel;
  final String languageCode;
  final String originalText;
  final String translatedText;
  final String? speakerLabel;
}

abstract final class AiChatContextBuilder {
  static AiChatContext fromSnapshot({
    required AiChatScope scope,
    required LocalStorageSnapshot snapshot,
    StoredMeeting? activeMeeting,
  }) {
    final meetings = switch (scope) {
      AiChatScope.thisMeeting => [?activeMeeting],
      AiChatScope.allMeetings => snapshot.meetings,
    };

    return AiChatContext(
      scope: scope,
      meetings: [
        for (final meeting in meetings)
          AiChatContextMeeting(
            id: meeting.id,
            title: meeting.title,
            sourceLanguageLabel: meeting.sourceLanguageLabel,
            targetLanguageLabel: meeting.targetLanguageLabel,
            entries: [
              for (final entry in meeting.transcriptEntries)
                AiChatContextEntry(
                  timestampLabel: _timeLabel(entry.timestamp),
                  languageCode: entry.languageCode,
                  originalText: entry.originalText,
                  translatedText: entry.translatedText,
                  speakerLabel: entry.speakerLabel,
                ),
            ],
          ),
      ],
    );
  }
}

class AiChatRequest {
  const AiChatRequest({
    required this.prompt,
    required this.context,
    this.model = OpenAiConfiguration.aiChatModel,
    this.reasoningEffort = OpenAiConfiguration.aiChatReasoningEffort,
  });

  final String prompt;
  final AiChatContext context;
  final String model;
  final String reasoningEffort;

  Map<String, Object?> toOpenAiResponsesBody() {
    return {
      'model': model,
      'store': false,
      'reasoning': {'effort': reasoningEffort},
      'text': {'verbosity': 'medium'},
      'instructions':
          'You are Live Translate AI Chat. Answer only from the provided '
          'local transcript context for the selected scope. Cite timestamp '
          'labels when possible. If the answer is not in the supplied local '
          'context, say that there is not enough local transcript context. '
          'Do not use outside meeting knowledge.',
      'input':
          'Selected scope: ${context.scope.label}\n'
          'User question: $prompt\n\n'
          'Local transcript context:\n${context.toPromptContext()}',
    };
  }
}

class AiChatAnswer {
  const AiChatAnswer({required this.text, required this.generatedAt});

  final String text;
  final DateTime generatedAt;
}

abstract interface class AiChatGateway {
  Future<AiChatAnswer> ask({
    required AiChatRequest request,
    required String credential,
  });
}

class OpenAiResponsesAiChatGateway implements AiChatGateway {
  OpenAiResponsesAiChatGateway({
    Uri? endpoint,
    HttpClientFactory? httpClientFactory,
    this.timeout = const Duration(seconds: 45),
    this.diagnostics = const PrivacySafeDiagnostics(),
  }) : endpoint = endpoint ?? Uri.parse(OpenAiConfiguration.responsesEndpoint),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Uri endpoint;
  final Duration timeout;
  final PrivacySafeDiagnostics diagnostics;
  final HttpClientFactory _httpClientFactory;

  @override
  Future<AiChatAnswer> ask({
    required AiChatRequest request,
    required String credential,
  }) async {
    diagnostics.info(
      'openai.ai_chat_request_started',
      fields: {
        'operation': 'responses.create',
        'endpoint': endpoint.host,
        'model': request.model,
        'reasoningEffort': request.reasoningEffort,
        'scope': request.context.scope.label,
      },
    );

    final client = _httpClientFactory();
    try {
      final httpRequest = await client.postUrl(endpoint).timeout(timeout);
      httpRequest.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $credential');
      httpRequest.write(jsonEncode(request.toOpenAiResponsesBody()));

      final response = await httpRequest.close().timeout(timeout);
      final responseBody = await utf8.decodeStream(response).timeout(timeout);
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        diagnostics.warning(
          'openai.ai_chat_credential_rejected',
          fields: {
            'operation': 'responses.create',
            'model': request.model,
            'scope': request.context.scope.label,
            'result': 'credentialRejected',
          },
        );
        throw const AiChatCredentialException();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        diagnostics.error(
          'openai.ai_chat_request_failed',
          fields: {
            'operation': 'responses.create',
            'model': request.model,
            'scope': request.context.scope.label,
            'errorCode': response.statusCode,
            'result': 'httpError',
          },
        );
        throw AiChatRequestException(statusCode: response.statusCode);
      }

      final decoded = jsonDecode(responseBody);
      final text = OpenAiResponsesText.extract(decoded);
      if (text == null || text.trim().isEmpty) {
        diagnostics.error(
          'openai.ai_chat_response_malformed',
          fields: {
            'operation': 'responses.create',
            'model': request.model,
            'scope': request.context.scope.label,
            'result': 'malformedResponse',
          },
        );
        throw const AiChatMalformedResponseException();
      }

      diagnostics.info(
        'openai.ai_chat_request_succeeded',
        fields: {
          'operation': 'responses.create',
          'model': request.model,
          'scope': request.context.scope.label,
          'result': 'success',
        },
      );
      return AiChatAnswer(text: text.trim(), generatedAt: DateTime.now());
    } on AiChatException {
      rethrow;
    } on TimeoutException catch (error) {
      diagnostics.warning(
        'openai.ai_chat_network_timeout',
        fields: {
          'operation': 'responses.create',
          'model': request.model,
          'scope': request.context.scope.label,
          'errorCode': error.runtimeType.toString(),
          'result': 'timeout',
        },
      );
      throw const AiChatNetworkException();
    } on SocketException catch (error) {
      diagnostics.warning(
        'openai.ai_chat_network_error',
        fields: {
          'operation': 'responses.create',
          'model': request.model,
          'scope': request.context.scope.label,
          'errorCode': error.runtimeType.toString(),
          'result': 'networkError',
        },
      );
      throw const AiChatNetworkException();
    } on FormatException {
      throw const AiChatMalformedResponseException();
    } finally {
      client.close(force: true);
    }
  }
}

abstract final class OpenAiResponsesText {
  static String? extract(Object? decoded) {
    if (decoded is! Map<Object?, Object?>) {
      return null;
    }

    final outputText = decoded['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) {
      return outputText;
    }

    final output = decoded['output'];
    if (output is! List<Object?>) {
      return null;
    }

    final parts = <String>[];
    for (final item in output.whereType<Map<Object?, Object?>>()) {
      final content = item['content'];
      if (content is! List<Object?>) {
        continue;
      }

      for (final contentPart in content.whereType<Map<Object?, Object?>>()) {
        final text = contentPart['text'];
        if (text is String && text.trim().isNotEmpty) {
          parts.add(text);
        }
      }
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join('\n\n');
  }
}

sealed class AiChatException implements Exception {
  const AiChatException();
}

class AiChatCredentialException extends AiChatException {
  const AiChatCredentialException();
}

class AiChatNetworkException extends AiChatException {
  const AiChatNetworkException();
}

class AiChatMalformedResponseException extends AiChatException {
  const AiChatMalformedResponseException();
}

class AiChatRequestException extends AiChatException {
  const AiChatRequestException({required this.statusCode});

  final int statusCode;
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}
