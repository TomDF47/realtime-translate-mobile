import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/mock/mock_live_translate_data.dart';
import 'package:realtime_translate_mobile/src/theme/live_translate_theme.dart';
import 'package:realtime_translate_mobile/src/ui/live_translate_components.dart';
import 'package:realtime_translate_mobile/src/ui/live_translate_models.dart';

void main() {
  test('maps session modes to stable labels and accents', () {
    expect(LiveSessionMode.listening.statusLabel, 'Listening');
    expect(LiveSessionMode.speaking.statusLabel, 'Speaking');
    expect(LiveSessionMode.readAloudPaused.statusLabel, 'Read aloud paused');

    expect(AppColors.forSessionMode(LiveSessionMode.listening), AppColors.teal);
    expect(AppColors.forSessionMode(LiveSessionMode.speaking), AppColors.amber);
    expect(
      AppColors.forSessionMode(LiveSessionMode.readAloudPaused),
      AppColors.amber,
    );
  });

  test('keeps AI chat scope labels explicit', () {
    expect(AiChatScope.thisMeeting.label, 'This meeting');
    expect(AiChatScope.allMeetings.label, 'All meetings');
    expect(
      AiChatScope.thisMeeting.inputPlaceholder,
      'Ask about this meeting...',
    );
    expect(AiChatScope.allMeetings.inputPlaceholder, 'Ask across meetings...');
  });

  testWidgets('renders session components from structured data', (
    tester,
  ) async {
    final session = MockLiveTranslateData.listeningSession;

    await tester.pumpWidget(
      MaterialApp(
        theme: LiveTranslateTheme.dark(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SessionStatusCard(session: session),
              const SizedBox(height: AppSpacing.sm),
              LanguageSelectorCard(data: session.fromLanguage),
              const SizedBox(height: AppSpacing.sm),
              FeatureChip(data: session.features.first),
              const SizedBox(height: AppSpacing.sm),
              const TranscriptCard(
                entry: TranscriptEntryData(
                  languageCode: 'EN',
                  originalText: 'Source speech captured locally.',
                  translatedText: 'Live translation is ready.',
                  timestamp: '10:37 AM',
                  accent: LiveAccent.blue,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 220,
                child: TranscriptList(entries: session.transcriptEntries),
              ),
              const SizedBox(height: AppSpacing.sm),
              JumpToLiveChip(onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Italian <-> English'), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Auto-detect'), findsNothing);
    expect(find.text('Italian'), findsOneWidget);
    expect(find.text('Spanish'), findsNothing);
    expect(find.text('Translate Text'), findsOneWidget);
    expect(find.text('Live translation is ready.'), findsOneWidget);
    expect(find.text('Waiting for speech'), findsOneWidget);
    expect(find.text('Jump to Live', skipOffstage: false), findsOneWidget);
  });

  testWidgets('renders queue, scope, and export controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LiveTranslateTheme.dark(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              QueueBanner(
                data: MockLiveTranslateData.speakingPausedSession.queueBanner!,
                onPrimaryPressed: () {},
                onSecondaryPressed: () {},
              ),
              const SizedBox(height: AppSpacing.sm),
              const AiChatScopePill(scope: AiChatScope.thisMeeting),
              const SizedBox(height: AppSpacing.sm),
              ExportTypeSelector(selected: ExportType.both, onChanged: (_) {}),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Read aloud is paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Skip to Live'), findsOneWidget);
    expect(find.text('This meeting'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Both'), findsOneWidget);
  });
}
