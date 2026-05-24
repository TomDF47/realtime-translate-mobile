import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_configuration.dart';
import 'package:realtime_translate_mobile/src/openai/openai_meeting_summary.dart';
import 'package:realtime_translate_mobile/src/storage/local_storage_models.dart';

void main() {
  test('creates privacy-preserving summary Responses API request body', () {
    final request = MeetingSummaryRequest(meeting: _meeting());

    final body = request.toOpenAiResponsesBody();
    final serialized = jsonEncode(body);

    expect(body['model'], OpenAiConfiguration.summaryModel);
    expect(body['store'], isFalse);
    expect(body['reasoning'], {
      'effort': OpenAiConfiguration.summaryReasoningEffort,
    });
    expect(serialized, contains('Executive Summary'));
    expect(serialized, contains('Critical Talking Points And Outcomes'));
    expect(serialized, contains('Actions'));
    expect(serialized, contains('Transcript line count: 1'));
    expect(serialized, contains('We will review the timeline.'));
    expect(serialized, isNot(contains('placeholder-local-openai-credential')));
  });

  test(
    'posts direct summary request without leaking credential into body',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <String, Object?>{};
      unawaited(
        server.first.then((request) async {
          received['authorization'] = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          received['body'] = await utf8.decodeStream(request);
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'output': [
                  {
                    'type': 'message',
                    'content': [
                      {
                        'type': 'output_text',
                        'text':
                            'Executive Summary\nThe team agreed on the timeline.\n\n'
                            'Critical Talking Points And Outcomes\n- Timeline review.\n\n'
                            'Actions\n- Share the draft.',
                      },
                    ],
                  },
                ],
              }),
            );
          await request.response.close();
        }),
      );

      final gateway = OpenAiResponsesMeetingSummaryGateway(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/responses'),
      );
      final summary = await gateway.generate(
        request: MeetingSummaryRequest(meeting: _meeting()),
        credential: 'placeholder-local-openai-credential',
      );

      await server.close(force: true);

      expect(summary.modelIntent, OpenAiConfiguration.summaryModel);
      expect(summary.transcriptEntryCount, 1);
      expect(summary.text, contains('Executive Summary'));
      expect(summary.toMetadata().isUsable, isTrue);
      expect(
        received['authorization'],
        'Bearer placeholder-local-openai-credential',
      );
      expect(
        received['body'],
        isNot(contains('placeholder-local-openai-credential')),
      );
      expect(received['body'], contains('"store":false'));
      expect(
        received['body'],
        contains('"effort":"${OpenAiConfiguration.summaryReasoningEffort}"'),
      );
    },
  );
}

StoredMeeting _meeting() {
  final timestamp = DateTime.utc(2026, 5, 24, 2, 37);
  return StoredMeeting(
    id: 'meeting-1',
    title: 'Timeline review',
    createdAt: timestamp,
    updatedAt: timestamp,
    sourceLanguageLabel: 'Spanish',
    targetLanguageLabel: 'English',
    transcriptEntries: [
      StoredTranscriptEntry(
        id: 'meeting-1-entry-1',
        meetingId: 'meeting-1',
        languageCode: 'ES',
        originalText: 'Revisaremos el cronograma.',
        translatedText: 'We will review the timeline.',
        timestamp: timestamp,
        speakerLabel: null,
        confidence: null,
        status: 'final',
        playbackState: 'playable',
      ),
    ],
    summaryMetadata: const StoredSummaryMetadata.empty(),
  );
}
