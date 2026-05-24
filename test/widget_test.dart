import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:realtime_translate_mobile/main.dart';
import 'package:realtime_translate_mobile/src/session/microphone_permission.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';

void main() {
  testWidgets('shows phone-local start surface', (tester) async {
    await tester.pumpWidget(
      LiveTranslateApp(meetingRepository: _testRepository()),
    );

    expect(find.text('Live Translate'), findsOneWidget);
    expect(find.text('Start new meeting'), findsOneWidget);
    expect(find.text('Open meeting history'), findsOneWidget);
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

  testWidgets('opens teal listening and scoped AI chat surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: _testRepository(),
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();

    expect(find.text('Auto-detect Spanish -> English'), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Translate Text'), findsOneWidget);
    expect(find.text('Jump to Live'), findsOneWidget);

    await tester.tap(find.byTooltip('Open AI chat'));
    await tester.pumpAndSettle();

    expect(find.text('AI Chat'), findsOneWidget);
    expect(find.text('This meeting'), findsOneWidget);
    expect(
      find.text('What did they agree about the timeline?'),
      findsOneWidget,
    );
    expect(find.textContaining('10:37 AM'), findsWidgets);
  });

  testWidgets('opens amber paused read-aloud and export surfaces', (
    tester,
  ) async {
    final repository = _testRepository();
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.granted(),
        meetingRepository: repository,
      ),
    );

    await tester.tap(find.text('Start new meeting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch Direction'));
    await tester.pumpAndSettle();

    expect(find.text('English -> Japanese'), findsOneWidget);
    expect(find.text('Speaking'), findsOneWidget);
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

    await tester.tap(find.text('Open share sheet'));
    await tester.pumpAndSettle();

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.recipientPreferences.lastSelectedRecipients, [
      'recipient@example.com',
    ]);
  });

  testWidgets('blocks live session when microphone permission is denied', (
    tester,
  ) async {
    await tester.pumpWidget(
      LiveTranslateApp(
        permissionGateway: _FakePermissionGateway.denied(),
        meetingRepository: _testRepository(),
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
