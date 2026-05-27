import 'package:flutter_test/flutter_test.dart';
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
      ),
    );
    final serialized = body.toString();

    expect(body['store'], isFalse);
    expect(serialized, contains('known_language_codes'));
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
