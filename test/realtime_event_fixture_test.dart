import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_realtime_translation.dart';
import 'package:realtime_translate_mobile/src/session/realtime_transcript_committer.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';
import 'package:realtime_translate_mobile/src/storage/local_storage_models.dart';

/// Fixture-driven committer test.
///
/// This replays a sequence of real-shaped `/v1/realtime/translations` events
/// through the production [LiveRealtimeTranscriptCommitter] and asserts the
/// resulting transcript rows. The fixture currently holds the DOCUMENTED event
/// shapes; swap in a redacted on-device capture (see the fixture's GROUND TRUTH
/// TODO) without changing this test. The point of this test is to stop encoding
/// hand-guessed event orderings inline and instead drive the committer from a
/// single, swappable event-shape fixture.
void main() {
  test('documented realtime event stream commits two language-correct cards',
      () async {
    final events = _loadFixtureEvents(
      'test/fixtures/realtime_translation_documented_turns.json',
    );
    expect(events, isNotEmpty, reason: 'fixture must contain events');

    final repository = LocalMeetingRepository(store: MemoryEncryptedLocalStore());
    final startedAt = DateTime.utc(2026, 6, 1, 6);
    await repository.upsertMeeting(
      StoredMeeting(
        id: 'meeting-1',
        title: 'Fixture replay',
        createdAt: startedAt,
        updatedAt: startedAt,
        sourceLanguageLabel: 'Auto-detect',
        targetLanguageLabel: 'English',
        transcriptEntries: const [],
        summaryMetadata: const StoredSummaryMetadata.empty(),
      ),
    );

    final committer = LiveRealtimeTranscriptCommitter(
      LiveRealtimeTranscriptCommitTarget(
        repository: repository,
        meetingId: 'meeting-1',
        sourceLanguageCode: 'auto',
        targetLanguageCode: 'en',
        now: () => startedAt,
      ),
    );

    for (final raw in events) {
      final event = OpenAiRealtimeEventParser.parse(raw);
      if (event is OpenAiRealtimeTranscriptDelta) {
        await committer.commitDelta(event);
      } else if (event is OpenAiRealtimeTranscriptCompleted) {
        await committer.commitCompleted(event);
      }
    }
    await committer.finish(interrupted: false);

    final entries =
        (await repository.loadSnapshot()).meetings.single.transcriptEntries;

    // Two distinct utterances must produce two distinct cards (no collapse into
    // one block) and every card must carry its original speech.
    expect(entries, hasLength(2));
    for (final entry in entries) {
      expect(entry.originalText, isNotEmpty,
          reason: 'every card must show original speech');
    }

    final italian = entries.first;
    expect(italian.languageCode, 'IT');
    expect(italian.originalText, 'Buongiorno, come stai?');
    expect(italian.translatedText, 'Good morning, how are you?');

    // The English utterance reaches the English-output session, which stays
    // silent on output, so the committer holds the original with no realtime
    // translation. The reverse-direction TEXT is backfilled by the
    // coordinator's direct OpenAI text path (covered in the coordinator tests).
    final english = entries.last;
    expect(english.languageCode, 'EN');
    expect(english.originalText, 'Hello, what are you going to do today?');
    expect(english.translatedText, isEmpty);
  });
}

List<Map<String, dynamic>> _loadFixtureEvents(String path) {
  final file = File(path);
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final events = decoded['events'] as List<dynamic>;
  return [
    for (final event in events) (event as Map<String, dynamic>),
  ];
}
