import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/language/language_support.dart';
import 'package:realtime_translate_mobile/src/openai/openai_text_interpreter.dart';
import 'package:realtime_translate_mobile/src/session/live_text_interpreter.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';
import 'package:realtime_translate_mobile/src/storage/local_storage_models.dart';

void main() {
  test('direct OpenAI text interpreter request uses store false', () {
    final gateway = OpenAiResponsesTextInterpreterGateway();

    final body = gateway.requestBody(
      const TextInterpreterTurnRequest(
        text: 'Hola, podemos empezar?',
        knownLanguageCodes: ['es', 'en'],
        sourceLanguageCode: 'es',
        targetLanguageCode: 'en',
        routeType: TranslationRouteType.directOpenAiFallback,
      ),
    );
    final serialized = body.toString();

    expect(body['store'], isFalse);
    expect(serialized, contains('known_language_codes'));
    expect(serialized, contains('target_language_code'));
    expect(serialized, isNot(contains('placeholder-local-openai-credential')));
  });

  test('discovers first language and waits for the other language', () async {
    final harness = await _Harness.create();
    harness.gateway.results.add(
      const TextInterpreterTurnResult(
        detectedLanguageCode: 'es',
        detectedLanguageLabel: 'Spanish',
      ),
    );

    final result = await harness.interpreter.handleTextTurn('Hola equipo');

    expect(result.languageCode, 'ES');
    expect(result.status, 'language_detected');
    expect(result.translatedText, isEmpty);
    expect(
      harness.interpreter.routeLabel,
      'Heard Spanish. Waiting for the other language...',
    );
    expect(harness.gateway.requests.single.knownLanguageCodes, isEmpty);
  });

  test('locks pair and backfills delayed first turn translation', () async {
    final harness = await _Harness.create();
    harness.gateway.results.addAll(const [
      TextInterpreterTurnResult(
        detectedLanguageCode: 'es',
        detectedLanguageLabel: 'Spanish',
      ),
      TextInterpreterTurnResult(
        detectedLanguageCode: 'en',
        detectedLanguageLabel: 'English',
        translatedText: 'Buenos dias.',
      ),
      TextInterpreterTurnResult(
        detectedLanguageCode: 'es',
        detectedLanguageLabel: 'Spanish',
        translatedText: 'Good morning.',
      ),
    ]);

    await harness.interpreter.handleTextTurn('Buenos dias.');
    final second = await harness.interpreter.handleTextTurn('Good morning.');

    expect(harness.interpreter.routeLabel, 'Spanish <-> English');
    expect(harness.interpreter.isPairLocked, isTrue);
    expect(second.languageCode, 'EN');
    expect(second.translatedText, 'Buenos dias.');
    expect(second.status, 'final');
    expect(harness.gateway.requests[1].knownLanguageCodes, ['es']);
    expect(harness.gateway.requests.last.knownLanguageCodes, ['es', 'en']);
    expect(harness.gateway.requests.last.text, 'Buenos dias.');

    final entries = (await harness.repository.loadSnapshot())
        .meetings
        .single
        .transcriptEntries;
    expect(entries, hasLength(2));
    expect(entries.first.originalText, 'Buenos dias.');
    expect(entries.first.translatedText, 'Good morning.');
    expect(entries.first.status, 'delayed_translation');
    expect(entries.last.originalText, 'Good morning.');
    expect(entries.last.translatedText, 'Buenos dias.');
  });

  test(
    'translates subsequent A to B and B to A turns through fake gateway',
    () async {
      final harness = await _Harness.create();
      harness.gateway.results.addAll(const [
        TextInterpreterTurnResult(
          detectedLanguageCode: 'es',
          detectedLanguageLabel: 'Spanish',
        ),
        TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
          translatedText: 'Hello.',
        ),
        TextInterpreterTurnResult(
          detectedLanguageCode: 'es',
          detectedLanguageLabel: 'Spanish',
          translatedText: 'Hello.',
        ),
        TextInterpreterTurnResult(
          detectedLanguageCode: 'es',
          detectedLanguageLabel: 'Spanish',
          translatedText: 'We agree.',
        ),
        TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
          translatedText: 'De acuerdo.',
        ),
      ]);

      await harness.interpreter.handleTextTurn('Hola.');
      await harness.interpreter.handleTextTurn('Hello.');
      final aToB = await harness.interpreter.handleTextTurn(
        'Estamos de acuerdo.',
      );
      final bToA = await harness.interpreter.handleTextTurn('Agreed.');

      expect(aToB.languageCode, 'ES');
      expect(aToB.translatedText, 'We agree.');
      expect(bToA.languageCode, 'EN');
      expect(bToA.translatedText, 'De acuerdo.');
      expect(harness.gateway.requests.last.knownLanguageCodes, ['es', 'en']);
      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(4));
      expect(entries.last.status, 'final');
    },
  );

  test(
    'English Italian pair routes English to Italian fallback and Italian to English realtime text',
    () async {
      final harness = await _Harness.create();
      harness.gateway.results.addAll(const [
        TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
        ),
        TextInterpreterTurnResult(
          detectedLanguageCode: 'it',
          detectedLanguageLabel: 'Italian',
          translatedText: 'We can begin.',
        ),
        TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
          translatedText: 'Possiamo confermare il piano.',
        ),
        TextInterpreterTurnResult(
          detectedLanguageCode: 'en',
          detectedLanguageLabel: 'English',
          translatedText: 'Possiamo confermare il piano.',
        ),
        TextInterpreterTurnResult(
          detectedLanguageCode: 'it',
          detectedLanguageLabel: 'Italian',
          translatedText: 'We can confirm the plan.',
        ),
      ]);

      await harness.interpreter.handleTextTurn('We can begin.');
      final italian = await harness.interpreter.handleTextTurn(
        'Possiamo iniziare.',
      );
      final english = await harness.interpreter.handleTextTurn(
        'We can confirm the plan.',
      );
      final backToEnglish = await harness.interpreter.handleTextTurn(
        'Possiamo confermare il piano.',
      );

      expect(harness.interpreter.routeLabel, 'English <-> Italian');
      expect(italian.languageCode, 'IT');
      expect(italian.translatedText, 'We can begin.');
      expect(english.languageCode, 'EN');
      expect(english.translatedText, 'Possiamo confermare il piano.');
      expect(backToEnglish.languageCode, 'IT');
      expect(backToEnglish.translatedText, 'We can confirm the plan.');

      final backfillDirection = harness.gateway.requests[2];
      expect(backfillDirection.sourceLanguageCode, 'en');
      expect(backfillDirection.targetLanguageCode, 'it');
      expect(
        backfillDirection.routeType,
        TranslationRouteType.directOpenAiFallback,
      );

      final englishDirection = harness.gateway.requests[3];
      expect(englishDirection.sourceLanguageCode, 'en');
      expect(englishDirection.targetLanguageCode, 'it');
      expect(
        englishDirection.routeType,
        TranslationRouteType.directOpenAiFallback,
      );

      final italianDirection = harness.gateway.requests[4];
      expect(italianDirection.sourceLanguageCode, 'it');
      expect(italianDirection.targetLanguageCode, 'en');
      expect(italianDirection.routeType, isNull);

      final entries = (await harness.repository.loadSnapshot())
          .meetings
          .single
          .transcriptEntries;
      expect(entries, hasLength(4));
      expect(entries[2].originalText, 'We can confirm the plan.');
      expect(entries[2].translatedText, 'Possiamo confermare il piano.');
      expect(entries[3].originalText, 'Possiamo confermare il piano.');
      expect(entries[3].translatedText, 'We can confirm the plan.');
    },
  );
}

