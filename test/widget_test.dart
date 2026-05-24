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
}
