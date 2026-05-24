// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
}

class _SmokeSelection {
  const _SmokeSelection({
    required this.summary,
    required this.aiChatThisMeeting,
    required this.aiChatAllMeetings,
    required this.realtimePrimary,
    required this.realtimeTranslationFallback,
  });

  final bool summary;
  final bool aiChatThisMeeting;
  final bool aiChatAllMeetings;
  final bool realtimePrimary;
  final bool realtimeTranslationFallback;

  static _SmokeSelection? fromArgs(List<String> args) {
    if (args.isEmpty || args.contains('--all')) {
      return const _SmokeSelection(
        summary: true,
        aiChatThisMeeting: true,
        aiChatAllMeetings: true,
        realtimePrimary: true,
        realtimeTranslationFallback: true,
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
    );
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
