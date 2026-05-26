import 'dart:async';
import 'dart:convert';

import 'encrypted_local_store.dart';
import 'local_storage_models.dart';

class LocalMeetingRepository {
  LocalMeetingRepository({required this.store});

  static const storageKey = 'live_translate_local_storage_v1';

  final EncryptedLocalStore store;
  Future<void> _mutationTail = Future<void>.value();

  bool get isEncryptedAtRest => store.isEncryptedAtRest;

  Future<LocalStorageSnapshot> loadSnapshot() async {
    await _mutationTail;
    return _readSnapshot();
  }

  Future<LocalStorageSnapshot> _readSnapshot() async {
    final raw = await store.read(key: storageKey);
    if (raw == null || raw.isEmpty) {
      return const LocalStorageSnapshot.empty();
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<Object?, Object?>) {
      return const LocalStorageSnapshot.empty();
    }

    return LocalStorageSnapshot.fromJson(decoded.cast<String, Object?>());
  }

  Future<void> saveSnapshot(LocalStorageSnapshot snapshot) {
    return _withMutation(() => _writeSnapshot(snapshot));
  }

  Future<void> _writeSnapshot(LocalStorageSnapshot snapshot) {
    return store.write(key: storageKey, value: jsonEncode(snapshot.toJson()));
  }

  Future<T> _withMutation<T>(Future<T> Function() action) {
    final previous = _mutationTail;
    final next = Completer<void>();
    _mutationTail = next.future;

    return previous.then((_) async {
      try {
        return await action();
      } finally {
        if (!next.isCompleted) {
          next.complete();
        }
      }
    });
  }

  Future<T> _updateSnapshot<T>(
    FutureOr<T> Function(LocalStorageSnapshot snapshot) update,
  ) {
    return _withMutation(() async {
      final snapshot = await _readSnapshot();
      return update(snapshot);
    });
  }

  Future<void> upsertMeeting(StoredMeeting meeting) async {
    await _updateSnapshot((snapshot) async {
      final meetings = [...snapshot.meetings];
      final existingIndex = meetings.indexWhere(
        (item) => item.id == meeting.id,
      );
      if (existingIndex == -1) {
        meetings.add(meeting);
      } else {
        meetings[existingIndex] = meeting;
      }

      meetings.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _writeSnapshot(snapshot.copyWith(meetings: meetings));
    });
  }

  Future<void> appendTranscriptEntry({
    required String meetingId,
    required StoredTranscriptEntry entry,
    required DateTime updatedAt,
  }) async {
    await _updateSnapshot((snapshot) async {
      final meetings = [
        for (final meeting in snapshot.meetings)
          if (meeting.id == meetingId)
            meeting.copyWith(
              updatedAt: updatedAt,
              transcriptEntries: [...meeting.transcriptEntries, entry],
            )
          else
            meeting,
      ];
      meetings.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _writeSnapshot(snapshot.copyWith(meetings: meetings));
    });
  }

  Future<void> touchMeeting({
    required String meetingId,
    required DateTime updatedAt,
  }) async {
    await _updateSnapshot((snapshot) async {
      final meetings = [
        for (final meeting in snapshot.meetings)
          if (meeting.id == meetingId)
            meeting.copyWith(updatedAt: updatedAt)
          else
            meeting,
      ];
      meetings.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _writeSnapshot(snapshot.copyWith(meetings: meetings));
    });
  }

  Future<void> upsertTranscriptEntry({
    required String meetingId,
    required StoredTranscriptEntry entry,
    required DateTime updatedAt,
  }) async {
    await _updateSnapshot((snapshot) async {
      final meetings = [
        for (final meeting in snapshot.meetings)
          if (meeting.id == meetingId)
            meeting.copyWith(
              updatedAt: updatedAt,
              transcriptEntries: _upsertTranscriptEntry(
                meeting.transcriptEntries,
                entry,
              ),
            )
          else
            meeting,
      ];
      meetings.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _writeSnapshot(snapshot.copyWith(meetings: meetings));
    });
  }

