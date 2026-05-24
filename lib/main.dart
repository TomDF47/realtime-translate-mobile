import 'package:flutter/material.dart';

import 'src/mock/mock_live_translate_data.dart';
import 'src/theme/live_translate_theme.dart';
import 'src/ui/live_translate_components.dart';

void main() {
  runApp(const LiveTranslateApp());
}

class LiveTranslateApp extends StatelessWidget {
  const LiveTranslateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Translate',
      debugShowCheckedModeBanner: false,
      theme: LiveTranslateTheme.dark(),
      home: const LocalSetupScreen(),
    );
  }
}

class LocalSetupScreen extends StatelessWidget {
  const LocalSetupScreen({super.key});

  static const _privacyLabel =
      'Transcripts are stored on device only. Your conversations stay private.';

  @override
  Widget build(BuildContext context) {
    return LiveTranslateShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _LocalSetupHero(),
                  _LocalSetupActions(),
                  Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xxl),
                    child: FooterBadgeRow(
                      badges: MockLiveTranslateData.footerBadges,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LocalSetupHero extends StatelessWidget {
  const _LocalSetupHero();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.xxl),
        const WaveLogo(),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          'Live Translate',
          textAlign: TextAlign.center,
          style: AppTextStyles.display(textTheme),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Live conversation translation for meetings and face-to-face moments',
          textAlign: TextAlign.center,
          style: AppTextStyles.body(textTheme).copyWith(fontSize: 18),
        ),
        const SizedBox(height: 44),
        const AudioWavePanel(),
      ],
    );
  }
}

class _LocalSetupActions extends StatelessWidget {
  const _LocalSetupActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final action in MockLiveTranslateData.localSetupActions) ...[
          LocalSetupActionButton(action: action, onPressed: () {}),
          if (action != MockLiveTranslateData.localSetupActions.last)
            const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xl),
        const PrivacyNote(label: LocalSetupScreen._privacyLabel),
      ],
    );
  }
}
