import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_configuration.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';

void main() {
  test('builds primary realtime2 websocket session config', () {
    const config = OpenAiRealtimeTranslationConfig(
      targetLanguageCode: 'es',
      profile: OpenAiRealtimeTranslationProfile.primaryRealtime2,
    );

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

  test('defaults to dedicated translation websocket session config', () {
    const config = OpenAiRealtimeTranslationConfig(
      targetLanguageCode: 'fr',
      sourceLanguageCode: 'en',
    );

    final uri = config.webSocketUri();
    final sessionUpdate = config.initialSessionUpdate();
    final serialized = jsonEncode(sessionUpdate);
    final session = sessionUpdate['session']! as Map<String, Object?>;
    final audio = session['audio']! as Map<String, Object?>;
    final output = audio['output']! as Map<String, Object?>;

    expect(uri.path, '/v1/realtime/translations');
    expect(uri.queryParameters, {
      'model': OpenAiConfiguration.translationFallbackModel,
    });
    expect(
      config.profile,
      OpenAiRealtimeTranslationProfile.dedicatedTranslation,
    );
    expect(session.keys, ['audio']);
    expect(audio.keys, ['output']);
    expect(output.keys, ['language']);
    expect(output['language'], 'fr');
    expect(serialized, isNot(contains('gpt-realtime-2')));
    expect(serialized, isNot(contains('gpt-realtime-translate')));
    expect(serialized, isNot(contains('model')));
    expect(serialized, isNot(contains('instructions')));
    expect(serialized, isNot(contains('"sourceLanguageCode"')));
    expect(serialized, isNot(contains('"source"')));
    expect(serialized, isNot(contains('"input"')));
    expect(serialized, isNot(contains('"language":"en"')));
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

    final dedicatedAudio = OpenAiRealtimeEventParser.parse({
      'type': 'session.output_audio.delta',
      'delta': 'base64-translated-audio',
    });
    expect(dedicatedAudio, isA<OpenAiRealtimeAudioDelta>());
    expect(
      (dedicatedAudio! as OpenAiRealtimeAudioDelta).base64Audio,
      'base64-translated-audio',
    );

    final source = OpenAiRealtimeEventParser.parse({
      'type': 'session.input_transcript.delta',
      'delta': 'hola',
      'item_id': 'source-item-1',
    });
    expect(source, isA<OpenAiRealtimeTranscriptDelta>());
    final parsedSource = source! as OpenAiRealtimeTranscriptDelta;
    expect(parsedSource.kind, OpenAiRealtimeTranscriptKind.source);
    expect(parsedSource.itemId, 'source-item-1');

    final translation = OpenAiRealtimeEventParser.parse({
      'type': 'session.output_transcript.delta',
      'delta': 'hello',
      'item_id': 'target-item-1',
    });
    expect(translation, isA<OpenAiRealtimeTranscriptDelta>());
    final parsedTranslation = translation! as OpenAiRealtimeTranscriptDelta;
    expect(parsedTranslation.kind, OpenAiRealtimeTranscriptKind.translation);
    expect(parsedTranslation.itemId, 'target-item-1');

    final completed = OpenAiRealtimeEventParser.parse({
      'type': 'session.output_transcript.done',
      'transcript': 'Hello.',
      'item_id': 'target-item-1',
    });
    expect(completed, isA<OpenAiRealtimeTranscriptCompleted>());
    final parsedCompleted = completed! as OpenAiRealtimeTranscriptCompleted;
    expect(parsedCompleted.kind, OpenAiRealtimeTranscriptKind.translation);
    expect(parsedCompleted.transcript, 'Hello.');
    expect(parsedCompleted.itemId, 'target-item-1');

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

    final inputSegment = OpenAiRealtimeEventParser.parse({
      'type': 'conversation.item.input_audio_transcription.segment',
      'item_id': 'input-item-2',
      'text': 'live source segment',
    });
    expect(inputSegment, isA<OpenAiRealtimeTranscriptDelta>());
    final parsedInputSegment = inputSegment! as OpenAiRealtimeTranscriptDelta;
    expect(parsedInputSegment.kind, OpenAiRealtimeTranscriptKind.source);
    expect(parsedInputSegment.itemId, 'input-item-2');
    expect(parsedInputSegment.delta, 'live source segment');

    expect(
      OpenAiRealtimeEventParser.parse({'type': 'session.updated'}),
      isA<OpenAiRealtimeSessionLifecycleEvent>(),
    );
    expect(
      OpenAiRealtimeEventParser.parse({'type': 'session.closed'}),
      isA<OpenAiRealtimeSessionClosed>(),
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
        config: const OpenAiRealtimeTranslationConfig(targetLanguageCode: 'es'),
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
      expect(
        receivedMessages[1],
        contains('"type":"session.input_audio_buffer.append"'),
      );
      expect(receivedMessages[2], contains('session.close'));
      expect(
        receivedMessages.join('\n'),
        isNot(contains('placeholder-local-openai-credential')),
      );
      expect(
        receivedMessages.join('\n'),
        isNot(contains('input_audio_buffer.commit')),
      );
      expect(receivedMessages.join('\n'), isNot(contains('response.create')));
    },
  );

  test('graceful close waits briefly for session.closed', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final closeRequested = Completer<void>();

    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await for (final message in socket) {
          final text = message as String;
          if (text.contains('session.update')) {
            socket.add(jsonEncode({'type': 'session.updated'}));
          }
          if (text.contains('session.close')) {
            closeRequested.complete();
            await Future<void>.delayed(const Duration(milliseconds: 80));
            socket.add(jsonEncode({'type': 'session.closed'}));
            await socket.close();
            break;
          }
        }
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

    var closeFinished = false;
    final closeFuture = session.closeGracefully().then((_) {
      closeFinished = true;
    });
    await closeRequested.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(closeFinished, isFalse);

    await closeFuture.timeout(const Duration(seconds: 3));
    await server.close(force: true);
    expect(closeFinished, isTrue);
  });

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
      config: const OpenAiRealtimeTranslationConfig(
        targetLanguageCode: 'es',
        profile: OpenAiRealtimeTranslationProfile.primaryRealtime2,
      ),
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

  test('connect waits for session.updated before returning', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sessionUpdatedSent = Completer<void>();

    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await for (final message in socket) {
          if ((message as String).contains('session.update')) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            socket.add(jsonEncode({'type': 'session.updated'}));
            sessionUpdatedSent.complete();
            break;
          }
        }
      }),
    );

    final gateway = OpenAiRealtimeTranslationGateway(
      webSocketBaseUri: Uri.parse('ws://127.0.0.1:${server.port}/v1'),
    );
    var connected = false;
    final connectFuture = gateway
        .connect(
          config: const OpenAiRealtimeTranslationConfig(
            targetLanguageCode: 'es',
            profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
          ),
          credential: 'placeholder-local-openai-credential',
        )
        .then((session) {
          connected = true;
          return session;
        });

    await Future<void>.delayed(Duration.zero);
    expect(connected, isFalse);

    await sessionUpdatedSent.future.timeout(const Duration(seconds: 3));
    final session = await connectFuture.timeout(const Duration(seconds: 3));
    final updated = await session.events.first.timeout(
      const Duration(seconds: 3),
    );
    await session.closeImmediately();
    await server.close(force: true);

    expect(connected, isTrue);
    expect(updated, isA<OpenAiRealtimeSessionLifecycleEvent>());
  });

  test('connect surfaces startup error after session.update', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await for (final message in socket) {
          if ((message as String).contains('session.update')) {
            socket.add(
              jsonEncode({
                'type': 'error',
                'error': {'code': 'invalid_api_key'},
              }),
            );
            break;
          }
        }
      }),
    );

    final gateway = OpenAiRealtimeTranslationGateway(
      webSocketBaseUri: Uri.parse('ws://127.0.0.1:${server.port}/v1'),
    );

    await expectLater(
      gateway.connect(
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'es',
          profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
        ),
        credential: 'placeholder-local-openai-credential',
      ),
      throwsA(
        isA<OpenAiRealtimeStartupException>().having(
          (error) => error.code,
          'code',
          'invalid_api_key',
        ),
      ),
    );
    await server.close(force: true);
  });

  test('startup error does not wait for socket cleanup to finish', () async {
    final socket = _StartupErrorHangingCloseWebSocket('invalid_api_key');
    final gateway = OpenAiRealtimeTranslationGateway(
      webSocketFactory: (uri, headers) async => socket,
    );

    await expectLater(
      gateway
          .connect(
            config: const OpenAiRealtimeTranslationConfig(
              targetLanguageCode: 'es',
              profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
            ),
            credential: 'placeholder-local-openai-credential',
          )
          .timeout(const Duration(milliseconds: 500)),
      throwsA(
        isA<OpenAiRealtimeStartupException>().having(
          (error) => error.code,
          'code',
          'invalid_api_key',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(socket.closeStarted, isTrue);
  });
}

class _StartupErrorHangingCloseWebSocket implements WebSocket {
  _StartupErrorHangingCloseWebSocket(this.errorCode);

  final String errorCode;
  final _events = StreamController<dynamic>();
  bool closeStarted = false;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  void add(dynamic data) {
    if (data is String && data.contains('session.update')) {
      scheduleMicrotask(() {
        _events.add(
          jsonEncode({
            'type': 'error',
            'error': {'code': errorCode},
          }),
        );
      });
    }
  }

  @override
  Future<void> close([int? code, String? reason]) {
    closeStarted = true;
    return Completer<void>().future;
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _events.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
