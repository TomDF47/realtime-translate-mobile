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

  test('requires generated summary text before summary exports', () {
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

    final summaryDocument = LocalMeetingExportComposer.compose(
      meeting: meeting,
      type: ExportType.summary,
      recipients: const ['recipient@example.com'],
      summaryText:
          'Executive Summary\nThe team agreed on the timeline.\n\nActions\n- Share the draft.',
    );
    expect(summaryDocument.type, ExportType.summary);
    expect(summaryDocument.body, contains('Summary'));
    expect(summaryDocument.body, contains('The team agreed on the timeline'));
    expect(summaryDocument.body, isNot(contains('Transcript\n\n[')));

    final bothDocument = LocalMeetingExportComposer.compose(
      meeting: _meeting(
        summaryMetadata: const StoredSummaryMetadata(
          available: true,
          updatedAt: null,
          modelIntent: 'gpt-5.5',
          transcriptEntryCount: 1,
          text:
              'Executive Summary\nThe team agreed on the timeline.\n\nActions\n- Share the draft.',
        ),
      ),
      type: ExportType.both,
      recipients: const ['recipient@example.com'],
    );
    expect(bothDocument.body, contains('Summary'));
    expect(bothDocument.body, contains('Transcript'));
    expect(bothDocument.body, contains('Original: ¿Podemos reunirnos?'));
  });
}

StoredMeeting _meeting({StoredSummaryMetadata? summaryMetadata}) {
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
    summaryMetadata: summaryMetadata ?? const StoredSummaryMetadata.empty(),
  );
}
