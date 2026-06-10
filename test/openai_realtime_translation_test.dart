import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/diagnostics/privacy_safe_diagnostics.dart';
import 'package:realtime_translate_mobile/src/openai/openai_configuration.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_resilience.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';

void main() {
  test('builds Gemini live translate setup and audio messages', () {
    final setup = GeminiLiveTranslationMessages.setup(targetLanguageCode: 'it');
    final audio = GeminiLiveTranslationMessages.audioAppend([1, 2, 3, 4]);
    final serializedSetup = jsonEncode(setup);
    final serializedAudio = jsonEncode(audio);

    expect(
      serializedSetup,
      contains('"model":"models/gemini-3.5-live-translate-preview"'),
    );
    expect(serializedSetup, contains('"responseModalities":["AUDIO"]'));
    expect(serializedSetup, contains('"inputAudioTranscription":{}'));
    expect(serializedSetup, contains('"outputAudioTranscription":{}'));
    expect(serializedSetup, contains('"targetLanguageCode":"it"'));
    expect(serializedSetup, contains('"echoTargetLanguage":true'));
    expect(serializedSetup, isNot(contains('placeholder-local-gemini-key')));

    expect(serializedAudio, contains('"realtimeInput"'));
    expect(serializedAudio, contains('"mimeType":"audio/pcm;rate=16000"'));
    expect(serializedAudio, contains('"data":"AQIDBA=="'));
    expect(serializedAudio, isNot(contains('placeholder-local-gemini-key')));
  });

  test('parses Gemini serverContent transcripts and translated audio', () {
    final input = GeminiLiveTranslationEventParser.parse({
      'serverContent': {
        'inputTranscription': {'text': 'ciao', 'languageCode': 'it'},
      },
    });
    expect(input, isA<OpenAiRealtimeTranscriptDelta>());
    final parsedInput = input! as OpenAiRealtimeTranscriptDelta;
    expect(parsedInput.kind, OpenAiRealtimeTranscriptKind.source);
    expect(parsedInput.delta, 'ciao');
    expect(parsedInput.languageCode, 'it');

    final output = GeminiLiveTranslationEventParser.parse({
      'serverContent': {
        'outputTranscription': {'text': 'hello', 'languageCode': 'en'},
      },
    });
    expect(output, isA<OpenAiRealtimeTranscriptDelta>());
    final parsedOutput = output! as OpenAiRealtimeTranscriptDelta;
    expect(parsedOutput.kind, OpenAiRealtimeTranscriptKind.translation);
    expect(parsedOutput.delta, 'hello');
    expect(parsedOutput.languageCode, 'en');

    final audio = GeminiLiveTranslationEventParser.parse({
      'serverContent': {
        'modelTurn': {
          'parts': [
            {
              'inlineData': {
                'mimeType': 'audio/pcm;rate=24000',
                'data': 'base64-audio',
              },
            },
          ],
        },
      },
    });
    expect(audio, isA<OpenAiRealtimeAudioDelta>());
    expect((audio! as OpenAiRealtimeAudioDelta).base64Audio, 'base64-audio');
  });

  test(
    'Gemini websocket keeps API key out of JSON messages and diagnostics',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final receivedMessages = <String>[];
      final serverDone = Completer<void>();
      final sink = MemoryPrivacySafeDiagnosticsSink();
      Uri? requestUri;
      String? authorization;

      unawaited(
        server.first.then((request) async {
          requestUri = request.uri;
          authorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          final socket = await WebSocketTransformer.upgrade(request);
          await for (final message in socket) {
            receivedMessages.add(message as String);
            if (message.contains('"setup"')) {
              socket.add(jsonEncode({'setupComplete': {}}));
            }
            if (message.contains('"realtimeInput"')) {
              await socket.close();
              break;
            }
          }
          serverDone.complete();
        }),
      );

      final gateway = GeminiLiveTranslationGateway(
        webSocketBaseUri: Uri.parse('ws://127.0.0.1:${server.port}'),
        diagnostics: PrivacySafeDiagnostics(sink: sink),
      );
      final session = await gateway.connect(
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'es',
          inputAudioRate: GeminiConfiguration.liveTranslateInputAudioRate,
          outputAudioRate: GeminiConfiguration.liveTranslateOutputAudioRate,
        ),
        credential: 'placeholder-local-gemini-key',
      );
      await session.events.first.timeout(const Duration(seconds: 3));
      session.appendPcm16Audio([1, 2, 3, 4]);
      await serverDone.future.timeout(const Duration(seconds: 3));
      await session.closeImmediately();
      await server.close(force: true);

      expect(requestUri?.path, GeminiConfiguration.liveTranslateWebSocketPath);
      expect(
        requestUri?.queryParameters['key'],
        'placeholder-local-gemini-key',
      );
      expect(authorization, isNull);
      expect(receivedMessages, hasLength(2));
      expect(receivedMessages.first, contains('"targetLanguageCode":"es"'));
      expect(receivedMessages.last, contains('"audio/pcm;rate=16000"'));
      expect(
        receivedMessages.join('\n'),
        isNot(contains('placeholder-local-gemini-key')),
      );
      expect(
        sink.records
            .map(
              (record) => jsonEncode({
                'event': record.event,
                'severity': record.severity.name,
                'fields': record.fields,
              }),
            )
            .join('\n'),
        isNot(contains('placeholder-local-gemini-key')),
      );
    },
  );

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
    expect(audio.keys, containsAll(<String>['input', 'output']));
    expect(output.keys, ['language']);
    expect(output['language'], 'fr');
    // The dedicated endpoint does not accept custom prompts or a source
    // language; we must not leak the model, instructions, or a source language
    // into the translation session config.
    expect(serialized, isNot(contains('gpt-realtime-2')));
    expect(serialized, isNot(contains('gpt-realtime-translate')));
    expect(serialized, isNot(contains('instructions')));
    expect(serialized, isNot(contains('"sourceLanguageCode"')));
    expect(serialized, isNot(contains('"source"')));
    expect(serialized, isNot(contains('"language":"en"')));
    expect(
      config.audioAppendEvent([1, 2, 3])['type'],
      'session.input_audio_buffer.append',
    );
    expect(config.inputAudioCommitEvent(), isNull);
    expect(config.responseCreateEvent(), isNull);
    expect(config.gracefulCloseEvent(), {'type': 'session.close'});
  });

  test('dedicated translation session enables source input transcription', () {
    // Regression for Tom's installed-app retest after PR #49: the original
    // speech never appeared and every turn collapsed into one block because
    // the dedicated `/v1/realtime/translations` session never enabled input
    // transcription, so the endpoint emitted no source
    // (`session.input_transcript`) events at all. Without source events the
    // committer never reaches a source-turn boundary, so output transcript
    // deltas keep appending to a single block.
    //
    // Per the official OpenAI Realtime Translation guide and cookbook, the
    // source/original transcript is only emitted when
    // `session.audio.input.transcription` is configured. This test fails on
    // main/a7a2743 (no `input` key) and passes once the config requests the
    // streaming transcription model.
    const config = OpenAiRealtimeTranslationConfig(targetLanguageCode: 'es');

    final sessionUpdate = config.initialSessionUpdate();
    final session = sessionUpdate['session']! as Map<String, Object?>;
    final audio = session['audio']! as Map<String, Object?>;
    final input = audio['input']! as Map<String, Object?>;
    final transcription = input['transcription']! as Map<String, Object?>;
    final noiseReduction = input['noise_reduction']! as Map<String, Object?>;

    expect(
      transcription['model'],
      OpenAiConfiguration.translationTranscriptionModel,
      reason:
          'input transcription must be configured so the endpoint emits '
          'session.input_transcript source events',
    );
    expect(transcription['model'], 'gpt-realtime-whisper');
    expect(
      noiseReduction['type'],
      OpenAiConfiguration.realtimeInputNoiseReduction,
    );
    // The translation endpoint rejects custom prompting and voice selection,
    // and source language is detected server-side, so we still send no
    // model, instructions, or source language.
    final serialized = jsonEncode(sessionUpdate);
    expect(serialized, isNot(contains('instructions')));
    expect(serialized, isNot(contains('"language":"auto"')));
  });

  test('reverse-direction session omits source input transcription', () {
    // The reverse (B-to-A) audio session must NOT request input transcription:
    // it only produces translated audio for the other listener. Requesting
    // source transcripts on both sessions would emit a duplicate source
    // transcript per utterance and create a second, sourceless card. The
    // reverse-direction TEXT is owned by the direct OpenAI text path instead.
    const reverseConfig = OpenAiRealtimeTranslationConfig(
      targetLanguageCode: 'it',
      sourceTranscriptionEnabled: false,
    );

    final sessionUpdate = reverseConfig.initialSessionUpdate();
    final session = sessionUpdate['session']! as Map<String, Object?>;
    final audio = session['audio']! as Map<String, Object?>;
    final input = audio['input']! as Map<String, Object?>;
    final output = audio['output']! as Map<String, Object?>;

    expect(input.containsKey('transcription'), isFalse);
    expect(
      (input['noise_reduction']! as Map<String, Object?>)['type'],
      OpenAiConfiguration.realtimeInputNoiseReduction,
    );
    expect(output['language'], 'it');
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

    final nestedLanguage = OpenAiRealtimeEventParser.parse({
      'type': 'conversation.item.input_audio_transcription.completed',
      'item': {
        'id': 'input-item-it',
        'metadata': {'language': 'it'},
      },
      'transcript': 'Ciao, grazie.',
    });
    expect(nestedLanguage, isA<OpenAiRealtimeTranscriptCompleted>());
    final parsedNestedLanguage =
        nestedLanguage! as OpenAiRealtimeTranscriptCompleted;
    expect(parsedNestedLanguage.itemId, 'input-item-it');
    expect(parsedNestedLanguage.languageCode, 'it');

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
      // The session.update sent on the wire must request input transcription so
      // the dedicated translation endpoint streams the source/original
      // transcript. This is the end-to-end (gateway -> socket) guarantee that
      // the original speech can appear in the live UI.
      final firstSent =
          jsonDecode(receivedMessages.first) as Map<String, dynamic>;
      final sentSession = firstSent['session'] as Map<String, dynamic>;
      final sentAudio = sentSession['audio'] as Map<String, dynamic>;
      final sentInput = sentAudio['input'] as Map<String, dynamic>;
      final sentTranscription =
          sentInput['transcription'] as Map<String, dynamic>;
      expect(sentTranscription['model'], 'gpt-realtime-whisper');
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

  test('closeImmediately completes without listening to events', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await for (final message in socket) {
          if ((message as String).contains('session.update')) {
            socket.add(jsonEncode({'type': 'session.updated'}));
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

    // Intentionally never listen to session.events. The single-subscription
    // controller previously left closeImmediately() awaiting a done event that
    // could never be delivered, hanging the close path forever.
    await session.closeImmediately().timeout(
      const Duration(seconds: 2),
      onTimeout: () =>
          fail('closeImmediately hung when events stream had no listener'),
    );
  });

  test('closeGracefully completes without listening to events', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await for (final message in socket) {
          final text = message as String;
          if (text.contains('session.update')) {
            socket.add(jsonEncode({'type': 'session.updated'}));
          }
          if (text.contains('session.close')) {
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

    // The graceful path delegates to closeImmediately(); it must also complete
    // promptly when nothing ever listened to session.events.
    await session.closeGracefully().timeout(
      const Duration(seconds: 2),
      onTimeout: () =>
          fail('closeGracefully hung when events stream had no listener'),
    );
  });

  test(
    'mid-session live socket drop surfaces a retryable reconnect trigger',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      unawaited(
        server.first.then((request) async {
          final socket = await WebSocketTransformer.upgrade(request);
          await for (final message in socket) {
            if ((message as String).contains('session.update')) {
              socket.add(jsonEncode({'type': 'session.updated'}));
              // Simulate a live transport drop: the realtime socket goes away
              // mid-session with no application-level session.close handshake,
              // which is what a network loss or server hangup looks like.
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

      final events = <OpenAiRealtimeEvent>[];
      final sessionClosedObserved = Completer<void>();
      session.events.listen(
        (event) {
          events.add(event);
          if (event is OpenAiRealtimeSessionClosed &&
              !sessionClosedObserved.isCompleted) {
            sessionClosedObserved.complete();
          }
        },
        onDone: () {
          if (!sessionClosedObserved.isCompleted) {
            sessionClosedObserved.complete();
          }
        },
      );

      await sessionClosedObserved.future.timeout(const Duration(seconds: 3));

      // The live coordinator subscribes to session.events with onData/onError
      // but no onDone, so production reconnect depends entirely on the real
      // session surfacing an explicit session-closed event when the transport
      // drops. Lock that behavior in on the real product class.
      expect(events.whereType<OpenAiRealtimeSessionClosed>(), isNotEmpty);

      // Reproduce exactly how the coordinator maps each surfaced drop event
      // into a failure, then assert every one routes into bounded
      // reconnect/backoff on the live path (never a fatal stop, never a
      // credential reset).
      const policy = OpenAiRealtimeReconnectPolicy();
      final dropDecisions = <OpenAiRealtimeReconnectDecision>[
        for (final event in events)
          if (event is OpenAiRealtimeError)
            policy.plan(
              failure: OpenAiRealtimeFailure.fromRealtimeError(event),
              retryAttempt: 1,
            )
          else if (event is OpenAiRealtimeSessionClosed)
            policy.plan(
              failure: OpenAiRealtimeFailure.sessionClosed(),
              retryAttempt: 1,
            ),
      ];
      expect(dropDecisions, isNotEmpty);
      for (final decision in dropDecisions) {
        expect(decision.failure.kind.isRetryable, isTrue);
        expect(
          decision.action,
          OpenAiRealtimeRecoveryAction.reconnectAfterBackoff,
        );
      }
    },
  );

  test(
    'live socket close code surfaces a sanitized retryable error event',
    () async {
      final socket = _MidSessionDropWebSocket(dropCloseCode: 1011);
      final gateway = OpenAiRealtimeTranslationGateway(
        webSocketFactory: (uri, headers) async => socket,
      );
      final session = await gateway.connect(
        config: const OpenAiRealtimeTranslationConfig(targetLanguageCode: 'es'),
        credential: 'placeholder-local-openai-credential',
      );

      final events = <OpenAiRealtimeEvent>[];
      final closed = Completer<void>();
      session.events.listen(
        (event) {
          events.add(event);
          if (event is OpenAiRealtimeSessionClosed && !closed.isCompleted) {
            closed.complete();
          }
        },
        onDone: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      );

      // The transport drops mid-session reporting only a close code: no
      // application session.close and no human-readable close reason.
      socket.dropWithCloseCode();
      await closed.future.timeout(const Duration(seconds: 3));

      final errorEvents = events.whereType<OpenAiRealtimeError>().toList();
      expect(errorEvents, isNotEmpty);
      for (final error in errorEvents) {
        final failure = OpenAiRealtimeFailure.fromRealtimeError(error);
        // The diagnostic code is a sanitized close-code token, never a raw
        // server payload, and it must classify as retryable network loss.
        expect(failure.kind, OpenAiRealtimeFailureKind.retryableNetwork);
        expect(failure.diagnosticCode, contains('socket.close_'));
      }
      expect(events.whereType<OpenAiRealtimeSessionClosed>(), isNotEmpty);
    },
  );
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

/// A controllable transport that becomes ready, then drops mid-session while
/// reporting only a numeric close code. It lets the real
/// [OpenAiRealtimeTranslationSession] socket-done path run deterministically
/// without depending on a loopback server's non-deterministic close code.
class _MidSessionDropWebSocket implements WebSocket {
  _MidSessionDropWebSocket({required this.dropCloseCode});

  final int dropCloseCode;
  final StreamController<dynamic> _events = StreamController<dynamic>();
  int? _reportedCloseCode;

  @override
  int? get closeCode => _reportedCloseCode;

  @override
  String? get closeReason => null;

  @override
  void add(dynamic data) {
    if (data is String && data.contains('session.update')) {
      scheduleMicrotask(() {
        if (!_events.isClosed) {
          _events.add(jsonEncode({'type': 'session.updated'}));
        }
      });
    }
  }

  void dropWithCloseCode() {
    _reportedCloseCode = dropCloseCode;
    if (!_events.isClosed) {
      unawaited(_events.close());
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    _reportedCloseCode ??= code;
    if (!_events.isClosed) {
      await _events.close();
    }
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
