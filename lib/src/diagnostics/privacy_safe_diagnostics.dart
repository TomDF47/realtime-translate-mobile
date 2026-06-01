enum DiagnosticSeverity { info, warning, error }

class PrivacySafeDiagnosticRecord {
  const PrivacySafeDiagnosticRecord({
    required this.event,
    required this.severity,
    required this.fields,
  });

  final String event;
  final DiagnosticSeverity severity;
  final Map<String, String> fields;
}

abstract interface class PrivacySafeDiagnosticsSink {
  void record(PrivacySafeDiagnosticRecord record);
}

class MemoryPrivacySafeDiagnosticsSink implements PrivacySafeDiagnosticsSink {
  final List<PrivacySafeDiagnosticRecord> records = [];

  @override
  void record(PrivacySafeDiagnosticRecord record) {
    records.add(record);
  }
}

class PrivacySafeDiagnostics {
  const PrivacySafeDiagnostics({
    this.sink = const _NoopPrivacySafeDiagnosticsSink(),
  });

  static const redacted = '[redacted]';
  static const omitted = '[omitted]';

  static const _allowedFieldKeys = {
    'appLifecycleState',
    'audioRoute',
    'backoffMs',
    'configured',
    'credentialStatus',
    'endpoint',
    'errorCode',
    'exportType',
    'fallbackModel',
    // Presence-only realtime transcript signal counters. These never carry
    // transcript/translation content; they only expose whether the dedicated
    // translation wire actually delivered source (original) vs output
    // (translated) transcript turns, so a release check can detect the
    // "translation arrived but original source never did" failure mode.
    'hasOutputSignal',
    'hasSourceSignal',
    'isMicrophoneCaptureOpen',
    'isPlaybackQueueOpen',
    'isRealtimeSessionOpen',
    'model',
    'nextPhase',
    'operation',
    'outputTurnCount',
    'permissionName',
    'permissionStatus',
    'previousPhase',
    'reasoningEffort',
    'realtimeProfile',
    'resource',
    'result',
    'retryAttempt',
    'scope',
    'signalState',
    'sourcelessFinalCount',
    'sourceTurnCount',
    'storageArea',
    'summaryModel',
    'targetLanguage',
  };

  static const _forbiddenKeyFragments = {
    'apikey',
    'audio',
    'authorization',
    'bearer',
    'body',
    'content',
    'cookie',
    'email',
    'exportpayload',
    'meetingid',
    'payload',
    'prompt',
    'raw',
    'recipient',
    'requestbody',
    'responsebody',
    'secret',
    'sessionid',
    'summary',
    'text',
    'token',
    'transcript',
    'translated',
    'translation',
  };

  static final RegExp _unsafeValuePattern = RegExp(
    r'(sk-(?:proj-)?[A-Za-z0-9_-]{20,}|'
    r'ek_[A-Za-z0-9_-]{20,}|'
    r'sess-[A-Za-z0-9_-]{20,}|'
    r'Bearer\s+[A-Za-z0-9._-]{10,}|'
    r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})',
    caseSensitive: false,
  );

  final PrivacySafeDiagnosticsSink sink;

  void info(String event, {Map<String, Object?> fields = const {}}) {
    record(event, severity: DiagnosticSeverity.info, fields: fields);
  }

  void warning(String event, {Map<String, Object?> fields = const {}}) {
    record(event, severity: DiagnosticSeverity.warning, fields: fields);
  }

  void error(String event, {Map<String, Object?> fields = const {}}) {
    record(event, severity: DiagnosticSeverity.error, fields: fields);
  }

  void record(
    String event, {
    required DiagnosticSeverity severity,
    Map<String, Object?> fields = const {},
  }) {
    sink.record(
      PrivacySafeDiagnosticRecord(
        event: sanitizeEventName(event),
        severity: severity,
        fields: sanitizeFields(fields),
      ),
    );
  }

  static String sanitizeEventName(String event) {
    if (containsUnsafeValue(event)) {
      return 'diagnostic_event';
    }

    final sanitized = event.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9_.:-]+'),
      '_',
    );
    if (sanitized.isEmpty) {
      return 'diagnostic_event';
    }

    if (sanitized.length > 64) {
      return sanitized.substring(0, 64);
    }

    return sanitized;
  }

  static Map<String, String> sanitizeFields(Map<String, Object?> fields) {
    return {
      for (final entry in fields.entries)
        entry.key: sanitizeFieldValue(entry.key, entry.value),
    };
  }

  static String sanitizeFieldValue(String key, Object? value) {
    if (!_allowedFieldKeys.contains(key)) {
      return _isForbiddenKey(key) ? redacted : omitted;
    }

    if (value == null) {
      return 'null';
    }

    if (value is bool || value is num || value is Enum) {
      return value.toString();
    }

    if (value is Iterable || value is Map) {
      return omitted;
    }

    final text = value.toString().trim();
    if (text.isEmpty) {
      return 'empty';
    }

    if (containsUnsafeValue(text)) {
      return redacted;
    }

    if (text.length > 96) {
      return omitted;
    }

    return text;
  }

  static bool containsUnsafeValue(String value) {
    return _unsafeValuePattern.hasMatch(value);
  }

  static bool _isForbiddenKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _forbiddenKeyFragments.any(normalized.contains);
  }
}

class _NoopPrivacySafeDiagnosticsSink implements PrivacySafeDiagnosticsSink {
  const _NoopPrivacySafeDiagnosticsSink();

  @override
  void record(PrivacySafeDiagnosticRecord record) {}
}
