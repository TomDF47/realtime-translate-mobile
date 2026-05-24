class LocalStorageSnapshot {
  const LocalStorageSnapshot({
    required this.schemaVersion,
    required this.meetings,
    required this.recentLanguageRoutes,
    required this.recipientPreferences,
    required this.sensitivePreferences,
    required this.credentialSessionMaterial,
  });

  const LocalStorageSnapshot.empty()
    : schemaVersion = 1,
      meetings = const [],
      recentLanguageRoutes = const [],
      recipientPreferences = const RecipientPreferences.empty(),
      sensitivePreferences = const {},
      credentialSessionMaterial = const {};

  final int schemaVersion;
  final List<StoredMeeting> meetings;
  final List<LanguageRoutePreference> recentLanguageRoutes;
  final RecipientPreferences recipientPreferences;
  final Map<String, String> sensitivePreferences;
  final Map<String, String> credentialSessionMaterial;

  LocalStorageSnapshot copyWith({
    int? schemaVersion,
    List<StoredMeeting>? meetings,
    List<LanguageRoutePreference>? recentLanguageRoutes,
    RecipientPreferences? recipientPreferences,
    Map<String, String>? sensitivePreferences,
    Map<String, String>? credentialSessionMaterial,
  }) {
    return LocalStorageSnapshot(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      meetings: meetings ?? this.meetings,
      recentLanguageRoutes: recentLanguageRoutes ?? this.recentLanguageRoutes,
      recipientPreferences: recipientPreferences ?? this.recipientPreferences,
      sensitivePreferences: sensitivePreferences ?? this.sensitivePreferences,
      credentialSessionMaterial:
          credentialSessionMaterial ?? this.credentialSessionMaterial,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'meetings': [for (final meeting in meetings) meeting.toJson()],
      'recentLanguageRoutes': [
        for (final route in recentLanguageRoutes) route.toJson(),
      ],
      'recipientPreferences': recipientPreferences.toJson(),
      'sensitivePreferences': sensitivePreferences,
      'credentialSessionMaterial': credentialSessionMaterial,
    };
  }

  static LocalStorageSnapshot fromJson(Map<String, Object?> json) {
    return LocalStorageSnapshot(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      meetings: _jsonList(
        json['meetings'],
      ).map(StoredMeeting.fromJson).toList(growable: false),
      recentLanguageRoutes: _jsonList(
        json['recentLanguageRoutes'],
      ).map(LanguageRoutePreference.fromJson).toList(growable: false),
      recipientPreferences: RecipientPreferences.fromJson(
        _jsonMap(json['recipientPreferences']),
      ),
      sensitivePreferences: _stringMap(json['sensitivePreferences']),
      credentialSessionMaterial: _stringMap(json['credentialSessionMaterial']),
    );
  }
}

class StoredMeeting {
  const StoredMeeting({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.sourceLanguageLabel,
    required this.targetLanguageLabel,
    required this.transcriptEntries,
    required this.summaryMetadata,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String sourceLanguageLabel;
  final String targetLanguageLabel;
  final List<StoredTranscriptEntry> transcriptEntries;
  final StoredSummaryMetadata summaryMetadata;

  int get transcriptCount => transcriptEntries.length;

  bool get summaryAvailable => summaryMetadata.available;

  StoredMeeting copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? sourceLanguageLabel,
    String? targetLanguageLabel,
    List<StoredTranscriptEntry>? transcriptEntries,
    StoredSummaryMetadata? summaryMetadata,
  }) {
    return StoredMeeting(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceLanguageLabel: sourceLanguageLabel ?? this.sourceLanguageLabel,
      targetLanguageLabel: targetLanguageLabel ?? this.targetLanguageLabel,
      transcriptEntries: transcriptEntries ?? this.transcriptEntries,
      summaryMetadata: summaryMetadata ?? this.summaryMetadata,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'sourceLanguageLabel': sourceLanguageLabel,
      'targetLanguageLabel': targetLanguageLabel,
      'transcriptEntries': [
        for (final entry in transcriptEntries) entry.toJson(),
      ],
      'summaryMetadata': summaryMetadata.toJson(),
    };
  }

  static StoredMeeting fromJson(Map<String, Object?> json) {
    return StoredMeeting(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled meeting',
      createdAt: _dateTime(json['createdAt']),
      updatedAt: _dateTime(json['updatedAt']),
      sourceLanguageLabel: json['sourceLanguageLabel'] as String? ?? '',
      targetLanguageLabel: json['targetLanguageLabel'] as String? ?? '',
      transcriptEntries: _jsonList(
        json['transcriptEntries'],
      ).map(StoredTranscriptEntry.fromJson).toList(growable: false),
      summaryMetadata: StoredSummaryMetadata.fromJson(
        _jsonMap(json['summaryMetadata']),
      ),
    );
  }
}

