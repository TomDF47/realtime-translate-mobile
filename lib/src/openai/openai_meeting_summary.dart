import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../diagnostics/privacy_safe_diagnostics.dart';
import '../storage/local_storage_models.dart';
import 'openai_ai_chat.dart';
import 'openai_configuration.dart';

class MeetingSummaryRequest {
  const MeetingSummaryRequest({
    required this.meeting,
    this.model = OpenAiConfiguration.summaryModel,
    this.reasoningEffort = OpenAiConfiguration.summaryReasoningEffort,
  });

  final StoredMeeting meeting;
  final String model;
  final String reasoningEffort;

  int get transcriptEntryCount => meeting.transcriptEntries.length;

  Map<String, Object?> toOpenAiResponsesBody() {
    return {
      'model': model,
      'store': false,
      'reasoning': {'effort': reasoningEffort},
      'text': {'verbosity': 'medium'},
      'instructions':
          'You are Live Translate meeting summary export. Generate an '
          'email-ready executive summary using only the supplied local '
          'transcript context. Do not invent details. Return plain text with '
          'exactly these section headings: Executive Summary, Critical '
          'Talking Points And Outcomes, Actions. Use bullets for critical '
          'talking points and outcomes. Put actions at the bottom. If no '
          'explicit actions are present, write "No explicit actions captured." '
          'Do not include the full transcript; the app appends it locally '
          'when the user chooses Both.',
      'input':
          'Meeting: ${meeting.title}\n'
          'Route: ${meeting.sourceLanguageLabel} -> '
          '${meeting.targetLanguageLabel}\n'
          'Transcript line count: $transcriptEntryCount\n\n'
          'Local transcript context:\n${_summaryPromptContext(meeting)}',
    };
  }

  static String _summaryPromptContext(StoredMeeting meeting) {
    if (meeting.transcriptEntries.isEmpty) {
      return 'No transcript lines are stored for this meeting yet.';
    }

    final lines = <String>[];
    for (final entry in meeting.transcriptEntries) {
      lines
        ..add('[${_timeLabel(entry.timestamp)}] ${entry.languageCode}')
        ..add('Original: ${entry.originalText}')
        ..add('Translation: ${entry.translatedText}');
      if (entry.speakerLabel != null && entry.speakerLabel!.isNotEmpty) {
        lines.add('Speaker: ${entry.speakerLabel}');
      }
      lines.add('');
    }

    return lines.join('\n').trim();
  }
}

class MeetingSummaryResult {
  const MeetingSummaryResult({
    required this.text,
    required this.generatedAt,
    required this.modelIntent,
    required this.transcriptEntryCount,
  });

  final String text;
  final DateTime generatedAt;
  final String modelIntent;
  final int transcriptEntryCount;

  StoredSummaryMetadata toMetadata() {
    return StoredSummaryMetadata(
      available: true,
      updatedAt: generatedAt,
      modelIntent: modelIntent,
      transcriptEntryCount: transcriptEntryCount,
      text: text,
    );
  }
}

abstract interface class MeetingSummaryGateway {
  Future<MeetingSummaryResult> generate({
    required MeetingSummaryRequest request,
    required String credential,
  });
}

class OpenAiResponsesMeetingSummaryGateway implements MeetingSummaryGateway {
  OpenAiResponsesMeetingSummaryGateway({
    Uri? endpoint,
    HttpClientFactory? httpClientFactory,
    this.timeout = const Duration(seconds: 75),
    this.diagnostics = const PrivacySafeDiagnostics(),
  }) : endpoint = endpoint ?? Uri.parse(OpenAiConfiguration.responsesEndpoint),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Uri endpoint;
  final Duration timeout;
  final PrivacySafeDiagnostics diagnostics;
  final HttpClientFactory _httpClientFactory;

  @override
  Future<MeetingSummaryResult> generate({
    required MeetingSummaryRequest request,
    required String credential,
  }) async {
    diagnostics.info(
      'openai.meeting_summary_request_started',
      fields: {
        'operation': 'responses.create',
        'endpoint': endpoint.host,
        'summaryModel': request.model,
        'reasoningEffort': request.reasoningEffort,
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
          'openai.meeting_summary_credential_rejected',
          fields: {
            'operation': 'responses.create',
            'summaryModel': request.model,
            'reasoningEffort': request.reasoningEffort,
            'result': 'credentialRejected',
          },
        );
        throw const MeetingSummaryCredentialException();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        diagnostics.error(
          'openai.meeting_summary_request_failed',
          fields: {
            'operation': 'responses.create',
            'summaryModel': request.model,
            'reasoningEffort': request.reasoningEffort,
            'errorCode': response.statusCode,
            'result': 'httpError',
          },
        );
        throw MeetingSummaryRequestException(statusCode: response.statusCode);
      }

      final decoded = jsonDecode(responseBody);
      final text = OpenAiResponsesText.extract(decoded);
      if (text == null || text.trim().isEmpty) {
        diagnostics.error(
          'openai.meeting_summary_response_malformed',
          fields: {
            'operation': 'responses.create',
            'summaryModel': request.model,
            'reasoningEffort': request.reasoningEffort,
            'result': 'malformedResponse',
          },
        );
        throw const MeetingSummaryMalformedResponseException();
      }

      diagnostics.info(
        'openai.meeting_summary_request_succeeded',
        fields: {
          'operation': 'responses.create',
          'summaryModel': request.model,
          'reasoningEffort': request.reasoningEffort,
          'result': 'success',
        },
      );
      return MeetingSummaryResult(
        text: text.trim(),
        generatedAt: DateTime.now().toUtc(),
        modelIntent: request.model,
        transcriptEntryCount: request.transcriptEntryCount,
      );
    } on MeetingSummaryException {
      rethrow;
    } on TimeoutException catch (error) {
      diagnostics.warning(
        'openai.meeting_summary_network_timeout',
        fields: {
          'operation': 'responses.create',
          'summaryModel': request.model,
          'reasoningEffort': request.reasoningEffort,
          'errorCode': error.runtimeType.toString(),
          'result': 'timeout',
        },
      );
      throw const MeetingSummaryNetworkException();
    } on SocketException catch (error) {
      diagnostics.warning(
        'openai.meeting_summary_network_error',
        fields: {
          'operation': 'responses.create',
          'summaryModel': request.model,
          'reasoningEffort': request.reasoningEffort,
          'errorCode': error.runtimeType.toString(),
          'result': 'networkError',
        },
      );
      throw const MeetingSummaryNetworkException();
    } on FormatException {
      throw const MeetingSummaryMalformedResponseException();
    } finally {
      client.close(force: true);
    }
  }
}

sealed class MeetingSummaryException implements Exception {
  const MeetingSummaryException();
}

class MeetingSummaryCredentialException extends MeetingSummaryException {
  const MeetingSummaryCredentialException();
}

class MeetingSummaryNetworkException extends MeetingSummaryException {
  const MeetingSummaryNetworkException();
}

class MeetingSummaryMalformedResponseException extends MeetingSummaryException {
  const MeetingSummaryMalformedResponseException();
}

class MeetingSummaryRequestException extends MeetingSummaryException {
  const MeetingSummaryRequestException({required this.statusCode});

  final int statusCode;
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}
