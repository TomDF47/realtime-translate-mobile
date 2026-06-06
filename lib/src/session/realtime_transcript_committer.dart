import '../language/local_language_detector.dart';
import '../openai/openai_realtime_translation.dart';
import '../storage/local_meeting_repository.dart';
import '../storage/local_storage_models.dart';

class LiveRealtimeTranscriptCommitTarget {
  const LiveRealtimeTranscriptCommitTarget({
    required this.repository,
    required this.meetingId,
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    required this.now,
  });

  final LocalMeetingRepository repository;
  final String meetingId;
  final String sourceLanguageCode;
  final String targetLanguageCode;
  final DateTime Function() now;
}

class LiveRealtimeTranscriptCommitter {
  LiveRealtimeTranscriptCommitter(this.target)
    : _entryId = _newEntryId(target, 0);

  final LiveRealtimeTranscriptCommitTarget target;
  String _entryId;
  final StringBuffer _sourceBuffer = StringBuffer();
  final StringBuffer _translationBuffer = StringBuffer();
  DateTime? _timestamp;
  Future<void> _pendingCommit = Future<void>.value();
  int _entrySequence = 1;
  bool _hasTranscript = false;
  bool _isFinal = false;
  bool _sourceCompleted = false;
  bool _translationCompleted = false;
  bool _readyForNextReadableBlock = false;
  String? _sourceItemId;
  String? _translationItemId;
  String? _detectedSourceLanguageCode;

  String? get currentEntryId => _hasTranscript ? _entryId : null;

  String entryIdForRealtimeItem(String itemId) {
    return _newEntryIdForRealtimeItem(target, itemId);
  }

  Future<StoredTranscriptEntry?> commitDelta(
    OpenAiRealtimeTranscriptDelta event, {
    bool forceNewSegment = false,
  }) {
    return _enqueue(() async {
      if (forceNewSegment && _hasTranscript) {
        _resetSegment();
      }
      if (_isDuplicateFinalItem(event.kind, event.itemId)) {
        return null;
      }

      final nextLanguageCode = event.kind == OpenAiRealtimeTranscriptKind.source
          ? event.languageCode ?? _detectLanguageCode(event.delta)
          : event.languageCode;
      if (_shouldStartNewSegment(
        event.kind,
        itemId: event.itemId,
        languageCode: nextLanguageCode,
      )) {
        _resetSegment();
      }

      _seedEntryIdFromItemIfNew(event);
      _appendDelta(event);
      _recordDetectedLanguage(event);
      final entry = await _upsert(status: _statusForCurrentSegment());
      if (_shouldRollReadableBlock()) {
        _readyForNextReadableBlock = true;
      }
      return entry;
    });
  }

  Future<StoredTranscriptEntry?> commitCompleted(
    OpenAiRealtimeTranscriptCompleted event, {
    bool forceNewSegment = false,
  }) {
    return _enqueue(() async {
      if (forceNewSegment && _hasTranscript) {
        _resetSegment();
      }
      if (_isDuplicateCompletion(event)) {
        return null;
      }

      final isSourceCompletion =
          event.kind == OpenAiRealtimeTranscriptKind.source &&
              event.transcript != null;
      final effectiveTranscript = isSourceCompletion
          ? _sourceCompletionSuffixAfterCurrent(event.transcript!)
          : event.transcript;
      final nextLanguageCode = event.kind == OpenAiRealtimeTranscriptKind.source
          ? event.languageCode ??
                (effectiveTranscript == null
                    ? null
                    : _detectLanguageCode(effectiveTranscript))
          : event.languageCode;
      if (_shouldStartNewSegment(
        event.kind,
        isCompletion: true,
        itemId: event.itemId,
        languageCode: nextLanguageCode,
        transcript: effectiveTranscript,
      )) {
        _resetSegment();
      }

      _seedEntryIdFromItemIfNew(event);
      _recordItemId(event.kind, event.itemId);
      if (effectiveTranscript != null) {
        _replaceTranscript(event.kind, effectiveTranscript);
      }
      _recordDetectedLanguage(event);
      _markCompleted(event.kind);

      if (_translationCompleted && _hasSourceText) {
        _isFinal = true;
      }
      if (_shouldRollReadableBlock()) {
        _readyForNextReadableBlock = true;
      }

      return _upsert(status: _statusForCurrentSegment());
    });
  }

