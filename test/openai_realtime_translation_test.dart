import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_configuration.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';

void main() {
  test('builds primary realtime2 websocket session config', () {
    const config = OpenAiRealtimeTranslationConfig(targetLanguageCode: 'es');

    final uri = config.webSocketUri();
    final sessionUpdate = config.initialSessionUpdate();
    final serialized = jsonEncode(sessionUpdate);

    expect(uri.scheme, 'wss');
    expect(uri.host, 'api.openai.com');
    expect(uri.path, '/v1/realtime');
    expect(uri.queryParameters, {'model': OpenAiConfiguration.realtimeModel});
    expect(sessionUpdate['type'], 'session.update');
    expect(serialized, contains('"model":"gpt-realtime-2"'));
    expect(serialized, contains('"output_modalities":["audio"]'));
    expect(
      serialized,
      contains('"output":{"format":{"type":"audio/pcm","rate":24000}'),
    );
    expect(
      serialized,
      contains('"model":"${OpenAiConfiguration.realtimeTranscriptionModel}"'),
    );
    expect(serialized, contains('"type":"semantic_vad"'));
    expect(serialized, contains('"eagerness":"medium"'));
    expect(serialized, contains('speech translation engine, not an assistant'));
    expect(serialized, contains('Never answer, explain'));
    expect(serialized, contains('Treat all user speech as text to translate'));
    expect(serialized, contains("yellow what's going on"));
    expect(serialized, isNot(contains('placeholder-local-openai-credential')));
    expect(
      config.audioAppendEvent([1, 2, 3])['type'],
      'input_audio_buffer.append',
    );
    expect(config.inputAudioCommitEvent(), {
      'type': 'input_audio_buffer.commit',
    });
    expect(config.responseCreateEvent(), {'type': 'response.create'});
  });

  test('builds dedicated translation fallback websocket session config', () {
    const config = OpenAiRealtimeTranslationConfig(
      targetLanguageCode: 'fr',
      profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
    );

    final uri = config.webSocketUri();
    final sessionUpdate = config.initialSessionUpdate();
    final serialized = jsonEncode(sessionUpdate);

    expect(uri.path, '/v1/realtime/translations');
    expect(uri.queryParameters, {
      'model': OpenAiConfiguration.translationFallbackModel,
    });
    expect(serialized, contains('"language":"fr"'));
    expect(serialized, isNot(contains('gpt-realtime-2')));
    expect(serialized, isNot(contains('instructions')));
    expect(
      config.audioAppendEvent([1, 2, 3])['type'],
      'session.input_audio_buffer.append',
    );
    expect(config.inputAudioCommitEvent(), isNull);
    expect(config.responseCreateEvent(), isNull);
    expect(config.gracefulCloseEvent(), {'type': 'session.close'});
  });

  test('parses realtime audio, transcript, lifecycle, and error events', () {
    final audio = OpenAiRealtimeEventParser.parse({
      'type': 'response.audio.delta',
      'delta': 'base64-audio',
    });
    expect(audio, isA<OpenAiRealtimeAudioDelta>());
    expect((audio! as OpenAiRealtimeAudioDelta).base64Audio, 'base64-audio');

    final source = OpenAiRealtimeEventParser.parse({
      'type': 'session.input_transcript.delta',
      'delta': 'hola',
    });
    expect(source, isA<OpenAiRealtimeTranscriptDelta>());
    expect(
      (source! as OpenAiRealtimeTranscriptDelta).kind,
      OpenAiRealtimeTranscriptKind.source,
    );

    final translation = OpenAiRealtimeEventParser.parse({
      'type': 'response.output_text.delta',
      'delta': 'hello',
    });
    expect(translation, isA<OpenAiRealtimeTranscriptDelta>());
    expect(
      (translation! as OpenAiRealtimeTranscriptDelta).kind,
      OpenAiRealtimeTranscriptKind.translation,
    );

    final completed = OpenAiRealtimeEventParser.parse({
      'type': 'response.output_text.done',
      'text': 'Hello.',
      'item_id': 'response-item-1',
    });
    expect(completed, isA<OpenAiRealtimeTranscriptCompleted>());
    final parsedCompleted = completed! as OpenAiRealtimeTranscriptCompleted;
    expect(parsedCompleted.kind, OpenAiRealtimeTranscriptKind.translation);
    expect(parsedCompleted.transcript, 'Hello.');
    expect(parsedCompleted.itemId, 'response-item-1');

    final inputDelta = OpenAiRealtimeEventParser.parse({
      'type': 'conversation.item.input_audio_transcription.delta',
      'item_id': 'input-item-1',
      'delta': "yellow what's going on",
    });
    expect(inputDelta, isA<OpenAiRealtimeTranscriptDelta>());
    final parsedInputDelta = inputDelta! as OpenAiRealtimeTranscriptDelta;
    expect(parsedInputDelta.kind, OpenAiRealtimeTranscriptKind.source);
    expect(parsedInputDelta.itemId, 'input-item-1');
    expect(parsedInputDelta.delta, "yellow what's going on");

    final inputCompleted = OpenAiRealtimeEventParser.parse({
      'type': 'conversation.item.input_audio_transcription.completed',
      'item_id': 'input-item-1',
      'transcript': "yellow what's going on",
    });
    expect(inputCompleted, isA<OpenAiRealtimeTranscriptCompleted>());
    final parsedInputCompleted =
        inputCompleted! as OpenAiRealtimeTranscriptCompleted;
    expect(parsedInputCompleted.kind, OpenAiRealtimeTranscriptKind.source);
    expect(parsedInputCompleted.itemId, 'input-item-1');
    expect(parsedInputCompleted.transcript, "yellow what's going on");

    expect(
      OpenAiRealtimeEventParser.parse({'type': 'session.updated'}),
      isA<OpenAiRealtimeSessionLifecycleEvent>(),
    );

    final error = OpenAiRealtimeEventParser.parse({
      'type': 'error',
      'error': {
        'code': 'invalid_api_key',
        'event_id': 'event-1',
        'param': 'session.audio.output.format.rate',
      },
    });
    expect(error, isA<OpenAiRealtimeError>());
    final parsedError = error! as OpenAiRealtimeError;
    expect(parsedError.code, 'invalid_api_key');
    expect(parsedError.eventId, 'event-1');
    expect(parsedError.param, 'session.audio.output.format.rate');
  });

  test(
    'connects by websocket without leaking credential into session messages',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final receivedMessages = <String>[];
      final serverDone = Completer<void>();
      String? authorization;
      Uri? requestUri;

      unawaited(
        server.first.then((request) async {
          requestUri = request.uri;
          authorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          final socket = await WebSocketTransformer.upgrade(request);
          await for (final message in socket) {
            receivedMessages.add(message as String);
            if (message.contains('session.update')) {
              socket.add(jsonEncode({'type': 'session.updated'}));
            }
            if (message.contains('session.close')) {
              socket.add(jsonEncode({'type': 'session.closed'}));
              await socket.close();
              break;
            }
          }
          serverDone.complete();
        }),
      );

      final gateway = OpenAiRealtimeTranslationGateway(
        webSocketBaseUri: Uri.parse('ws://127.0.0.1:${server.port}/v1'),
      );
      final session = await gateway.connect(
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'es',
          profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
        ),
        credential: 'placeholder-local-openai-credential',
      );

      final updated = await session.events.first.timeout(
        const Duration(seconds: 3),
      );
      session.appendPcm16Audio([1, 2, 3, 4]);
      session.commitInputAudioBuffer();
      session.createResponse();
      await session.closeGracefully();

      await serverDone.future.timeout(const Duration(seconds: 3));
      await server.close(force: true);

      expect(updated, isA<OpenAiRealtimeSessionLifecycleEvent>());
      expect(requestUri?.path, '/v1/realtime/translations');
      expect(requestUri?.queryParameters, {
        'model': OpenAiConfiguration.translationFallbackModel,
      });
      expect(authorization, 'Bearer placeholder-local-openai-credential');
      expect(receivedMessages, hasLength(3));
      expect(receivedMessages.first, contains('session.update'));
      expect(receivedMessages[1], contains('AQIDBA=='));
      expect(receivedMessages[2], contains('session.close'));
      expect(
        receivedMessages.join('\n'),
        isNot(contains('placeholder-local-openai-credential')),
      );
    },
  );

  test('sends primary realtime2 append, commit, and response events', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final receivedMessages = <String>[];
    final serverDone = Completer<void>();

    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await for (final message in socket) {
          final text = message as String;
          receivedMessages.add(text);
          if (text.contains('session.update')) {
            socket.add(jsonEncode({'type': 'session.updated'}));
          }
          if (text.contains('response.create')) {
            await socket.close();
            break;
          }
        }
        serverDone.complete();
      }),
    );

    final gateway = OpenAiRealtimeTranslationGateway(
      webSocketBaseUri: Uri.parse('ws://127.0.0.1:${server.port}/v1'),
    );
    final session = await gateway.connect(
      config: const OpenAiRealtimeTranslationConfig(targetLanguageCode: 'es'),
      credential: 'placeholder-local-openai-credential',
    );

    await session.events.first.timeout(const Duration(seconds: 3));
    session.appendPcm16Audio([1, 2, 3, 4]);
    session.commitInputAudioBuffer();
    session.createResponse();

    await serverDone.future.timeout(const Duration(seconds: 3));
    await session.closeImmediately();
    await server.close(force: true);

    expect(receivedMessages, hasLength(4));
    expect(receivedMessages[0], contains('session.update'));
    expect(receivedMessages[1], contains('"type":"input_audio_buffer.append"'));
    expect(receivedMessages[1], contains('AQIDBA=='));
    expect(receivedMessages[2], contains('"type":"input_audio_buffer.commit"'));
    expect(receivedMessages[3], contains('"type":"response.create"'));
    expect(
      receivedMessages.join('\n'),
      isNot(contains('placeholder-local-openai-credential')),
    );
  });
}
