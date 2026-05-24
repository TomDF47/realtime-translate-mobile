// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:realtime_translate_mobile/src/openai/openai_configuration.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';

const _credentialEnvName = 'OPENAI_API_KEY';
const _timeout = Duration(seconds: 45);

Future<void> main(List<String> args) async {
  final selection = _SmokeSelection.fromArgs(args);
  if (selection == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final credential = Platform.environment[_credentialEnvName]?.trim();
  if (credential == null || credential.isEmpty) {
    stderr.writeln('Missing $_credentialEnvName environment variable.');
    exitCode = 64;
    return;
  }

  final results = <_SmokeResult>[];
  if (selection.summary) {
    results.add(await _runResponsesSmoke(_summarySmokeRequest()));
  }
  if (selection.aiChatThisMeeting) {
    results.add(await _runResponsesSmoke(_aiChatSmokeRequestThisMeeting()));
  }
  if (selection.aiChatAllMeetings) {
    results.add(await _runResponsesSmoke(_aiChatSmokeRequestAllMeetings()));
  }
  if (selection.realtimePrimary) {
    results.add(
      await _runRealtimeSmoke(
        credential: credential,
        name: 'realtime-primary',
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'es',
          profile: OpenAiRealtimeTranslationProfile.primaryRealtime2,
        ),
      ),
    );
  }
  if (selection.realtimeTranslationFallback) {
    results.add(
      await _runRealtimeSmoke(
        credential: credential,
        name: 'realtime-translation-fallback',
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'fr',
          profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
        ),
      ),
    );
  }
  if (selection.realtimeSyntheticAudio) {
    results.add(
      await _runRealtimeSyntheticAudioSmoke(
        credential: credential,
        name: 'realtime-translation-synthetic-audio',
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'fr',
          profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
        ),
      ),
    );
  }
  if (selection.realtimePrimarySyntheticAudio) {
    results.add(
      await _runRealtimePrimarySyntheticAudioSmoke(
        credential: credential,
        name: 'realtime-primary-synthetic-audio',
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'es',
          profile: OpenAiRealtimeTranslationProfile.primaryRealtime2,
        ),
      ),
    );
  }
  if (selection.realtimeGeneratedSpeech) {
    results.add(
      await _runRealtimeGeneratedSpeechSmoke(
        credential: credential,
        name: 'realtime-translation-generated-speech',
        config: const OpenAiRealtimeTranslationConfig(
          targetLanguageCode: 'en',
          profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
        ),
      ),
    );
  }

  print('Live OpenAI smoke results:');
  for (final result in results) {
    print('${result.passed ? 'PASS' : 'FAIL'} ${result.name}: ${result.note}');
  }

  if (results.any((result) => !result.passed)) {
    exitCode = 1;
  }
}

Future<_SmokeResult> _runResponsesSmoke(_ResponsesSmokeRequest smoke) async {
  final credential = Platform.environment[_credentialEnvName]!.trim();
  final client = HttpClient();
  try {
    final request = await client
        .postUrl(Uri.parse(OpenAiConfiguration.responsesEndpoint))
        .timeout(_timeout);
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer $credential');
    request.write(jsonEncode(smoke.body));

    final response = await request.close().timeout(_timeout);
    final responseBody = await utf8.decodeStream(response).timeout(_timeout);
    final errorCode = _safeErrorCode(responseBody);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _SmokeResult.failed(
        smoke.name,
        'responses.create status=${response.statusCode}'
        '${errorCode == null ? '' : ' code=$errorCode'} '
        'model=${smoke.model} reasoning=${smoke.reasoningEffort} '
        'store=false',
      );
    }

    final decoded = jsonDecode(responseBody);
    final text = _extractOutputText(decoded);
    if (text == null || text.trim().isEmpty) {
      return _SmokeResult.failed(
        smoke.name,
        'responses.create returned no extractable text '
        'model=${smoke.model} reasoning=${smoke.reasoningEffort} '
        'store=false',
      );
    }

    String? missingFragment;
    for (final fragment in smoke.requiredOutputFragments) {
      if (!text.contains(fragment)) {
        missingFragment = fragment;
        break;
      }
    }
    if (missingFragment != null) {
      return _SmokeResult.failed(
        smoke.name,
        'responses.create missingExpectedOutputFragment '
        'fragment=$missingFragment model=${smoke.model} '
        'reasoning=${smoke.reasoningEffort} store=false',
      );
    }

    return _SmokeResult.passed(
      smoke.name,
      'responses.create model=${smoke.model} '
      'reasoning=${smoke.reasoningEffort} store=false',
    );
  } on TimeoutException {
    return _SmokeResult.failed(
      smoke.name,
      'responses.create timeout model=${smoke.model} '
      'reasoning=${smoke.reasoningEffort} store=false',
    );
  } on SocketException catch (error) {
    return _SmokeResult.failed(
      smoke.name,
      'responses.create socketError=${error.osError?.errorCode ?? 'unknown'} '
      'model=${smoke.model} reasoning=${smoke.reasoningEffort} store=false',
    );
  } on FormatException {
    return _SmokeResult.failed(
      smoke.name,
      'responses.create malformedJson model=${smoke.model} '
      'reasoning=${smoke.reasoningEffort} store=false',
    );
  } finally {
    client.close(force: true);
  }
}