class StoredTranscriptEntry {
  const StoredTranscriptEntry({
    required this.id,
    required this.meetingId,
    required this.languageCode,
    required this.originalText,
    required this.translatedText,
    required this.timestamp,
    required this.speakerLabel,
    required this.confidence,
    required this.status,
    required this.playbackState,
  });

  final String id;
  final String meetingId;
  final String languageCode;
  final String originalText;
  final String translatedText;
  final DateTime timestamp;
  final String? speakerLabel;
  final double? confidence;
  final String status;
  final String playbackState;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'meetingId': meetingId,
      'languageCode': languageCode,
      'originalText': originalText,
      'translatedText': translatedText,
      'timestamp': timestamp.toIso8601String(),
      'speakerLabel': speakerLabel,
      'confidence': confidence,
      'status': status,
      'playbackState': playbackState,
    };
  }

  static StoredTranscriptEntry fromJson(Map<String, Object?> json) {
    return StoredTranscriptEntry(
      id: json['id'] as String? ?? '',
      meetingId: json['meetingId'] as String? ?? '',
      languageCode: json['languageCode'] as String? ?? '',
      originalText: json['originalText'] as String? ?? '',
      translatedText: json['translatedText'] as String? ?? '',
      timestamp: _dateTime(json['timestamp']),
      speakerLabel: json['speakerLabel'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'final',
      playbackState: json['playbackState'] as String? ?? 'playable',
    );
  }
}

class StoredSummaryMetadata {
  const StoredSummaryMetadata({
    required this.available,
    required this.updatedAt,
    required this.modelIntent,
    required this.transcriptEntryCount,
  });

  const StoredSummaryMetadata.empty()
    : available = false,
      updatedAt = null,
      modelIntent = null,
      transcriptEntryCount = 0;

  final bool available;
  final DateTime? updatedAt;
  final String? modelIntent;
  final int transcriptEntryCount;

  Map<String, Object?> toJson() {
    return {
      'available': available,
      'updatedAt': updatedAt?.toIso8601String(),
      'modelIntent': modelIntent,
      'transcriptEntryCount': transcriptEntryCount,
    };
  }

  static StoredSummaryMetadata fromJson(Map<String, Object?> json) {
    return StoredSummaryMetadata(
      available: json['available'] as bool? ?? false,
      updatedAt: _nullableDateTime(json['updatedAt']),
      modelIntent: json['modelIntent'] as String?,
      transcriptEntryCount:
          (json['transcriptEntryCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class RecipientPreferences {
  const RecipientPreferences({
    required this.rememberedRecipients,
    required this.lastSelectedRecipients,
  });

  const RecipientPreferences.empty()
    : rememberedRecipients = const [],
      lastSelectedRecipients = const [];

  final List<String> rememberedRecipients;
  final List<String> lastSelectedRecipients;

  Map<String, Object?> toJson() {
    return {
      'rememberedRecipients': rememberedRecipients,
      'lastSelectedRecipients': lastSelectedRecipients,
    };
  }

  static RecipientPreferences fromJson(Map<String, Object?> json) {
    return RecipientPreferences(
      rememberedRecipients: _stringList(json['rememberedRecipients']),
      lastSelectedRecipients: _stringList(json['lastSelectedRecipients']),
    );
  }
}

class LanguageRoutePreference {
  const LanguageRoutePreference({
    required this.sourceLanguageLabel,
    required this.targetLanguageLabel,
    required this.updatedAt,
  });

  final String sourceLanguageLabel;
  final String targetLanguageLabel;
  final DateTime updatedAt;

  Map<String, Object?> toJson() {
    return {
      'sourceLanguageLabel': sourceLanguageLabel,
      'targetLanguageLabel': targetLanguageLabel,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static LanguageRoutePreference fromJson(Map<String, Object?> json) {
    return LanguageRoutePreference(
      sourceLanguageLabel: json['sourceLanguageLabel'] as String? ?? '',
      targetLanguageLabel: json['targetLanguageLabel'] as String? ?? '',
      updatedAt: _dateTime(json['updatedAt']),
    );
  }
}

List<Map<String, Object?>> _jsonList(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }

  return value
      .whereType<Map<Object?, Object?>>()
      .map((item) => item.cast<String, Object?>())
      .toList(growable: false);
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return const {};
  }

  return value.cast<String, Object?>();
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return const {};
  }

  return value.map((key, value) => MapEntry('$key', '$value'));
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }

  return value.map((item) => '$item').toList(growable: false);
}

DateTime _dateTime(Object? value) {
  return _nullableDateTime(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _nullableDateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }

  return DateTime.tryParse(value);
}