  Future<StoredTranscriptEntry?> finish({required bool interrupted}) {
    return _enqueue(() {
      if (!_hasTranscript || _isFinal) {
        return Future<StoredTranscriptEntry?>.value();
      }

      if (!_hasSourceText) {
        return _upsert(status: interrupted ? 'interrupted' : 'partial');
      }

      _isFinal = true;
      return _upsert(status: interrupted ? 'interrupted' : 'final');
    });
  }

  Future<StoredTranscriptEntry?> _enqueue(
    Future<StoredTranscriptEntry?> Function() action,
  ) {
    final next = _pendingCommit.then((_) => action());
    _pendingCommit = next.then<void>((_) {}).catchError((_) {});
    return next;
  }

  void _resetSegment() {
    _entryId = _newEntryId(target, _entrySequence);
    _entrySequence += 1;
    _sourceBuffer.clear();
    _translationBuffer.clear();
    _timestamp = null;
    _hasTranscript = false;
    _isFinal = false;
    _sourceCompleted = false;
    _translationCompleted = false;
    _readyForNextReadableBlock = false;
    _sourceItemId = null;
    _translationItemId = null;
    _detectedSourceLanguageCode = null;
  }

  void _appendDelta(OpenAiRealtimeTranscriptDelta event) {
    _timestamp ??= target.now().toUtc();
    _hasTranscript = true;
    switch (event.kind) {
      case OpenAiRealtimeTranscriptKind.source:
        _sourceItemId ??= event.itemId;
        _detectedSourceLanguageCode ??= event.languageCode;
        _sourceBuffer.write(event.delta);
        _sourceCompleted = false;
      case OpenAiRealtimeTranscriptKind.translation:
        _translationItemId ??= event.itemId;
        _translationBuffer.write(event.delta);
        _translationCompleted = false;
    }
  }

  void _replaceTranscript(
    OpenAiRealtimeTranscriptKind kind,
    String transcript,
  ) {
    _timestamp ??= target.now().toUtc();
    _hasTranscript = true;
    switch (kind) {
      case OpenAiRealtimeTranscriptKind.source:
        if (_isCumulativeSourceCompletion(transcript)) {
          return;
        }
        _sourceBuffer
          ..clear()
          ..write(transcript);
      case OpenAiRealtimeTranscriptKind.translation:
        _translationBuffer
          ..clear()
          ..write(transcript);
    }
  }

  void _markCompleted(OpenAiRealtimeTranscriptKind kind) {
    switch (kind) {
      case OpenAiRealtimeTranscriptKind.source:
        _sourceCompleted = true;
      case OpenAiRealtimeTranscriptKind.translation:
        _translationCompleted = true;
    }
  }

  void _recordItemId(OpenAiRealtimeTranscriptKind kind, String? itemId) {
    if (itemId == null || itemId.isEmpty) {
      return;
    }

    switch (kind) {
      case OpenAiRealtimeTranscriptKind.source:
        _sourceItemId ??= itemId;
      case OpenAiRealtimeTranscriptKind.translation:
        _translationItemId ??= itemId;
    }
  }

  Future<StoredTranscriptEntry?> _upsert({required String status}) async {
    if (!_hasTranscript) {
      return null;
    }

    final updatedAt = target.now().toUtc();
    final resolvedSourceLanguage = _resolveSourceLanguageCode();
    final entry = StoredTranscriptEntry(
      id: _entryId,
      meetingId: target.meetingId,
      // Never default an unknown source language to the target language. If the
      // route has an explicit manual source, use that as the last resort;
      // auto-detect sessions stay neutral ('auto') until metadata or local
      // detection resolves the source.
      languageCode: (resolvedSourceLanguage == null ||
              resolvedSourceLanguage.isEmpty)
          ? 'auto'
          : resolvedSourceLanguage.toUpperCase(),
      originalText: _sourceBuffer.toString().trim(),
      translatedText: _translationBuffer.toString().trim(),
      timestamp: _timestamp ?? updatedAt,
      speakerLabel: null,
      confidence: null,
      status: status,
      playbackState: 'none',
    );
    await target.repository.upsertTranscriptEntry(
      meetingId: target.meetingId,
      updatedAt: updatedAt,
      entry: entry,
    );
    return entry;
  }

