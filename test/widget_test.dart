import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:realtime_translate_mobile/main.dart';

void main() {
  testWidgets('shows phone-local start surface', (tester) async {
    await tester.pumpWidget(const LiveTranslateApp());

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
    await tester.pumpWidget(const LiveTranslateApp());

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
    await tester.pumpWidget(const LiveTranslateApp());

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
  });
}