class _Harness {
  _Harness({
    required this.repository,
    required this.gateway,
    required this.interpreter,
  });

  final LocalMeetingRepository repository;
  final _FakeTextInterpreterGateway gateway;
  final LiveTextInterpreter interpreter;

  static Future<_Harness> create() async {
    final repository = LocalMeetingRepository(
      store: MemoryEncryptedLocalStore(),
    );
    final startedAt = DateTime.utc(2026, 5, 27, 4);
    await repository.upsertMeeting(
      StoredMeeting(
        id: 'meeting-1',
        title: 'Live interpreter',
        createdAt: startedAt,
        updatedAt: startedAt,
        sourceLanguageLabel: 'Auto-detect',
        targetLanguageLabel: 'Auto-detect',
        transcriptEntries: const [],
        summaryMetadata: const StoredSummaryMetadata.empty(),
      ),
    );
    final gateway = _FakeTextInterpreterGateway();
    final interpreter = LiveTextInterpreter(
      repository: repository,
      gateway: gateway,
      meetingId: 'meeting-1',
      credential: 'placeholder-local-openai-credential',
      now: () => startedAt,
    );
    return _Harness(
      repository: repository,
      gateway: gateway,
      interpreter: interpreter,
    );
  }
}

class _FakeTextInterpreterGateway implements TextInterpreterGateway {
  final List<TextInterpreterTurnRequest> requests = [];
  final List<TextInterpreterTurnResult> results = [];

  @override
  Future<TextInterpreterTurnResult> interpretTurn({
    required TextInterpreterTurnRequest request,
    required String credential,
  }) async {
    requests.add(request);
    expect(credential, 'placeholder-local-openai-credential');
    return results.removeAt(0);
  }
}