  bool _shouldStartNewSegment(
    OpenAiRealtimeTranscriptKind nextKind, {
    bool isCompletion = false,
    String? itemId,
    String? languageCode,
    String? transcript,
  }) {
    if (!_hasTranscript) {
      return false;
    }

    if (itemId != null &&
        nextKind == OpenAiRealtimeTranscriptKind.source &&
        _sourceItemId != null &&
        _sourceItemId != itemId) {
      return true;
    }

    if (nextKind == OpenAiRealtimeTranscriptKind.source &&
        languageCode != null &&
        languageCode.isNotEmpty &&
        _detectedSourceLanguageCode != null &&
        _detectedSourceLanguageCode != languageCode) {
      return true;
    }

    // New source utterance on the dedicated translation path, which sends no
    // item ids: once the current block's source has completed, any further
    // incoming source content belongs to a new turn. This is the reliable
    // block boundary when the previous turn never received a realtime
    // translation (for example an English->Italian direct fallback turn whose
    // translated text is written separately), so a later turn's source and
    // translation no longer merge into the prior source-only block. An
    // identical re-sent source completion (a duplicate/refinement of the
    // current turn rather than a new utterance) is excluded so a repeated
    // event does not over-split.
    if (nextKind == OpenAiRealtimeTranscriptKind.source &&
        _sourceCompleted &&
        !_isRepeatedCurrentSourceTranscript(transcript)) {
      return true;
    }

    if (_isFinal) {
      if (isCompletion &&
          ((nextKind == OpenAiRealtimeTranscriptKind.source &&
                  !_sourceCompleted) ||
              (nextKind == OpenAiRealtimeTranscriptKind.translation &&
                  !_translationCompleted))) {
        return false;
      }
      return true;
    }

    if (!_readyForNextReadableBlock) {
      return false;
    }

    if (nextKind == OpenAiRealtimeTranscriptKind.translation) {
      // Never roll a readable block on a translation event on this wire.
      //
      // On the dedicated `/v1/realtime/translations` wire (no item ids, no
      // language metadata) the source and target transcripts stream on
      // independent cadences. Once a turn's source has completed, the readable
      // roll can arm while that turn's translation is still streaming. A later
      // translation delta/done for the SAME turn then has no new source to
      // distinguish it from a new turn, so rolling here would reset the
      // segment and orphan the translation tail onto a fresh, source-less card
      // ("Original speech pending" / "--") — exactly the round-3 failure.
      //
      // The completed source utterance is the only reliable turn boundary, and
      // a genuinely new source utterance after completion already starts a new
      // card via the new-source rule above. So a continued translation always
      // stays on the current card; its original is preserved and the full
      // translation is appended.
      return false;
    }

    return _sourceCompleted;
  }

  void _seedEntryIdFromItemIfNew(OpenAiRealtimeEvent event) {
    final itemId = switch (event) {
      OpenAiRealtimeTranscriptDelta(:final itemId) => itemId,
      OpenAiRealtimeTranscriptCompleted(:final itemId) => itemId,
      _ => null,
    };
    if (_hasTranscript || itemId == null || itemId.isEmpty) {
      return;
    }

    _entryId = _newEntryIdForRealtimeItem(target, itemId);
  }

  void _recordDetectedLanguage(OpenAiRealtimeEvent event) {
    final OpenAiRealtimeTranscriptKind? kind;
    final String? languageCode;
    switch (event) {
      case OpenAiRealtimeTranscriptDelta():
        kind = event.kind;
        languageCode = event.languageCode;
      case OpenAiRealtimeTranscriptCompleted():
        kind = event.kind;
        languageCode = event.languageCode;
      default:
        kind = null;
        languageCode = null;
    }
    if (kind != OpenAiRealtimeTranscriptKind.source) {
      return;
    }

    final resolvedLanguageCode =
        languageCode ?? _detectLanguageCode(_sourceBuffer.toString());
    if (resolvedLanguageCode == null || resolvedLanguageCode.isEmpty) {
      return;
    }
    _detectedSourceLanguageCode ??= resolvedLanguageCode;
  }

  /// Resolves the source language for the current block without defaulting to
  /// the target language.
  ///
  /// The dedicated `/v1/realtime/translations` endpoint sends no language
  /// metadata, so this resolves from, in order: an explicitly recorded source
  /// language and deterministic detection over the source transcript text. It
  /// returns `null` when the source language is genuinely unknown so callers
  /// can render a neutral label instead of mislabeling the source as the
  /// target language.
  String? _resolveSourceLanguageCode() {
    return _detectedSourceLanguageCode ??
        _detectLanguageCode(_sourceBuffer.toString()) ??
        _manualSourceLanguageCode();
  }

  String? _manualSourceLanguageCode() {
    final normalized = target.sourceLanguageCode.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'auto') {
      return null;
    }

