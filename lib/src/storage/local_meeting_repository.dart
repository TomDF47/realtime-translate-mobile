import 'dart:convert';

import 'encrypted_local_store.dart';
import 'local_storage_models.dart';

class LocalMeetingRepository {
  LocalMeetingRepository({required this.store});

  static const storageKey = 'live_translate_local_storage_v1';

  final EncryptedLocalStore store;

  bool get isEncryptedAtRest => store.isEncryptedAtRest;

  Future<LocalStorageSnapshot> loadSnapshot() async {
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
    return store.write(key: storageKey, value: jsonEncode(snapshot.toJson()));
  }

  Future<void> upsertMeeting(StoredMeeting meeting) async {
    final snapshot = await loadSnapshot();
    final meetings = [...snapshot.meetings];
    final existingIndex = meetings.indexWhere((item) => item.id == meeting.id);
    if (existingIndex == -1) {
      meetings.add(meeting);
    } else {
      meetings[existingIndex] = meeting;
    }

    meetings.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await saveSnapshot(snapshot.copyWith(meetings: meetings));
  }

  Future<void> appendTranscriptEntry({
    required String meetingId,
    required StoredTranscriptEntry entry,
    required DateTime updatedAt,
  }) async {
    final snapshot = await loadSnapshot();
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
    await saveSnapshot(snapshot.copyWith(meetings: meetings));
  }

  Future<void> deleteMeeting(String meetingId) async {
    final snapshot = await loadSnapshot();
    await saveSnapshot(
      snapshot.copyWith(
        meetings: [
          for (final meeting in snapshot.meetings)
            if (meeting.id != meetingId) meeting,
        ],
      ),
    );
  }

  Future<void> clearMeetingHistory() async {
    final snapshot = await loadSnapshot();
    await saveSnapshot(snapshot.copyWith(meetings: const []));
  }

  Future<void> saveRecipientPreferences(
    RecipientPreferences preferences,
  ) async {
    final snapshot = await loadSnapshot();
    await saveSnapshot(snapshot.copyWith(recipientPreferences: preferences));
  }

  Future<void> saveRecentLanguageRoute(LanguageRoutePreference route) async {
    final snapshot = await loadSnapshot();
    final routes = [
      route,
      for (final existing in snapshot.recentLanguageRoutes)
        if (existing.sourceLanguageLabel != route.sourceLanguageLabel ||
            existing.targetLanguageLabel != route.targetLanguageLabel)
          existing,
    ].take(8).toList(growable: false);
    await saveSnapshot(snapshot.copyWith(recentLanguageRoutes: routes));
  }

  Future<void> saveSensitivePreference({
    required String key,
    required String value,
  }) async {
    final snapshot = await loadSnapshot();
    await saveSnapshot(
      snapshot.copyWith(
        sensitivePreferences: {...snapshot.sensitivePreferences, key: value},
      ),
    );
  }

  Future<void> saveCredentialSessionMaterial({
    required String key,
    required String value,
  }) async {
    final snapshot = await loadSnapshot();
    await saveSnapshot(
      snapshot.copyWith(
        credentialSessionMaterial: {
          ...snapshot.credentialSessionMaterial,
          key: value,
        },
      ),
    );
  }

  Future<Map<String, String>> loadCredentialSessionMaterial() async {
    final snapshot = await loadSnapshot();
    return snapshot.credentialSessionMaterial;
  }

  Future<void> deleteCredentialSessionMaterialKeys(Set<String> keys) async {
    final snapshot = await loadSnapshot();
    await saveSnapshot(
      snapshot.copyWith(
        credentialSessionMaterial: {
          for (final entry in snapshot.credentialSessionMaterial.entries)
            if (!keys.contains(entry.key)) entry.key: entry.value,
        },
      ),
    );
  }

  Future<void> deleteAllLocalData() {
    return store.delete(key: storageKey);
  }
}
