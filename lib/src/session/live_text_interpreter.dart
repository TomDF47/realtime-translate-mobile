import '../openai/openai_text_interpreter.dart';
import '../storage/local_meeting_repository.dart';
import '../storage/local_storage_models.dart';

class LiveTextInterpreter {
  LiveTextInterpreter({
    required this.repository,
    required this.gateway,
    required this.meetingId,
    required this.credential,
    required this.now,
  });

  final LocalMeetingRepository repository;
  final TextInterpreterGateway gateway;
  final String meetingId;
  final String credential;
  final DateTime Function() now;

  final Map<String, String> _languageLabels = <String, String>{};
  _PendingFirstTurn? _pendingFirstTurn;
  int _turnSequence = 0;

  List<String> get knownLanguageCodes =>
      List.unmodifiable(_languageLabels.keys);

  bool get isPairLocked => _languageLabels.length >= 2;

  String get routeLabel {
    if (_languageLabels.length >= 2) {
      final labels = _languageLabels.values.take(2).toList(growable: false);
      return '${labels[0]} <-> ${labels[1]}';
    }
    if (_languageLabels.length == 1) {
      return 'Heard ${_languageLabels.values.single}. Waiting for the other language...';
    }
    return 'Listening for languages...';
  }

  Future<StoredTranscriptEntry> handleTextTurn(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Text turn must not be empty.');
    }

    final sequence = _turnSequence++;
    final entryId = '$meetingId-text-turn-$sequence';
    final detectedAt = now().toUtc();
    await _upsert(
      entryId: entryId,
      languageCode: 'AUTO',
      originalText: trimmed,
      translatedText: '',
      timestamp: detectedAt,
      status: 'detecting_language',
    );

    final result = await gateway.interpretTurn(
      request: TextInterpreterTurnRequest(
        text: trimmed,
        knownLanguageCodes: knownLanguageCodes,
      ),
      credential: credential,
    );
    final code = result.detectedLanguageCode.toLowerCase();
    final hadLanguage = _languageLabels.containsKey(code);
    _languageLabels.putIfAbsent(code, () => result.detectedLanguageLabel);
    final discoveredSecondLanguage =
        !hadLanguage && _languageLabels.length == 2;
    final translatedText = result.translatedText?.trim() ?? '';
    final status = translatedText.isEmpty ? 'language_detected' : 'translating';
    await _upsert(
      entryId: entryId,
      languageCode: code.toUpperCase(),
      originalText: trimmed,
      translatedText: translatedText,
      timestamp: detectedAt,
      status: status,
    );

    if (_languageLabels.length == 1 && translatedText.isEmpty) {
      _pendingFirstTurn = _PendingFirstTurn(
        entryId: entryId,
        languageCode: code,
        originalText: trimmed,
        timestamp: detectedAt,
      );
    }

    final finalEntry = StoredTranscriptEntry(
      id: entryId,
      meetingId: meetingId,
      languageCode: code.toUpperCase(),
      originalText: trimmed,
      translatedText: translatedText,
      timestamp: detectedAt,
      speakerLabel: null,
      confidence: null,
      status: translatedText.isEmpty ? 'language_detected' : 'final',
      playbackState: 'none',
    );
    await repository.upsertTranscriptEntry(
      meetingId: meetingId,
      updatedAt: now().toUtc(),
      entry: finalEntry,
    );
    if (discoveredSecondLanguage) {
      await _backfillPendingFirstTurn();
    }
    return finalEntry;
  }

  Future<void> _backfillPendingFirstTurn() async {
    final pending = _pendingFirstTurn;
    if (pending == null || !isPairLocked) {
      return;
    }

    _pendingFirstTurn = null;
    await _upsert(
      entryId: pending.entryId,
      languageCode: pending.languageCode.toUpperCase(),
      originalText: pending.originalText,
      translatedText: '',
      timestamp: pending.timestamp,
      status: 'translating_delayed',
    );

    final result = await gateway.interpretTurn(
      request: TextInterpreterTurnRequest(
        text: pending.originalText,
        knownLanguageCodes: knownLanguageCodes,
      ),
      credential: credential,
    );
    final translatedText = result.translatedText?.trim() ?? '';
    if (translatedText.isEmpty) {
      _pendingFirstTurn = pending;
      await _upsert(
        entryId: pending.entryId,
        languageCode: pending.languageCode.toUpperCase(),
        originalText: pending.originalText,
        translatedText: '',
        timestamp: pending.timestamp,
        status: 'language_detected',
      );
      return;
    }

    await _upsert(
      entryId: pending.entryId,
      languageCode: pending.languageCode.toUpperCase(),
      originalText: pending.originalText,
      translatedText: translatedText,
      timestamp: pending.timestamp,
      status: 'delayed_translation',
    );
  }

  Future<void> _upsert({
    required String entryId,
    required String languageCode,
    required String originalText,
    required String translatedText,
    required DateTime timestamp,
    required String status,
  }) {
    return repository.upsertTranscriptEntry(
      meetingId: meetingId,
      updatedAt: now().toUtc(),
      entry: StoredTranscriptEntry(
        id: entryId,
        meetingId: meetingId,
        languageCode: languageCode,
        originalText: originalText,
        translatedText: translatedText,
        timestamp: timestamp,
        speakerLabel: null,
        confidence: null,
        status: status,
        playbackState: 'none',
      ),
    );
  }
}

class _PendingFirstTurn {
  const _PendingFirstTurn({
    required this.entryId,
    required this.languageCode,
    required this.originalText,
    required this.timestamp,
  });

  final String entryId;
  final String languageCode;
  final String originalText;
  final DateTime timestamp;
}