    return normalized;
  }

  bool _shouldRollReadableBlock() {
    if (!_hasSourceText || !_hasTranslationText) {
      return false;
    }

    // The dedicated `/v1/realtime/translations` wire sends no item ids and no
    // language metadata, so the completed source utterance is the only
    // reliable turn boundary. A single continuous utterance streams its source
    // and target transcripts on independent cadences, and the translation side
    // frequently crosses sentence boundaries (or grows long) while the same
    // source utterance is still being transcribed. Rolling on the translation
    // alone there splits one still-open turn: the next translation delta opens
    // a fresh card whose original stays empty ("Original speech pending"),
    // which is exactly Tom's 2026-06-01 installed-app screenshot. Only treat a
    // readable block as complete once this turn's source has finished, so a
    // mid-utterance translation never orphans itself onto a sourceless card.
    if (!_sourceCompleted) {
      return false;
    }

    final sourceText = _sourceBuffer.toString().trim();
    final translatedText = _translationBuffer.toString().trim();
    if (sourceText.length >= _readableBlockCharacterThreshold ||
        translatedText.length >= _readableBlockCharacterThreshold) {
      return true;
    }

    return _sentenceBoundaryCount(translatedText) >= 1 &&
        _endsAtSentenceBoundary(translatedText);
  }

  String _statusForCurrentSegment() {
    return _isFinal || (_translationCompleted && _hasSourceText)
        ? 'final'
        : 'partial';
  }

  bool get _hasSourceText => _sourceBuffer.toString().trim().isNotEmpty;

  bool get _hasTranslationText =>
      _translationBuffer.toString().trim().isNotEmpty;

  bool _isRepeatedCurrentSourceTranscript(String? transcript) {
    final candidate = transcript?.trim();
    if (candidate == null || candidate.isEmpty) {
      return false;
    }

    return _sourceBuffer.toString().trim() == candidate;
  }

  String? _sourceCompletionSuffixAfterCurrent(String transcript) {
    if (!_hasTranscript || !_sourceCompleted) {
      return transcript;
    }

    final current = _sourceBuffer.toString().trim();
    final candidate = transcript.trim();
    if (current.isEmpty || candidate.isEmpty || candidate == current) {
      return transcript;
    }
    if (!candidate.startsWith(current)) {
      return transcript;
    }

    final suffix = candidate.substring(current.length).trimLeft();
    return suffix.isEmpty ? transcript : suffix;
  }

  bool _isCumulativeSourceCompletion(String transcript) {
    final current = _sourceBuffer.toString().trim();
    final candidate = transcript.trim();
    return _entrySequence > 1 &&
        current.length >= _minimumCumulativeCompletionCurrentLength &&
        candidate != current &&
        candidate.contains(current);
  }

  bool _isDuplicateCompletion(OpenAiRealtimeTranscriptCompleted event) {
    final transcript = event.transcript?.trim();
    if (!_isFinal || transcript == null || transcript.isEmpty) {
      return false;
    }

    return switch (event.kind) {
      OpenAiRealtimeTranscriptKind.source =>
        _sourceCompleted && _sourceBuffer.toString().trim() == transcript,
      OpenAiRealtimeTranscriptKind.translation =>
        _translationCompleted &&
            _translationBuffer.toString().trim() == transcript,
    };
  }

  bool _isDuplicateFinalItem(
    OpenAiRealtimeTranscriptKind kind,
    String? itemId,
  ) {
    if (!_isFinal || itemId == null || itemId.isEmpty) {
      return false;
    }

    return switch (kind) {
      OpenAiRealtimeTranscriptKind.source => _sourceItemId == itemId,
      OpenAiRealtimeTranscriptKind.translation => _translationItemId == itemId,
    };
  }
}

const _readableBlockCharacterThreshold = 180;
const _minimumCumulativeCompletionCurrentLength = 12;

String? _detectLanguageCode(String text) {
  return detectLocalLanguageCode(text) ?? _legacyDetectLanguageCode(text);
}

