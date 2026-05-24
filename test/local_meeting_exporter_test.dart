import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/export/local_meeting_exporter.dart';
import 'package:realtime_translate_mobile/src/storage/local_storage_models.dart';
import 'package:realtime_translate_mobile/src/ui/live_translate_models.dart';

void main() {
  test('composes transcript export document for native share', () {
    final meeting = _meeting();

    final document = LocalMeetingExportComposer.compose(
      meeting: meeting,
      type: ExportType.transcript,
      recipients: const ['recipient@example.com'],
    );

    expect(document.subject, 'Live Translate - Project timeline review');
    expect(document.type, ExportType.transcript);
    expect(document.recipients, ['recipient@example.com']);
    expect(document.body, contains('Route: Spanish -> English'));
    expect(document.body, contains('Original: ¿Podemos reunirnos?'));
    expect(document.body, contains('Translation: Can we meet?'));
    expect(document.body, contains('Prepared locally on this device.'));
    expect(document.toMethodArguments(), containsPair('type', 'transcript'));
  });

  test(
    'does not produce fake summary exports before summary generation lands',
    () {
      final meeting = _meeting();

      expect(
        () => LocalMeetingExportComposer.compose(
          meeting: meeting,
          type: ExportType.summary,
          recipients: const ['recipient@example.com'],
        ),
        throwsA(isA<SummaryExportUnavailableException>()),
      );
      expect(
        () => LocalMeetingExportComposer.compose(
          meeting: meeting,
          type: ExportType.both,
          recipients: const ['recipient@example.com'],
        ),
        throwsA(isA<SummaryExportUnavailableException>()),
      );
    },
  );
}

StoredMeeting _meeting() {
  final timestamp = DateTime.utc(2026, 5, 24, 2, 37);
  return StoredMeeting(
    id: 'meeting-1',
    title: 'Project timeline review',
    createdAt: timestamp,
    updatedAt: timestamp,
    sourceLanguageLabel: 'Spanish',
    targetLanguageLabel: 'English',
    transcriptEntries: [
      StoredTranscriptEntry(
        id: 'entry-1',
        meetingId: 'meeting-1',
        languageCode: 'ES',
        originalText: '¿Podemos reunirnos?',
        translatedText: 'Can we meet?',
        timestamp: timestamp,
        speakerLabel: null,
        confidence: null,
        status: 'final',
        playbackState: 'playable',
      ),
    ],
    summaryMetadata: const StoredSummaryMetadata.empty(),
  );
}
