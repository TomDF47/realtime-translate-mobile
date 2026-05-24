import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_ai_chat.dart';
import 'package:realtime_translate_mobile/src/openai/openai_configuration.dart';
import 'package:realtime_translate_mobile/src/storage/local_storage_models.dart';
import 'package:realtime_translate_mobile/src/ui/live_translate_models.dart';

void main() {
  test('builds scoped context from local meeting snapshots', () {
    final meetingOne = _meeting(id: 'meeting-1', title: 'Timeline review');
    final meetingTwo = _meeting(id: 'meeting-2', title: 'Budget sync');
    final snapshot = const LocalStorageSnapshot.empty().copyWith(
      meetings: [meetingOne, meetingTwo],
    );

    final thisMeetingContext = AiChatContextBuilder.fromSnapshot(
      scope: AiChatScope.thisMeeting,
      snapshot: snapshot,
      activeMeeting: meetingOne,
    );
    final allMeetingsContext = AiChatContextBuilder.fromSnapshot(
      scope: AiChatScope.allMeetings,
      snapshot: snapshot,
    );

    expect(thisMeetingContext.meetings, hasLength(1));
    expect(thisMeetingContext.toPromptContext(), contains('Timeline review'));
    expect(
      thisMeetingContext.toPromptContext(),
      isNot(contains('Budget sync')),
    );
    expect(allMeetingsContext.meetings, hasLength(2));
    expect(allMeetingsContext.transcriptEntryCount, 2);
  });

  test('creates privacy-preserving Responses API request body', () {
    final context = AiChatContextBuilder.fromSnapshot(
      scope: AiChatScope.thisMeeting,
      snapshot: const LocalStorageSnapshot.empty().copyWith(
        meetings: [_meeting()],
      ),
      activeMeeting: _meeting(),
    );
    final request = AiChatRequest(
      prompt: 'What did they agree?',
      context: context,
    );

    final body = request.toOpenAiResponsesBody();
    final serialized = jsonEncode(body);

    expect(body['model'], OpenAiConfiguration.aiChatModel);
    expect(body['store'], isFalse);
    expect(body['reasoning'], {
      'effort': OpenAiConfiguration.aiChatReasoningEffort,
    });
    expect(serialized, contains('Selected scope: This meeting'));
    expect(serialized, contains('What did they agree?'));
    expect(serialized, isNot(contains('placeholder-local-openai-credential')));
  });

  test('extracts text from common Responses API shapes', () {
    expect(
      OpenAiResponsesText.extract({'output_text': 'Direct helper text'}),
      'Direct helper text',
    );
    expect(
      OpenAiResponsesText.extract({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'Nested text'},
            ],
          },
        ],
      }),
      'Nested text',
    );
  });

  test(
    'posts direct Responses request without leaking credential into body',
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
                        'text': 'They agreed on the timeline (10:37 AM).',
                      },
                    ],
                  },
                ],
              }),
            );
          await request.response.close();
        }),
      );

      final gateway = OpenAiResponsesAiChatGateway(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/responses'),
      );
      final answer = await gateway.ask(
        request: AiChatRequest(
          prompt: 'What did they agree?',
          context: AiChatContextBuilder.fromSnapshot(
            scope: AiChatScope.thisMeeting,
            snapshot: const LocalStorageSnapshot.empty().copyWith(
              meetings: [_meeting()],
            ),
            activeMeeting: _meeting(),
          ),
        ),
        credential: 'placeholder-local-openai-credential',
      );

      await server.close(force: true);

      expect(answer.text, 'They agreed on the timeline (10:37 AM).');
      expect(
        received['authorization'],
        'Bearer placeholder-local-openai-credential',
      );
      expect(
        received['body'],
        isNot(contains('placeholder-local-openai-credential')),
      );
      expect(received['body'], contains('"store":false'));
    },
  );
}

StoredMeeting _meeting({
  String id = 'meeting-1',
  String title = 'Timeline review',
}) {
  final timestamp = DateTime.utc(2026, 5, 24, 2, 37);
  return StoredMeeting(
    id: id,
    title: title,
    createdAt: timestamp,
    updatedAt: timestamp,
    sourceLanguageLabel: 'Spanish',
    targetLanguageLabel: 'English',
    transcriptEntries: [
      StoredTranscriptEntry(
        id: '$id-entry-1',
        meetingId: id,
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
