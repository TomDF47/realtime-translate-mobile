import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';
import 'package:realtime_translate_mobile/src/storage/local_storage_models.dart';

void main() {
  test('persists meetings and transcript history in encrypted store', () async {
    final store = MemoryEncryptedLocalStore();
    final repository = LocalMeetingRepository(store: store);
    final createdAt = DateTime.utc(2026, 5, 24, 1);
    final updatedAt = DateTime.utc(2026, 5, 24, 2);

    final meeting = StoredMeeting(
      id: 'meeting-1',
      title: 'Project timeline review',
      createdAt: createdAt,
      updatedAt: createdAt,
      sourceLanguageLabel: 'Auto-detect Spanish',
      targetLanguageLabel: 'English',
      transcriptEntries: const [],
      summaryMetadata: const StoredSummaryMetadata.empty(),
    );

    await repository.upsertMeeting(meeting);
    await repository.appendTranscriptEntry(
      meetingId: meeting.id,
      updatedAt: updatedAt,
      entry: StoredTranscriptEntry(
        id: 'entry-1',
        meetingId: meeting.id,
        languageCode: 'ES',
        originalText: '¿Podemos reunirnos el martes?',
        translatedText: 'Can we meet on Tuesday?',
        timestamp: updatedAt,
        speakerLabel: null,
        confidence: 0.98,
        status: 'final',
        playbackState: 'playable',
      ),
    );

    final snapshot = await repository.loadSnapshot();

    expect(repository.isEncryptedAtRest, isTrue);
    expect(store.storageDescription, contains('encrypted'));
    expect(snapshot.meetings, hasLength(1));
    expect(snapshot.meetings.single.transcriptCount, 1);
    expect(
      snapshot.meetings.single.transcriptEntries.single.translatedText,
      contains('Tuesday'),
    );
  });

  test('upserts a realtime transcript entry without duplicate rows', () async {
    final repository = LocalMeetingRepository(
      store: MemoryEncryptedLocalStore(),
    );
    final createdAt = DateTime.utc(2026, 5, 24, 1);
    final firstDeltaAt = DateTime.utc(2026, 5, 24, 1, 0, 1);
    final secondDeltaAt = DateTime.utc(2026, 5, 24, 1, 0, 2);

    await repository.upsertMeeting(
      StoredMeeting(
        id: 'meeting-1',
        title: 'Realtime transcript',
        createdAt: createdAt,
        updatedAt: createdAt,
        sourceLanguageLabel: 'Auto-detect Spanish',
        targetLanguageLabel: 'English',
        transcriptEntries: const [],
        summaryMetadata: const StoredSummaryMetadata.empty(),
      ),
    );
    await repository.upsertTranscriptEntry(
      meetingId: 'meeting-1',
      updatedAt: firstDeltaAt,
      entry: StoredTranscriptEntry(
        id: 'meeting-1-realtime-1',
        meetingId: 'meeting-1',
        languageCode: 'EN',
        originalText: 'Hola',
        translatedText: 'Hello',
        timestamp: firstDeltaAt,
        speakerLabel: null,
        confidence: null,
        status: 'partial',
        playbackState: 'none',
      ),
    );
    await repository.upsertTranscriptEntry(
      meetingId: 'meeting-1',
      updatedAt: secondDeltaAt,
      entry: StoredTranscriptEntry(
        id: 'meeting-1-realtime-1',
        meetingId: 'meeting-1',
        languageCode: 'EN',
        originalText: 'Hola',
        translatedText: 'Hello there.',
        timestamp: firstDeltaAt,
        speakerLabel: null,
        confidence: null,
        status: 'final',
        playbackState: 'none',
      ),
    );

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.meetings.single.transcriptEntries, hasLength(1));
    expect(
      snapshot.meetings.single.transcriptEntries.single.translatedText,
      'Hello there.',
    );
    expect(snapshot.meetings.single.transcriptEntries.single.status, 'final');
    expect(snapshot.meetings.single.updatedAt, secondDeltaAt);
  });

  test('stores generated meeting summaries locally with metadata', () async {
    final repository = LocalMeetingRepository(
      store: MemoryEncryptedLocalStore(),
    );
    final now = DateTime.utc(2026, 5, 24, 3);
    await repository.upsertMeeting(
      StoredMeeting(
        id: 'meeting-1',
        title: 'Project timeline review',
        createdAt: now,
        updatedAt: now,
        sourceLanguageLabel: 'Spanish',
        targetLanguageLabel: 'English',
        transcriptEntries: const [],
        summaryMetadata: const StoredSummaryMetadata.empty(),
      ),
    );

    final updated = await repository.saveMeetingSummary(
      meetingId: 'meeting-1',
      updatedAt: now.add(const Duration(minutes: 5)),
      summaryMetadata: StoredSummaryMetadata(
        available: true,
        updatedAt: now.add(const Duration(minutes: 5)),
        modelIntent: 'gpt-5.5',
        transcriptEntryCount: 0,
        text: 'Executive Summary\nNo transcript lines are stored yet.',
      ),
    );
    final snapshot = await repository.loadSnapshot();

    expect(updated, isNotNull);
    expect(snapshot.meetings.single.summaryAvailable, isTrue);
    expect(snapshot.meetings.single.summaryMetadata.modelIntent, 'gpt-5.5');
    expect(
      snapshot.meetings.single.summaryMetadata.text,
      contains('Executive Summary'),
    );
  });

  test(
    'stores generated export bodies on the encrypted meeting snapshot',
    () async {
      final store = MemoryEncryptedLocalStore();
      final repository = LocalMeetingRepository(store: store);
      final now = DateTime.utc(2026, 5, 24, 3);
      await repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Generated export meeting',
          createdAt: now,
          updatedAt: now,
          sourceLanguageLabel: 'Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      final updated = await repository.saveGeneratedExport(
        meetingId: 'meeting-1',
        updatedAt: now.add(const Duration(minutes: 2)),
        generatedExport: StoredGeneratedExport(
          id: 'export-1',
          meetingId: 'meeting-1',
          type: 'transcript',
          subject: 'Live Translate - Generated export meeting',
          body: 'Synthetic local export body',
          createdAt: now.add(const Duration(minutes: 2)),
          transcriptEntryCount: 0,
        ),
      );
      final snapshot = await repository.loadSnapshot();

      expect(repository.isEncryptedAtRest, isTrue);
      expect(updated, isNotNull);
      expect(snapshot.meetings.single.generatedExports, hasLength(1));
      expect(
        snapshot.meetings.single.generatedExports.single.body,
        contains('Synthetic'),
      );
      expect(snapshot.recipientPreferences.lastSelectedRecipients, isEmpty);
    },
  );

  test(
    'deletes meeting history without clearing recipient preferences',
    () async {
      final repository = LocalMeetingRepository(
        store: MemoryEncryptedLocalStore(),
      );
      final now = DateTime.utc(2026, 5, 24);

      await repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Delete me',
          createdAt: now,
          updatedAt: now,
          sourceLanguageLabel: 'English',
          targetLanguageLabel: 'Japanese',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );
      await repository.saveRecipientPreferences(
        const RecipientPreferences(
          rememberedRecipients: ['recipient@example.com'],
          lastSelectedRecipients: ['recipient@example.com'],
        ),
      );

      await repository.deleteMeeting('meeting-1');

      final snapshot = await repository.loadSnapshot();
      expect(snapshot.meetings, isEmpty);
      expect(snapshot.recipientPreferences.rememberedRecipients, [
        'recipient@example.com',
      ]);
    },
  );

  test(
    'serializes delete after concurrent transcript upsert without restoring row',
    () async {
      final store = _BlockingMemoryEncryptedLocalStore();
      final repository = LocalMeetingRepository(store: store);
      final now = DateTime.utc(2026, 5, 24, 4);

      await repository.upsertMeeting(
        StoredMeeting(
          id: 'meeting-1',
          title: 'Delete race',
          createdAt: now,
          updatedAt: now,
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          transcriptEntries: const [],
          summaryMetadata: const StoredSummaryMetadata.empty(),
        ),
      );

      store.blockNextWrite();
      final transcriptWrite = repository.upsertTranscriptEntry(
        meetingId: 'meeting-1',
        updatedAt: now.add(const Duration(seconds: 1)),
        entry: StoredTranscriptEntry(
          id: 'meeting-1-realtime-1',
          meetingId: 'meeting-1',
          languageCode: 'EN',
          originalText: 'Hola',
          translatedText: 'Hello',
          timestamp: now,
          speakerLabel: null,
          confidence: null,
          status: 'partial',
          playbackState: 'none',
        ),
      );
      await store.waitForBlockedWrite();

      final delete = repository.deleteMeeting('meeting-1');
      await Future<void>.delayed(Duration.zero);
      store.releaseBlockedWrite();
      await Future.wait([transcriptWrite, delete]);

      final snapshot = await repository.loadSnapshot();
      expect(snapshot.meetings, isEmpty);
    },
  );

  test(
    'stores recent language routes and recipient preferences locally',
    () async {
      final repository = LocalMeetingRepository(
        store: MemoryEncryptedLocalStore(),
      );
      final now = DateTime.utc(2026, 5, 24, 3);

      await repository.saveRecentLanguageRoute(
        LanguageRoutePreference(
          sourceLanguageLabel: 'Auto-detect Spanish',
          targetLanguageLabel: 'English',
          updatedAt: now,
        ),
      );
      await repository.saveRecipientPreferences(
        const RecipientPreferences(
          rememberedRecipients: [
            'recipient@example.com',
            'assistant@example.com',
          ],
          lastSelectedRecipients: ['assistant@example.com'],
        ),
      );

      final snapshot = await repository.loadSnapshot();
      expect(
        snapshot.recentLanguageRoutes.single.targetLanguageLabel,
        'English',
      );
      expect(snapshot.recipientPreferences.lastSelectedRecipients, [
        'assistant@example.com',
      ]);
    },
  );

  test('deleteAllLocalData clears sensitive local storage document', () async {
    final repository = LocalMeetingRepository(
      store: MemoryEncryptedLocalStore(),
    );

    await repository.saveSensitivePreference(key: 'retentionDays', value: '30');
    await repository.saveCredentialSessionMaterial(
      key: 'directOpenAISessionPlaceholder',
      value: 'placeholder-only',
    );
    await repository.deleteAllLocalData();

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.sensitivePreferences, isEmpty);
    expect(snapshot.credentialSessionMaterial, isEmpty);
  });
}

class _BlockingMemoryEncryptedLocalStore implements EncryptedLocalStore {
  final Map<String, String> _values = {};
  Completer<void>? _blockedWriteStarted;
  Completer<void>? _blockedWriteReleased;
  bool _blockNextWrite = false;

  @override
  bool get isEncryptedAtRest => true;

  @override
  String get storageDescription => 'blocking in-memory encrypted test double';

  void blockNextWrite() {
    _blockNextWrite = true;
    _blockedWriteStarted = Completer<void>();
    _blockedWriteReleased = Completer<void>();
  }

  Future<void> waitForBlockedWrite() {
    return _blockedWriteStarted!.future;
  }

  void releaseBlockedWrite() {
    final blockedWriteReleased = _blockedWriteReleased;
    if (blockedWriteReleased != null && !blockedWriteReleased.isCompleted) {
      blockedWriteReleased.complete();
    }
  }

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    if (_blockNextWrite) {
      _blockNextWrite = false;
      _blockedWriteStarted?.complete();
      await _blockedWriteReleased!.future;
    }

    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}
