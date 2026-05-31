import '../language/language_support.dart';
import '../openai/openai_text_interpreter.dart';
import '../storage/local_meeting_repository.dart';
import '../storage/local_storage_models.dart';
import 'bidirectional_interpreter_routing.dart';

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

  final BidirectionalInterpreterRuntime _runtime =
      BidirectionalInterpreterRuntime();
  _PendingFirstTurn? _pendingFirstTurn;
  int _turnSequence = 0;

  List<String> get knownLanguageCodes => _runtime.languageCodes;

  bool get isPairLocked => _runtime.isPairLocked;

  String get routeLabel => _runtime.routeLabel;

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
      request: _turnRequest(text: trimmed),
      credential: credential,
    );
    final code = result.detectedLanguageCode.toLowerCase();
    final discoveredLanguage = _runtime.recordDetectedLanguage(
      code: code,
      label: result.detectedLanguageLabel,
    );
    final discoveredSecondLanguage = discoveredLanguage && isPairLocked;
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

    if (knownLanguageCodes.length == 1 && translatedText.isEmpty) {
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
      request: _turnRequest(
        text: pending.originalText,
        sourceLanguageCode: pending.languageCode,
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

  TextInterpreterTurnRequest _turnRequest({
    required String text,
    String? sourceLanguageCode,
  }) {
    final resolvedSourceLanguageCode =
        sourceLanguageCode ?? detectInterpreterLanguageCode(text);
    final direction = resolvedSourceLanguageCode == null
        ? null
        : _runtime.directionForSource(resolvedSourceLanguageCode);
    final routeType = direction?.routePlan.type;
    return TextInterpreterTurnRequest(
      text: text,
      knownLanguageCodes: knownLanguageCodes,
      sourceLanguageCode: direction?.sourceLanguageCode,
      targetLanguageCode: direction?.targetLanguageCode,
      routeType: routeType == TranslationRouteType.directOpenAiFallback
          ? routeType
          : null,
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