  Future<StoredMeeting?> saveMeetingSummary({
    required String meetingId,
    required StoredSummaryMetadata summaryMetadata,
    required DateTime updatedAt,
  }) async {
    return _updateSnapshot((snapshot) async {
      StoredMeeting? updatedMeeting;
      final meetings = [
        for (final meeting in snapshot.meetings)
          if (meeting.id == meetingId)
            updatedMeeting = meeting.copyWith(
              updatedAt: updatedAt,
              summaryMetadata: summaryMetadata,
            )
          else
            meeting,
      ];
      meetings.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _writeSnapshot(snapshot.copyWith(meetings: meetings));
      return updatedMeeting;
    });
  }

  Future<StoredMeeting?> saveGeneratedExport({
    required String meetingId,
    required StoredGeneratedExport generatedExport,
    required DateTime updatedAt,
  }) async {
    return _updateSnapshot((snapshot) async {
      StoredMeeting? updatedMeeting;
      final meetings = [
        for (final meeting in snapshot.meetings)
          if (meeting.id == meetingId)
            updatedMeeting = meeting.copyWith(
              updatedAt: updatedAt,
              generatedExports: [
                generatedExport,
                for (final existing in meeting.generatedExports)
                  if (existing.id != generatedExport.id) existing,
              ],
            )
          else
            meeting,
      ];
      meetings.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _writeSnapshot(snapshot.copyWith(meetings: meetings));
      return updatedMeeting;
    });
  }

  Future<void> deleteMeeting(String meetingId) async {
    await _updateSnapshot((snapshot) {
      return _writeSnapshot(
        snapshot.copyWith(
          meetings: [
            for (final meeting in snapshot.meetings)
              if (meeting.id != meetingId) meeting,
          ],
        ),
      );
    });
  }

  Future<void> clearMeetingHistory() async {
    await _updateSnapshot((snapshot) {
      return _writeSnapshot(snapshot.copyWith(meetings: const []));
    });
  }

  Future<void> saveRecipientPreferences(
    RecipientPreferences preferences,
  ) async {
    await _updateSnapshot((snapshot) {
      return _writeSnapshot(
        snapshot.copyWith(recipientPreferences: preferences),
      );
    });
  }

  Future<void> saveRecentLanguageRoute(LanguageRoutePreference route) async {
    await _updateSnapshot((snapshot) async {
      final routes = [
        route,
        for (final existing in snapshot.recentLanguageRoutes)
          if (existing.sourceLanguageLabel != route.sourceLanguageLabel ||
              existing.targetLanguageLabel != route.targetLanguageLabel)
            existing,
      ].take(8).toList(growable: false);
      await _writeSnapshot(snapshot.copyWith(recentLanguageRoutes: routes));
    });
  }

  Future<void> saveSensitivePreference({
    required String key,
    required String value,
  }) async {
    await _updateSnapshot((snapshot) {
      return _writeSnapshot(
        snapshot.copyWith(
          sensitivePreferences: {...snapshot.sensitivePreferences, key: value},
        ),
      );
    });
  }

  Future<void> saveCredentialSessionMaterial({
    required String key,
    required String value,
  }) async {
    await _updateSnapshot((snapshot) {
      return _writeSnapshot(
        snapshot.copyWith(
          credentialSessionMaterial: {
            ...snapshot.credentialSessionMaterial,
            key: value,
          },
        ),
      );
    });
  }

  Future<Map<String, String>> loadCredentialSessionMaterial() async {
    final snapshot = await loadSnapshot();
    return snapshot.credentialSessionMaterial;
  }

  Future<void> deleteCredentialSessionMaterialKeys(Set<String> keys) async {
    await _updateSnapshot((snapshot) {
      return _writeSnapshot(
        snapshot.copyWith(
          credentialSessionMaterial: {
            for (final entry in snapshot.credentialSessionMaterial.entries)
              if (!keys.contains(entry.key)) entry.key: entry.value,
          },
        ),
      );
    });
  }

  Future<void> deleteAllLocalData() {
    return _withMutation(() => store.delete(key: storageKey));
  }
}

List<StoredTranscriptEntry> _upsertTranscriptEntry(
  List<StoredTranscriptEntry> entries,
  StoredTranscriptEntry entry,
) {
  final updated = [...entries];
  final existingIndex = updated.indexWhere((item) => item.id == entry.id);
  if (existingIndex == -1) {
    updated.add(entry);
  } else {
    updated[existingIndex] = entry;
  }

  return updated;
}
