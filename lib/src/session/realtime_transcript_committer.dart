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

  Future<void> commitDelta(OpenAiRealtimeTranscriptDelta event) {
    return _enqueue(() async {
      if (_shouldStartNewSegment(event.kind)) {
        _resetSegment();
      }

      _appendDelta(event);
      await _upsert(status: _statusForCurrentSegment());
      if (_shouldRollReadableBlock()) {
        _readyForNextReadableBlock = true;
      }
    });
  }

  Future<void> commitCompleted(OpenAiRealtimeTranscriptCompleted event) {
    return _enqueue(() {
      if (_shouldStartNewSegment(event.kind, isCompletion: true)) {
        _resetSegment();
      }

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
  }

  void _appendDelta(OpenAiRealtimeTranscriptDelta event) {
    _timestamp ??= target.now().toUtc();
    _hasTranscript = true;
    switch (event.kind) {
      case OpenAiRealtimeTranscriptKind.source:
        _sourceBuffer.write(event.delta);
        _sourceCompleted = false;
      case OpenAiRealtimeTranscriptKind.translation:
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
  }) {
    if (!_hasTranscript) {
      return false;
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

  bool _shouldRollReadableBlock() {
    if (!_hasSourceText || !_hasTranslationText) {
      return false;
    }

    final text = _translationBuffer.toString().trim();
    return _sentenceBoundaryCount(text) >= 2 && _endsAtSentenceBoundary(text);
  }

  String _statusForCurrentSegment() {
    return _isFinal || _translationCompleted ? 'final' : 'partial';
  }

  bool get _hasSourceText => _sourceBuffer.toString().trim().isNotEmpty;

  bool get _hasTranslationText =>
      _translationBuffer.toString().trim().isNotEmpty;
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
