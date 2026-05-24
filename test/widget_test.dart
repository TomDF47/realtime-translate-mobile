import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:realtime_translate_mobile/main.dart';
import 'package:realtime_translate_mobile/src/export/local_meeting_exporter.dart';
import 'package:realtime_translate_mobile/src/openai/openai_ai_chat.dart';
import 'package:realtime_translate_mobile/src/openai/openai_credential_store.dart';
import 'package:realtime_translate_mobile/src/openai/openai_meeting_summary.dart';
import 'package:realtime_translate_mobile/src/session/microphone_permission.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';
import 'package:realtime_translate_mobile/src/ui/live_translate_models.dart';

void main() {
  testWidgets('shows phone-local start surface', (tester) async {
    final repository = _testRepository();
    await tester.pumpWidget(LiveTranslateApp(meetingRepository: repository));

    expect(find.text('Live Translate'), findsOneWidget);
    expect(find.text('Start new meeting'), findsOneWidget);
    expect(find.text('Open meeting history'), findsOneWidget);
    expect(find.text('OpenAI setup'), findsOneWidget);
    expect(
      find.text(
        'Transcripts are stored on device only. Your conversations stay private.',
      ),
      findsOneWidget,
    );
    expect(find.text('Secure & Private'), findsOneWidget);
    expect(find.text('Android MVP'), findsOneWidget);

    expect(find.textContaining('Continue with'), findsNothing);
    expect(find.textContaining('Flutter Demo'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('saves OpenAI credential locally before live start', (
    tester,
  ) async {
    final repository = _testRepository();
    await tester.pumpWidget(LiveTranslateApp(meetingRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI setup required'), findsOneWidget);
    expect(find.text('Open OpenAI setup'), findsOneWidget);

    await tester.tap(find.text('Open OpenAI setup'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'placeholder-local-openai-credential',
    );
    await tester.tap(find.text('Save encrypted credential'));
    await tester.pumpAndSettle();

    expect(
      find.text('OpenAI credential stored on this device'),
      findsOneWidget,
    );
    expect(find.text('placeholder-local-openai-credential'), findsNothing);
    expect(
      await OpenAiCredentialStore(
        repository: repository,
      ).readCredentialForNetworkUse(),
      'placeholder-local-openai-credential',
    );
  });

  testWidgets('opens teal listening and scoped AI chat surfaces', (
    tester,
  ) async {
    final repository = _testRepository();
    final aiChatGateway = _FakeAiChatGateway(
      'They agreed to meet on Tuesday at 10 AM (10:37 AM).',
    );
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        aiChatGateway: aiChatGateway,
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();

    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Translate Text'), findsOneWidget);
    expect(find.text('Jump to Live'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('To language selector')));
    await tester.pumpAndSettle();

    expect(find.text('Realtime target languages'), findsOneWidget);
    expect(find.text('English (US)'), findsOneWidget);
    expect(find.text('Spanish (ES)'), findsOneWidget);
    expect(find.text('French (FR)'), findsOneWidget);
    expect(find.text('Japanese (JP)'), findsNothing);
    expect(find.text('Fallback route'), findsOneWidget);
    expect(find.textContaining('direct OpenAI fallback'), findsOneWidget);

    Navigator.of(tester.element(find.text('Realtime target languages'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open AI chat'));
    await tester.pumpAndSettle();

    expect(find.text('AI Chat'), findsOneWidget);
    expect(find.text('This meeting'), findsOneWidget);
    expect(find.textContaining('Ready to answer from'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'What did they agree about the timeline?',
    );
    await tester.tap(find.byTooltip('Send AI chat prompt'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('They agreed to meet on Tuesday at 10 AM'),
      findsOneWidget,
    );
    expect(
      aiChatGateway.requests.single.context.scope,
      AiChatScope.thisMeeting,
    );
    expect(
      aiChatGateway.requests.single.context.transcriptEntryCount,
      greaterThan(0),
    );
  });

  testWidgets('opens all-meetings AI chat from meeting history', (
    tester,
  ) async {
    final repository = _testRepository();
    final aiChatGateway = _FakeAiChatGateway(
      'Across meetings, the timeline was agreed at 10:37 AM.',
    );
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        aiChatGateway: aiChatGateway,
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meeting history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask across meetings'));
    await tester.pumpAndSettle();

    expect(find.text('AI Chat'), findsOneWidget);
    expect(find.text('All meetings'), findsOneWidget);
    expect(find.text('Ask across meetings...'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Summarise timeline');
    await tester.tap(find.byTooltip('Send AI chat prompt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Across meetings'), findsOneWidget);
    expect(
      aiChatGateway.requests.single.context.scope,
      AiChatScope.allMeetings,
    );
  });

  testWidgets('opens amber paused read-aloud and export surfaces', (
    tester,
  ) async {
    final repository = _testRepository();
    final nativeShareGateway = _FakeNativeShareGateway();
    final meetingSummaryGateway = _FakeMeetingSummaryGateway();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
        nativeShareGateway: nativeShareGateway,
        meetingSummaryGateway: meetingSummaryGateway,
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch Direction'));
    await tester.pumpAndSettle();

    expect(find.text('English -> Japanese'), findsOneWidget);
    expect(find.text('Speaking'), findsOneWidget);
    expect(find.text('Fallback pending'), findsOneWidget);
    expect(find.text('Read aloud is paused'), findsOneWidget);
    expect(find.text('Resume Read Aloud'), findsOneWidget);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export meeting'));
    await tester.pumpAndSettle();

    expect(find.text('Email export'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Both'), findsOneWidget);
    expect(find.text('recipient@example.com'), findsOneWidget);

    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.textContaining('direct OpenAI request'), findsOneWidget);
    await tester.ensureVisible(find.text('Open share sheet'));
    await tester.tap(find.text('Open share sheet'));
    await tester.pumpAndSettle();

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.recipientPreferences.lastSelectedRecipients, [
      'recipient@example.com',
    ]);
    expect(snapshot.meetings.single.summaryAvailable, isTrue);
    expect(meetingSummaryGateway.requests, hasLength(1));
    expect(nativeShareGateway.documents, hasLength(1));
    expect(nativeShareGateway.documents.single.type, ExportType.summary);
    expect(nativeShareGateway.documents.single.recipients, [
      'recipient@example.com',
    ]);
    expect(
      nativeShareGateway.documents.single.body,
      contains('Executive Summary'),
    );
    expect(
      nativeShareGateway.documents.single.body,
      isNot(contains('Transcript\n\n[')),
    );
    expect(
      find.text('Share sheet opened. Review the export before sending.'),
      findsOneWidget,
    );
  });

  testWidgets('blocks live session when microphone permission is denied', (
    tester,
  ) async {
    final repository = _testRepository();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.denied(),
        meetingRepository: repository,
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();

    expect(find.text('Microphone access needed'), findsOneWidget);
    expect(find.text('Try microphone permission again'), findsOneWidget);
    expect(
      find.text(
        'No audio is captured before microphone permission is granted.',
      ),
      findsOneWidget,
    );
    expect(find.text('Auto-detect Spanish -> English'), findsNothing);
  });

  testWidgets('persists and deletes local meeting history', (tester) async {
    final repository = _testRepository();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    expect((await repository.loadSnapshot()).meetings, hasLength(1));

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meeting history'));
    await tester.pumpAndSettle();

    expect(find.text('Project timeline review'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Project timeline review'));
    await tester.pumpAndSettle();

    expect((await repository.loadSnapshot()).meetings, isEmpty);
    expect(find.text('Start new meeting'), findsOneWidget);
  });

  testWidgets('selects an old meeting and appends local history', (
    tester,
  ) async {
    final repository = _testRepository();
    await _seedCredential(repository);
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();

    final initialMeeting = (await repository.loadSnapshot()).meetings.single;

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meeting history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project timeline review'));
    await tester.pumpAndSettle();

    final continuedMeeting = (await repository.loadSnapshot()).meetings.single;
    expect(continuedMeeting.id, initialMeeting.id);
    expect(
      continuedMeeting.transcriptCount,
      initialMeeting.transcriptCount + 1,
    );
    expect(continuedMeeting.createdAt, initialMeeting.createdAt);
    expect(
      continuedMeeting.updatedAt.isAfter(initialMeeting.updatedAt),
      isTrue,
    );
    expect(find.text('Project timeline review'), findsNothing);
    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);
  });
}

LocalMeetingRepository _testRepository() {
  return LocalMeetingRepository(store: MemoryEncryptedLocalStore());
}

Future<void> _seedCredential(LocalMeetingRepository repository) {
  return OpenAiCredentialStore(
    repository: repository,
  ).saveUserProvidedCredential('placeholder-local-openai-credential');
}

class _FakePermissionGateway implements MicrophonePermissionGateway {
  _FakePermissionGateway(this._status);

  _FakePermissionGateway.granted() : this(MicrophonePermissionStatus.granted);

  _FakePermissionGateway.denied() : this(MicrophonePermissionStatus.denied);

  final MicrophonePermissionStatus _status;

  @override
  Future<MicrophonePermissionStatus> checkStatus() async => _status;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<MicrophonePermissionStatus> request() async => _status;
}

class _FakeNativeShareGateway implements NativeShareGateway {
  final List<MeetingExportDocument> documents = [];

  @override
  Future<NativeShareResult> shareMeetingExport(
    MeetingExportDocument document,
  ) async {
    documents.add(document);
    return NativeShareResult.launched;
  }
}

class _FakeAiChatGateway implements AiChatGateway {
  _FakeAiChatGateway(this.answer);

  final String answer;
  final List<AiChatRequest> requests = [];

  @override
  Future<AiChatAnswer> ask({
    required AiChatRequest request,
    required String credential,
  }) async {
    requests.add(request);
    expect(credential, 'placeholder-local-openai-credential');
    return AiChatAnswer(
      text: answer,
      generatedAt: DateTime(2026, 5, 24, 2, 42),
    );
  }
}

class _FakeMeetingSummaryGateway implements MeetingSummaryGateway {
  final List<MeetingSummaryRequest> requests = [];

  @override
  Future<MeetingSummaryResult> generate({
    required MeetingSummaryRequest request,
    required String credential,
  }) async {
    requests.add(request);
    expect(credential, 'placeholder-local-openai-credential');
    return MeetingSummaryResult(
      text:
          'Executive Summary\nThe meeting aligned on the project timeline.\n\n'
          'Critical Talking Points And Outcomes\n- Review the deliverables.\n\n'
          'Actions\n- Share the draft plan.',
      generatedAt: DateTime(2026, 5, 24, 2, 45),
      modelIntent: request.model,
      transcriptEntryCount: request.transcriptEntryCount,
    );
  }
}
