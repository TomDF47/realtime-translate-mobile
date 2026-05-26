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

  Future<void> commitDelta(OpenAiRealtimeTranscriptDelta event) {
    return _enqueue(() async {
      if (_isDuplicateFinalItem(event.kind, event.itemId)) {
        return;
      }

      if (_shouldStartNewSegment(event.kind, itemId: event.itemId)) {
        _resetSegment();
      }

      _seedEntryIdFromItemIfNew(event);
      _appendDelta(event);
      await _upsert(status: _statusForCurrentSegment());
      if (_shouldRollReadableBlock()) {
        _readyForNextReadableBlock = true;
      }
    });
  }

  Future<void> commitCompleted(OpenAiRealtimeTranscriptCompleted event) {
    return _enqueue(() {
      if (_isDuplicateCompletion(event)) {
        return Future<void>.value();
      }

      if (_shouldStartNewSegment(
        event.kind,
        isCompletion: true,
        itemId: event.itemId,
      )) {
        _resetSegment();
      }

      _seedEntryIdFromItemIfNew(event);
      _recordItemId(event.kind, event.itemId);
      if (event.transcript != null) {
        _replaceTranscript(event.kind, event.transcript!);
      }
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

  Future<void> finish({required bool interrupted}) {
    return _enqueue(() {
      if (!_hasTranscript || _isFinal) {
        return Future<void>.value();
      }

      _isFinal = true;
      return _upsert(status: interrupted ? 'interrupted' : 'final');
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pendingCommit.then((_) => action());
    _pendingCommit = next.catchError((_) {});
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
  }

  void _appendDelta(OpenAiRealtimeTranscriptDelta event) {
    _timestamp ??= target.now().toUtc();
    _hasTranscript = true;
    switch (event.kind) {
      case OpenAiRealtimeTranscriptKind.source:
        _sourceItemId ??= event.itemId;
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

  Future<void> _upsert({required String status}) {
    if (!_hasTranscript) {
      return Future<void>.value();
    }

    final updatedAt = target.now().toUtc();
    return target.repository.upsertTranscriptEntry(
      meetingId: target.meetingId,
      updatedAt: updatedAt,
      entry: StoredTranscriptEntry(
        id: _entryId,
        meetingId: target.meetingId,
        languageCode: target.targetLanguageCode.toUpperCase(),
        originalText: _sourceBuffer.toString().trim(),
        translatedText: _translationBuffer.toString().trim(),
        timestamp: _timestamp ?? updatedAt,
        speakerLabel: null,
        confidence: null,
        status: status,
        playbackState: 'none',
      ),
    );
  }

  bool _shouldStartNewSegment(
    OpenAiRealtimeTranscriptKind nextKind, {
    bool isCompletion = false,
    String? itemId,
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
      return true;
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

  bool _shouldRollReadableBlock() {
    if (!_hasSourceText || !_hasTranslationText) {
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
    return _isFinal || _translationCompleted ? 'final' : 'partial';
  }

  bool get _hasSourceText => _sourceBuffer.toString().trim().isNotEmpty;

  bool get _hasTranslationText =>
      _translationBuffer.toString().trim().isNotEmpty;

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
