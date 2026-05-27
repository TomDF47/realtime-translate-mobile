import 'dart:convert';
import 'dart:io';

import '../diagnostics/privacy_safe_diagnostics.dart';
import 'openai_configuration.dart';

abstract interface class TextInterpreterGateway {
  Future<TextInterpreterTurnResult> interpretTurn({
    required TextInterpreterTurnRequest request,
    required String credential,
  });
}

class TextInterpreterTurnRequest {
  const TextInterpreterTurnRequest({
    required this.text,
    required this.knownLanguageCodes,
    this.model = OpenAiConfiguration.summaryModel,
  });

  final String text;
  final List<String> knownLanguageCodes;
  final String model;
}

class TextInterpreterTurnResult {
  const TextInterpreterTurnResult({
    required this.detectedLanguageCode,
    required this.detectedLanguageLabel,
    this.translatedText,
  });

  final String detectedLanguageCode;
  final String detectedLanguageLabel;
  final String? translatedText;
}

class OpenAiResponsesTextInterpreterGateway implements TextInterpreterGateway {
  OpenAiResponsesTextInterpreterGateway({
    HttpClient? httpClient,
    Uri? endpoint,
    this.diagnostics = const PrivacySafeDiagnostics(),
  }) : _httpClient = httpClient ?? HttpClient(),
       _endpoint = endpoint ?? Uri.parse('https://api.openai.com/v1/responses');

  final HttpClient _httpClient;
  final Uri _endpoint;
  final PrivacySafeDiagnostics diagnostics;

  @override
  Future<TextInterpreterTurnResult> interpretTurn({
    required TextInterpreterTurnRequest request,
    required String credential,
  }) async {
    final httpRequest = await _httpClient.postUrl(_endpoint);
    httpRequest.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $credential')
      ..set(HttpHeaders.contentTypeHeader, ContentType.json.mimeType);
    httpRequest.write(jsonEncode(requestBody(request)));

    final response = await httpRequest.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      diagnostics.warning(
        'openai.text_interpreter_credential_rejected',
        fields: const {
          'operation': 'textInterpreter.interpretTurn',
          'result': 'credentialRejected',
        },
      );
      throw const TextInterpreterCredentialException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      diagnostics.warning(
        'openai.text_interpreter_failed',
        fields: {
          'operation': 'textInterpreter.interpretTurn',
          'result': 'requestFailed',
          'errorCode': response.statusCode,
        },
      );
      throw TextInterpreterRequestException(statusCode: response.statusCode);
    }

    final decoded = jsonDecode(body);
    final outputText = _extractOutputText(decoded);
    final output = jsonDecode(outputText);
    if (output is! Map<String, dynamic>) {
      throw const TextInterpreterMalformedResponseException();
    }

    final code = output['detected_language_code'];
    final label = output['detected_language_label'];
    final translated = output['translated_text'];
    if (code is! String || code.trim().isEmpty || label is! String) {
      throw const TextInterpreterMalformedResponseException();
    }

    return TextInterpreterTurnResult(
      detectedLanguageCode: code.trim().toLowerCase(),
      detectedLanguageLabel: label.trim().isEmpty ? code.toUpperCase() : label,
      translatedText: translated is String && translated.trim().isNotEmpty
          ? translated.trim()
          : null,
    );
  }

  Map<String, Object?> requestBody(TextInterpreterTurnRequest request) {
    return {
      'model': request.model,
      'store': false,
      'input': [
        {
          'role': 'system',
          'content': [
            {
              'type': 'input_text',
              'text':
                  'Detect the language of the user text. If exactly one known '
                  'language is supplied, do not translate. If two known '
                  'languages are supplied and the detected language is one of '
                  'them, translate into the other language. Return only JSON '
                  'with detected_language_code, detected_language_label, and '
                  'translated_text.',
            },
          ],
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text': jsonEncode({
                'known_language_codes': request.knownLanguageCodes,
                'text': request.text,
              }),
            },
          ],
        },
      ],
    };
  }

  String _extractOutputText(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      final outputText = decoded['output_text'];
      if (outputText is String && outputText.trim().isNotEmpty) {
        return outputText;
      }
      final output = decoded['output'];
      if (output is List) {
        for (final item in output) {
          if (item is! Map<String, dynamic>) {
            continue;
          }
          final content = item['content'];
          if (content is List) {
            for (final part in content) {
              if (part is Map<String, dynamic>) {
                final text = part['text'];
                if (text is String && text.trim().isNotEmpty) {
                  return text;
                }
              }
            }
          }
        }
      }
    }

    throw const TextInterpreterMalformedResponseException();
  }
}

class TextInterpreterCredentialException implements Exception {
  const TextInterpreterCredentialException();
}

class TextInterpreterRequestException implements Exception {
  const TextInterpreterRequestException({required this.statusCode});

  final int statusCode;
}

class TextInterpreterMalformedResponseException implements Exception {
  const TextInterpreterMalformedResponseException();
}