String? _legacyDetectLanguageCode(String text) {
  final normalized = text.toLowerCase();
  if (normalized.trim().isEmpty) {
    return null;
  }

  final scores = <String, int>{
    for (final language in _languageMarkers.entries)
      language.key: _languageScore(normalized, language.value),
  };

  var bestCode = '';
  var bestScore = 0;
  var tiedBestScore = false;
  for (final entry in scores.entries) {
    if (entry.value > bestScore) {
      bestCode = entry.key;
      bestScore = entry.value;
      tiedBestScore = false;
    } else if (entry.value == bestScore && entry.value > 0) {
      tiedBestScore = true;
    }
  }

  if (tiedBestScore || bestScore <= 0) {
    return null;
  }

  // A single distinctive non-English marker (for example "buongiorno", "ciao",
  // "hola", "bonjour") is enough to resolve a short foreign phrase, as long as
  // English scored nothing. English short phrases still need the higher
  // threshold because its markers are common function words that can appear
  // incidentally in other languages. The relaxed threshold also requires the
  // best language to have matched a marker that is not an English homograph
  // (for example Italian "come"), so an English-only phrase such as
  // "Let me come in." does not resolve to a foreign language at score 1.
  final englishScore = scores['en'] ?? 0;
  final hasDistinctiveMarker =
      bestCode != 'en' && _languageScore(normalized, _distinctiveMarkers(bestCode)) > 0;
  final minimumScore =
      (bestCode != 'en' && englishScore == 0 && hasDistinctiveMarker)
      ? _minimumDistinctiveLanguageScore
      : _minimumLocalLanguageScore;

  return bestScore < minimumScore ? null : bestCode;
}

const _minimumLocalLanguageScore = 2;
const _minimumDistinctiveLanguageScore = 1;

// Single source of truth for the deterministic local language markers. English
// markers are common function words, so English never uses the relaxed
// single-marker threshold (see `_detectLanguageCode`).
const _languageMarkers = <String, List<String>>{
  'en': [
    'the',
    'and',
    'you',
    'what',
    'going',
    'hello',
    'thank',
    'thanks',
    'meeting',
    'timeline',
    'please',
  ],
  'it': [
    'ciao',
    'grazie',
    'buongiorno',
    'buonasera',
    'allora',
    'cosa',
    'perche',
    'perchè',
    'sono',
    'siamo',
    'mi',
    'piace',
    'calcio',
    'buono',
    'buona',
    'questo',
    'questa',
    'quello',
    'quella',
    'parlo',
    'italiano',
    'come',
    'stai',
    'sta',
    'bene',
    'tutti',
    'tutto',
    'sei',
    'molto',
    'anche',
  ],
  'es': [
    'hola',
    'gracias',
    'buenos',
    'dias',
    'estas',
    'esta',
    'que',
    'por',
    'favor',
    'hablo',
    'espanol',
    'español',
  ],
  'fr': [
    'bonjour',
    'merci',
    'salut',
    'avec',
    'pourquoi',
    'parle',
    'francais',
    'français',
    'nous',
    'vous',
    'etre',
    'être',
  ],
};

// Markers that are also common English words. They count toward the higher
// multi-marker threshold but are excluded from single-marker eligibility so an
// English-only phrase (for example "Let me come in.") cannot resolve to a
// foreign language at score 1.
const _englishHomographMarkers = <String>{'come'};

// Markers for [code] that are eligible to resolve the language from a single
// hit, i.e. its full marker list minus any English homographs.
List<String> _distinctiveMarkers(String code) {
  final markers = _languageMarkers[code] ?? const <String>[];
  return markers
      .where((marker) => !_englishHomographMarkers.contains(marker))
      .toList(growable: false);
}

int _languageScore(String text, List<String> markers) {
  var score = 0;
  for (final marker in markers) {
    if (RegExp(
      '(^|[^a-zà-ÿ])${RegExp.escape(marker)}([^a-zà-ÿ]|\$)',
      unicode: true,
    ).hasMatch(text)) {
      score += 1;
    }
  }
  return score;
}

bool _endsAtSentenceBoundary(String text) {
  if (text.isEmpty) {
    return false;
  }

  final trimmed = text.trimRight();
  return trimmed.endsWith('.') ||
      trimmed.endsWith('?') ||
      trimmed.endsWith('!') ||
      trimmed.endsWith('。') ||
      trimmed.endsWith('？') ||
      trimmed.endsWith('！');
}

int _sentenceBoundaryCount(String text) {
  return RegExp(r'[.!?。？！](?:\s|$)').allMatches(text).length;
}

String _newEntryId(LiveRealtimeTranscriptCommitTarget target, int sequence) {
  return '${target.meetingId}-realtime-'
      '${target.now().microsecondsSinceEpoch}-$sequence';
}

String _newEntryIdForRealtimeItem(
  LiveRealtimeTranscriptCommitTarget target,
  String itemId,
) {
  final safeItemId = itemId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-');
  return '${target.meetingId}-realtime-item-$safeItemId';
}