Future<_SmokeResult> _runRealtimeSmoke({
  required String credential,
  required String name,
  required OpenAiRealtimeTranslationConfig config,
}) async {
  OpenAiRealtimeTranslationSession? session;
  try {
    session = await OpenAiRealtimeTranslationGateway().connect(
      config: config,
      credential: credential,
    );

    final event = await session.events
        .firstWhere(
          (event) =>
              event is OpenAiRealtimeSessionLifecycleEvent ||
              event is OpenAiRealtimeError ||
              event is OpenAiRealtimeSessionClosed,
        )
        .timeout(const Duration(seconds: 10));

    if (event is OpenAiRealtimeError) {
      return _SmokeResult.failed(
        name,
        'websocket event=${event.type} code=${event.code ?? 'unknown'} '
        '${_safeRealtimeErrorParam(event)}'
        'model=${config.profile.model} path=${config.profile.path}',
      );
    }

    if (event is OpenAiRealtimeSessionClosed) {
      return _SmokeResult.failed(
        name,
        'websocket closedBeforeReady model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    return _SmokeResult.passed(
      name,
      'websocket event=${event.type} model=${config.profile.model} '
      'path=${config.profile.path}',
    );
  } on WebSocketException catch (error) {
    return _SmokeResult.failed(
      name,
      'websocket handshakeFailed status=${error.httpStatusCode ?? 'unknown'} '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } on TimeoutException {
    return _SmokeResult.failed(
      name,
      'websocket timeout model=${config.profile.model} '
      'path=${config.profile.path}',
    );
  } on SocketException catch (error) {
    return _SmokeResult.failed(
      name,
      'websocket socketError=${error.osError?.errorCode ?? 'unknown'} '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } finally {
    await session?.closeImmediately();
  }
}

Future<_SmokeResult> _runRealtimeSyntheticAudioSmoke({
  required String credential,
  required String name,
  required OpenAiRealtimeTranslationConfig config,
}) async {
  OpenAiRealtimeTranslationSession? session;
  try {
    session = await OpenAiRealtimeTranslationGateway().connect(
      config: config,
      credential: credential,
    );

    final readyEvent = await _waitForRealtimeReady(
      session.events,
      const Duration(seconds: 10),
      requireSessionUpdated: true,
    );

    if (readyEvent == null) {
      return _SmokeResult.failed(
        name,
        'websocket sessionUpdateTimeout model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    if (readyEvent is OpenAiRealtimeError) {
      return _SmokeResult.failed(
        name,
        'websocket event=${readyEvent.type} '
        'code=${readyEvent.code ?? 'unknown'} '
        '${_safeRealtimeErrorParam(readyEvent)}'
        'model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    if (readyEvent is OpenAiRealtimeSessionClosed) {
      return _SmokeResult.failed(
        name,
        'websocket closedBeforeReady model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    session.appendPcm16Audio(_syntheticTonePcm16(config));
    final error = await _waitForRealtimeError(
      session.events,
      const Duration(seconds: 2),
    );
    if (error != null) {
      return _SmokeResult.failed(
        name,
        'websocket syntheticPcm16AppendError code=${error.code ?? 'unknown'} '
        '${_safeRealtimeErrorParam(error)}'
        'model=${config.profile.model} path=${config.profile.path}',
      );
    }

    return _SmokeResult.passed(
      name,
      'websocket syntheticPcm16ToneAppend=200ms nonSpeech '
      'model=${config.profile.model} '
      'path=${config.profile.path}',
    );
  } on WebSocketException catch (error) {
    return _SmokeResult.failed(
      name,
      'websocket handshakeFailed status=${error.httpStatusCode ?? 'unknown'} '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } on TimeoutException {
    return _SmokeResult.failed(
      name,
      'websocket timeout model=${config.profile.model} '
      'path=${config.profile.path}',
    );
  } on SocketException catch (error) {
    return _SmokeResult.failed(
      name,
      'websocket socketError=${error.osError?.errorCode ?? 'unknown'} '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } finally {
    await session?.closeImmediately();
  }
}

Future<_SmokeResult> _runRealtimePrimarySyntheticAudioSmoke({
  required String credential,
  required String name,
  required OpenAiRealtimeTranslationConfig config,
}) async {
  OpenAiRealtimeTranslationSession? session;
  try {
    session = await OpenAiRealtimeTranslationGateway().connect(
      config: config,
      credential: credential,
    );

    final readyEvent = await _waitForRealtimeReady(
      session.events,
      const Duration(seconds: 10),
      requireSessionUpdated: true,
    );

    if (readyEvent == null) {
      return _SmokeResult.failed(
        name,
        'websocket sessionUpdateTimeout model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    if (readyEvent is OpenAiRealtimeError) {
      return _SmokeResult.failed(
        name,
        'websocket event=${readyEvent.type} '
        'code=${readyEvent.code ?? 'unknown'} '
        '${_safeRealtimeErrorParam(readyEvent)}'
        'model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    if (readyEvent is OpenAiRealtimeSessionClosed) {
      return _SmokeResult.failed(
        name,
        'websocket closedBeforeReady model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    session.appendPcm16Audio(_syntheticTonePcm16(config));

    final error = await _waitForRealtimeError(
      session.events,
      const Duration(seconds: 3),
    );
    if (error != null) {
      return _SmokeResult.failed(
        name,
        'websocket syntheticPcm16AppendError code=${error.code ?? 'unknown'} '
        '${_safeRealtimeErrorParam(error)}'
        'model=${config.profile.model} path=${config.profile.path}',
      );
    }

    return _SmokeResult.passed(
      name,
      'websocket syntheticPcm16ToneAppend=200ms nonSpeech '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } on WebSocketException catch (error) {
    return _SmokeResult.failed(
      name,
      'websocket handshakeFailed status=${error.httpStatusCode ?? 'unknown'} '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } on TimeoutException {
    return _SmokeResult.failed(
      name,
      'websocket timeout model=${config.profile.model} '
      'path=${config.profile.path}',
    );
  } on SocketException catch (error) {
    return _SmokeResult.failed(
      name,
      'websocket socketError=${error.osError?.errorCode ?? 'unknown'} '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } finally {
    await session?.closeImmediately();
  }
}

Future<_SmokeResult> _runRealtimeGeneratedSpeechSmoke({
  required String credential,
  required String name,
  required OpenAiRealtimeTranslationConfig config,
}) async {
  final speech = await _generateSpeechPcm16(config);
  if (speech.failureNote != null) {
    return _SmokeResult.failed(name, speech.failureNote!);
  }

  OpenAiRealtimeTranslationSession? session;
  try {
    session = await OpenAiRealtimeTranslationGateway().connect(
      config: config,
      credential: credential,
    );

    final readyEvent = await _waitForRealtimeReady(
      session.events,
      const Duration(seconds: 10),
      requireSessionUpdated: true,
    );

    if (readyEvent == null) {
      return _SmokeResult.failed(
        name,
        'websocket sessionUpdateTimeout model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    if (readyEvent is OpenAiRealtimeError) {
      return _SmokeResult.failed(
        name,
        'websocket event=${readyEvent.type} '
        'code=${readyEvent.code ?? 'unknown'} '
        '${_safeRealtimeErrorParam(readyEvent)}'
        'model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    if (readyEvent is OpenAiRealtimeSessionClosed) {
      return _SmokeResult.failed(
        name,
        'websocket closedBeforeReady model=${config.profile.model} '
        'path=${config.profile.path}',
      );
    }

    final evidenceFuture = _waitForGeneratedSpeechEvidence(
      session.events,
      const Duration(seconds: 18),
    );

    for (final chunk in _pcm16Chunks(
      speech.pcm16!,
      sampleRate: config.inputAudioRate,
      chunkDuration: const Duration(milliseconds: 200),
    )) {
      session.appendPcm16Audio(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    session.appendPcm16Audio(_silencePcm16(config.inputAudioRate, 500));

    final evidence = await evidenceFuture;
    if (evidence.error != null) {
      final error = evidence.error!;
      return _SmokeResult.failed(
        name,
        'websocket generatedSpeechError code=${error.code ?? 'unknown'} '
        '${_safeRealtimeErrorParam(error)}'
        'model=${config.profile.model} path=${config.profile.path}',
      );
    }

    if (!evidence.hasTranscript || !evidence.hasTranslatedAudio) {
      return _SmokeResult.failed(
        name,
        'websocket generatedSpeechMissingEvidence '
        'transcriptEvents=${evidence.transcriptEvents} '
        'translatedAudioEvents=${evidence.audioEvents} '
        'model=${config.profile.model} path=${config.profile.path}',
      );
    }

    return _SmokeResult.passed(
      name,
      'websocket generatedSpeech=local-espeak-ng '
      'transcriptEvents=${evidence.transcriptEvents} '
      'translatedAudioEvents=${evidence.audioEvents} '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } on WebSocketException catch (error) {
    return _SmokeResult.failed(
      name,
      'websocket handshakeFailed status=${error.httpStatusCode ?? 'unknown'} '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } on TimeoutException {
    return _SmokeResult.failed(
      name,
      'websocket timeout model=${config.profile.model} '
      'path=${config.profile.path}',
    );
  } on SocketException catch (error) {
    return _SmokeResult.failed(
      name,
      'websocket socketError=${error.osError?.errorCode ?? 'unknown'} '
      'model=${config.profile.model} path=${config.profile.path}',
    );
  } finally {
    await session?.closeImmediately();
  }
}

List<int> _syntheticTonePcm16(OpenAiRealtimeTranslationConfig config) {
  const chunkDuration = Duration(milliseconds: 200);
  const frequencyHz = 440;
  final sampleCount =
      config.inputAudioRate *
      chunkDuration.inMilliseconds ~/
      Duration.millisecondsPerSecond;
  final bytes = List<int>.filled(sampleCount * 2, 0);

  for (var i = 0; i < sampleCount; i += 1) {
    final sample =
        (math.sin(2 * math.pi * frequencyHz * i / config.inputAudioRate) *
                0x2000)
            .round();
    bytes[i * 2] = sample & 0xff;
    bytes[i * 2 + 1] = (sample >> 8) & 0xff;
  }

  return bytes;
}

List<int> _silencePcm16(int sampleRate, int milliseconds) {
  final sampleCount =
      sampleRate * milliseconds ~/ Duration.millisecondsPerSecond;
  return List<int>.filled(sampleCount * 2, 0);
}

Iterable<List<int>> _pcm16Chunks(
  List<int> pcm16, {
  required int sampleRate,
  required Duration chunkDuration,
}) sync* {
  final chunkSize =
      sampleRate *
      chunkDuration.inMilliseconds ~/
      Duration.millisecondsPerSecond *
      2;
  for (var offset = 0; offset < pcm16.length; offset += chunkSize) {
    yield pcm16.sublist(offset, math.min(offset + chunkSize, pcm16.length));
  }
}

Future<_GeneratedSpeech> _generateSpeechPcm16(
  OpenAiRealtimeTranslationConfig config,
) async {
  final executable = await _findExecutable('espeak-ng');
  if (executable == null) {
    return const _GeneratedSpeech.failure(
      'generatedSpeech dependencyUnavailable executable=espeak-ng',
    );
  }

  final result = await Process.run(executable, const [
    '-v',
    'es',
    '--stdout',
    'Revisaremos el cronograma.',
  ], stdoutEncoding: null);
  if (result.exitCode != 0 || result.stdout is! List<int>) {
    return _GeneratedSpeech.failure(
      'generatedSpeech synthesisFailed exit=${result.exitCode}',
    );
  }

  try {
    final wav = _Pcm16Wav.parse(Uint8List.fromList(result.stdout as List<int>));
    return _GeneratedSpeech.success(
      wav.resampleMonoPcm16(config.inputAudioRate),
    );
  } on FormatException catch (error) {
    return _GeneratedSpeech.failure(
      'generatedSpeech malformedWav reason=${error.message}',
    );
  }
}

Future<String?> _findExecutable(String name) async {
  final result = await Process.run('which', [name]);
  if (result.exitCode != 0) {
    return null;
  }

  final path = result.stdout.toString().trim();
  return path.isEmpty ? null : path;
}

Future<OpenAiRealtimeError?> _waitForRealtimeError(
  Stream<OpenAiRealtimeEvent> events,
  Duration timeout,
) async {
  final completer = Completer<OpenAiRealtimeError?>();
  late final StreamSubscription<OpenAiRealtimeEvent> subscription;
  Timer? timer;
  subscription = events.listen((event) {
    if (event is OpenAiRealtimeError && !completer.isCompleted) {
      completer.complete(event);
    }
  });
  timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  });

  return completer.future.whenComplete(() async {
    timer?.cancel();
    await subscription.cancel();
  });
}

Future<_GeneratedSpeechEvidence> _waitForGeneratedSpeechEvidence(
  Stream<OpenAiRealtimeEvent> events,
  Duration timeout,
) async {
  final completer = Completer<_GeneratedSpeechEvidence>();
  late final StreamSubscription<OpenAiRealtimeEvent> subscription;
  Timer? timer;
  var transcriptEvents = 0;
  var audioEvents = 0;

  void complete({OpenAiRealtimeError? error}) {
    if (completer.isCompleted) {
      return;
    }
    completer.complete(
      _GeneratedSpeechEvidence(
        transcriptEvents: transcriptEvents,
        audioEvents: audioEvents,
        error: error,
      ),
    );
  }

  subscription = events.listen((event) {
    if (event is OpenAiRealtimeError) {
      complete(error: event);
      return;
    }
    if (event is OpenAiRealtimeTranscriptDelta ||
        event is OpenAiRealtimeTranscriptCompleted) {
      transcriptEvents += 1;
    }
    if (event is OpenAiRealtimeAudioDelta) {
      audioEvents += 1;
    }
    if (transcriptEvents > 0 && audioEvents > 0) {
      complete();
    }
  });
  timer = Timer(timeout, complete);

  return completer.future.whenComplete(() async {
    timer?.cancel();
    await subscription.cancel();
  });
}

Future<OpenAiRealtimeEvent?> _waitForRealtimeReady(
  Stream<OpenAiRealtimeEvent> events,
  Duration timeout, {
  required bool requireSessionUpdated,
}) async {
  final completer = Completer<OpenAiRealtimeEvent?>();
  late final StreamSubscription<OpenAiRealtimeEvent> subscription;
  Timer? timer;

  subscription = events.listen((event) {
    if (completer.isCompleted) {
      return;
    }

    if (event is OpenAiRealtimeError || event is OpenAiRealtimeSessionClosed) {
      completer.complete(event);
      return;
    }

    if (event is OpenAiRealtimeSessionLifecycleEvent) {
      if (!requireSessionUpdated || event.type == 'session.updated') {
        completer.complete(event);
      }
    }
  });

  timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  });

  return completer.future.whenComplete(() async {
    timer?.cancel();
    await subscription.cancel();
  });
}

_ResponsesSmokeRequest _summarySmokeRequest() {
  return _ResponsesSmokeRequest(
    name: 'summary-export',
    model: OpenAiConfiguration.summaryModel,
    reasoningEffort: OpenAiConfiguration.summaryReasoningEffort,
    body: {
      'model': OpenAiConfiguration.summaryModel,
      'store': false,
      'reasoning': {'effort': OpenAiConfiguration.summaryReasoningEffort},
      'text': {'verbosity': 'low'},
      'instructions':
          'Generate a short email-ready meeting summary using only the '
          'provided synthetic transcript. Return plain text with the headings '
          'Executive Summary, Critical Talking Points And Outcomes, Actions.',
      'input':
          'Meeting: Synthetic smoke test\n'
          'Route: Spanish -> English\n'
          'Transcript line count: 1\n\n'
          'Local transcript context:\n'
          '[10:37 AM] ES\n'
          'Original: Revisaremos el cronograma.\n'
          'Translation: We will review the timeline.',
    },
    requiredOutputFragments: const [
      'Executive Summary',
      'Critical Talking Points And Outcomes',
      'Actions',
    ],
  );
}

_ResponsesSmokeRequest _aiChatSmokeRequestThisMeeting() {
  return _ResponsesSmokeRequest(
    name: 'ai-chat-this-meeting',
    model: OpenAiConfiguration.aiChatModel,
    reasoningEffort: OpenAiConfiguration.aiChatReasoningEffort,
    body: {
      'model': OpenAiConfiguration.aiChatModel,
      'store': false,
      'reasoning': {'effort': OpenAiConfiguration.aiChatReasoningEffort},
      'text': {'verbosity': 'low'},
      'instructions':
          'Answer only from the supplied local transcript context. Cite the '
          'timestamp label when possible.',
      'input':
          'Selected scope: This meeting\n'
          'User question: What did the team agree to review?\n\n'
          'Local transcript context:\n'
          'Meeting: Synthetic smoke test\n'
          'Route: Spanish -> English\n'
          '[10:37 AM] ES\n'
          'Original: Revisaremos el cronograma.\n'
          'Translation: We will review the timeline.',
    },
  );
}

_ResponsesSmokeRequest _aiChatSmokeRequestAllMeetings() {
  return _ResponsesSmokeRequest(
    name: 'ai-chat-all-meetings',
    model: OpenAiConfiguration.aiChatModel,
    reasoningEffort: OpenAiConfiguration.aiChatReasoningEffort,
    body: {
      'model': OpenAiConfiguration.aiChatModel,
      'store': false,
      'reasoning': {'effort': OpenAiConfiguration.aiChatReasoningEffort},
      'text': {'verbosity': 'low'},
      'instructions':
          'Answer only from the supplied local transcript context. Cite the '
          'timestamp label when possible.',
      'input':
          'Selected scope: All meetings\n'
          'User question: What topics appear in the local meeting history?\n\n'
          'Local transcript context:\n'
          'Meeting: Synthetic smoke test\n'
          'Route: Spanish -> English\n'
          '[10:37 AM] ES\n'
          'Original: Revisaremos el cronograma.\n'
          'Translation: We will review the timeline.\n\n'
          'Meeting: Synthetic follow-up smoke test\n'
          'Route: French -> English\n'
          '[10:42 AM] FR\n'
          'Original: Nous confirmerons le budget.\n'
          'Translation: We will confirm the budget.',
    },
  );
}

String? _extractOutputText(Object? decoded) {
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

String? _safeErrorCode(String responseBody) {
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<Object?, Object?>) {
      return null;
    }
    final error = decoded['error'];
    if (error is! Map<Object?, Object?>) {
      return null;
    }
    final code = error['code'] ?? error['type'];
    if (code is String && RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(code)) {
      return code;
    }
  } on FormatException {
    return null;
  }

  return null;
}

String _safeRealtimeErrorParam(OpenAiRealtimeError error) {
  final param = error.param;
  if (param == null || !RegExp(r'^[a-zA-Z0-9_.\[\]-]+$').hasMatch(param)) {
    return '';
  }

  return 'param=$param ';
}

void _printUsage() {
  print('Usage: dart run scripts/live_openai_smoke.dart [options]');
  print('');
  print('Requires OPENAI_API_KEY in the process environment.');
  print('Options:');
  print('  --all                         Run every smoke target (default).');
  print(
    '  --responses-only              Run Summary and AI chat Responses calls.',
  );
  print(
    '  --summary                     Run Summary/Both export Responses smoke.',
  );
  print('  --ai-chat-this-meeting         Run This meeting AI chat smoke.');
  print('  --ai-chat-all-meetings         Run All meetings AI chat smoke.');
  print('  --realtime-primary            Run gpt-realtime-2 WebSocket smoke.');
  print(
    '  --realtime-translation         Run gpt-realtime-translate WebSocket smoke.',
  );
  print(
    '  --realtime-synthetic-audio     Append 200 ms non-speech synthetic PCM16 tone to the translation profile.',
  );
  print(
    '  --realtime-primary-synthetic-audio'
    ' Append 200 ms non-speech synthetic PCM16 tone to gpt-realtime-2.',
  );
  print(
    '  --realtime-generated-speech'
    ' Stream local generated Spanish speech to the translation profile.',
  );
}

class _SmokeSelection {
  const _SmokeSelection({
    required this.summary,
    required this.aiChatThisMeeting,
    required this.aiChatAllMeetings,
    required this.realtimePrimary,
    required this.realtimeTranslationFallback,
    required this.realtimeSyntheticAudio,
    required this.realtimePrimarySyntheticAudio,
    required this.realtimeGeneratedSpeech,
  });

  final bool summary;
  final bool aiChatThisMeeting;
  final bool aiChatAllMeetings;
  final bool realtimePrimary;
  final bool realtimeTranslationFallback;
  final bool realtimeSyntheticAudio;
  final bool realtimePrimarySyntheticAudio;
  final bool realtimeGeneratedSpeech;

  static _SmokeSelection? fromArgs(List<String> args) {
    if (args.isEmpty || args.contains('--all')) {
      return const _SmokeSelection(
        summary: true,
        aiChatThisMeeting: true,
        aiChatAllMeetings: true,
        realtimePrimary: true,
        realtimeTranslationFallback: true,
        realtimeSyntheticAudio: true,
        realtimePrimarySyntheticAudio: true,
        realtimeGeneratedSpeech: true,
      );
    }

    if (args.any((arg) => !arg.startsWith('--'))) {
      return null;
    }

    const knownArgs = {
      '--responses-only',
      '--summary',
      '--ai-chat-this-meeting',
      '--ai-chat-all-meetings',
      '--realtime-primary',
      '--realtime-translation',
      '--realtime-synthetic-audio',
      '--realtime-primary-synthetic-audio',
      '--realtime-generated-speech',
    };
    if (args.any((arg) => !knownArgs.contains(arg))) {
      return null;
    }

    final responsesOnly = args.contains('--responses-only');
    return _SmokeSelection(
      summary: responsesOnly || args.contains('--summary'),
      aiChatThisMeeting:
          responsesOnly || args.contains('--ai-chat-this-meeting'),
      aiChatAllMeetings:
          responsesOnly || args.contains('--ai-chat-all-meetings'),
      realtimePrimary: args.contains('--realtime-primary'),
      realtimeTranslationFallback: args.contains('--realtime-translation'),
      realtimeSyntheticAudio: args.contains('--realtime-synthetic-audio'),
      realtimePrimarySyntheticAudio: args.contains(
        '--realtime-primary-synthetic-audio',
      ),
      realtimeGeneratedSpeech: args.contains('--realtime-generated-speech'),
    );
  }
}

class _GeneratedSpeech {
  const _GeneratedSpeech._({required this.pcm16, required this.failureNote});

  const _GeneratedSpeech.success(List<int> pcm16)
    : this._(pcm16: pcm16, failureNote: null);

  const _GeneratedSpeech.failure(String note)
    : this._(pcm16: null, failureNote: note);

  final List<int>? pcm16;
  final String? failureNote;
}

class _GeneratedSpeechEvidence {
  const _GeneratedSpeechEvidence({
    required this.transcriptEvents,
    required this.audioEvents,
    required this.error,
  });

  final int transcriptEvents;
  final int audioEvents;
  final OpenAiRealtimeError? error;

  bool get hasTranscript => transcriptEvents > 0;

  bool get hasTranslatedAudio => audioEvents > 0;
}

class _Pcm16Wav {
  const _Pcm16Wav({
    required this.sampleRate,
    required this.channelCount,
    required this.samples,
  });

  final int sampleRate;
  final int channelCount;
  final Int16List samples;

  static _Pcm16Wav parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 44 ||
        _fourCc(bytes, 0) != 'RIFF' ||
        _fourCc(bytes, 8) != 'WAVE') {
      throw const FormatException('notRiffWave');
    }

    int? sampleRate;
    int? channelCount;
    int? bitsPerSample;
    int? audioFormat;
    Uint8List? pcmData;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = _fourCc(bytes, offset);
      var size = data.getUint32(offset + 4, Endian.little);
      final payloadOffset = offset + 8;
      if (payloadOffset + size > bytes.length) {
        if (id != 'data') {
          throw const FormatException('truncatedChunk');
        }
        size = bytes.length - payloadOffset;
      }
      final nextOffset = payloadOffset + size + (size.isOdd ? 1 : 0);

      if (id == 'fmt ') {
        audioFormat = data.getUint16(payloadOffset, Endian.little);
        channelCount = data.getUint16(payloadOffset + 2, Endian.little);
        sampleRate = data.getUint32(payloadOffset + 4, Endian.little);
        bitsPerSample = data.getUint16(payloadOffset + 14, Endian.little);
      } else if (id == 'data') {
        pcmData = Uint8List.sublistView(
          bytes,
          payloadOffset,
          payloadOffset + size,
        );
      }
      offset = nextOffset;
    }

    if (audioFormat != 1 ||
        sampleRate == null ||
        channelCount == null ||
        bitsPerSample != 16 ||
        pcmData == null) {
      throw const FormatException('unsupportedWav');
    }

    final pcmBytes = ByteData.sublistView(pcmData);
    final samples = Int16List(pcmData.length ~/ 2);
    for (var i = 0; i < samples.length; i += 1) {
      samples[i] = pcmBytes.getInt16(i * 2, Endian.little);
    }

    return _Pcm16Wav(
      sampleRate: sampleRate,
      channelCount: channelCount,
      samples: samples,
    );
  }

  List<int> resampleMonoPcm16(int targetRate) {
    final monoSampleCount = samples.length ~/ channelCount;
    final mono = Int16List(monoSampleCount);
    for (var frame = 0; frame < monoSampleCount; frame += 1) {
      var sum = 0;
      for (var channel = 0; channel < channelCount; channel += 1) {
        sum += samples[frame * channelCount + channel];
      }
      mono[frame] = sum ~/ channelCount;
    }

    final targetSampleCount = (monoSampleCount * targetRate / sampleRate)
        .round();
    final output = List<int>.filled(targetSampleCount * 2, 0);
    for (var i = 0; i < targetSampleCount; i += 1) {
      final sourcePosition = i * sampleRate / targetRate;
      final left = sourcePosition.floor().clamp(0, monoSampleCount - 1);
      final right = math.min(left + 1, monoSampleCount - 1);
      final fraction = sourcePosition - left;
      final sample = (mono[left] * (1 - fraction) + mono[right] * fraction)
          .round()
          .clamp(-32768, 32767);
      output[i * 2] = sample & 0xff;
      output[i * 2 + 1] = (sample >> 8) & 0xff;
    }
    return output;
  }

  static String _fourCc(Uint8List bytes, int offset) {
    return String.fromCharCodes(bytes.sublist(offset, offset + 4));
  }
}

class _ResponsesSmokeRequest {
  const _ResponsesSmokeRequest({
    required this.name,
    required this.model,
    required this.reasoningEffort,
    required this.body,
    this.requiredOutputFragments = const [],
  });

  final String name;
  final String model;
  final String reasoningEffort;
  final Map<String, Object?> body;
  final List<String> requiredOutputFragments;
}

class _SmokeResult {
  const _SmokeResult._({
    required this.name,
    required this.passed,
    required this.note,
  });

  factory _SmokeResult.passed(String name, String note) {
    return _SmokeResult._(name: name, passed: true, note: note);
  }

  factory _SmokeResult.failed(String name, String note) {
    return _SmokeResult._(name: name, passed: false, note: note);
  }

  final String name;
  final bool passed;
  final String note;
}
