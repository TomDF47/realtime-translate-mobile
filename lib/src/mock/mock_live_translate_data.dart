import 'package:flutter/material.dart';

import '../ui/live_translate_models.dart';

abstract final class MockLiveTranslateData {
  static const localSetupActions = [
    LocalSetupActionData(
      label: 'Start new meeting',
      icon: Icons.add_circle_outline_rounded,
      semanticLabel: 'Start new meeting',
      isPrimary: true,
    ),
    LocalSetupActionData(
      label: 'Open meeting history',
      icon: Icons.history_rounded,
      semanticLabel: 'Open meeting history',
    ),
    LocalSetupActionData(
      label: 'OpenAI setup',
      icon: Icons.key_rounded,
      semanticLabel: 'OpenAI setup',
    ),
  ];

  static const assistantPrompts = [
    PromptChipData(label: 'Summarise action items'),
    PromptChipData(label: 'What do they need from me?'),
    PromptChipData(label: 'Regenerate', icon: Icons.refresh_rounded),
  ];

  static const listeningSession = LiveSessionViewData(
    routeLabel: 'Auto-detect -> English',
    elapsedLabel: '00:05:23',
    mode: LiveSessionMode.listening,
    fromLanguage: LanguageSelectorData(
      eyebrow: 'From',
      primaryLabel: 'Auto-detect',
      secondaryLabel: '',
      icon: Icons.graphic_eq_rounded,
      accent: LiveAccent.teal,
    ),
    toLanguage: LanguageSelectorData(
      eyebrow: 'To',
      primaryLabel: 'English',
      secondaryLabel: '(US)',
      icon: Icons.volume_up_rounded,
      accent: LiveAccent.blue,
    ),
    features: [
      FeatureChipData(
        label: 'Translate Text',
        icon: Icons.text_fields_rounded,
        accent: LiveAccent.blue,
        isEnabled: true,
      ),
      FeatureChipData(
        label: 'Read Aloud',
        icon: Icons.volume_up_rounded,
        accent: LiveAccent.blue,
        isEnabled: true,
      ),
      FeatureChipData(
        label: 'Headphones Active',
        icon: Icons.headphones_rounded,
        accent: LiveAccent.teal,
        isPassive: true,
      ),
    ],
    transcriptEntries: [],
    bottomControls: [
      BottomControlActionData(
        label: 'Stop Listening',
        icon: Icons.stop_rounded,
        accent: LiveAccent.red,
        semanticLabel: 'Stop listening',
      ),
      BottomControlActionData(
        label: 'Pause Read Aloud',
        icon: Icons.pause_rounded,
        accent: LiveAccent.blue,
        semanticLabel: 'Pause read aloud',
      ),
      BottomControlActionData(
        label: 'Switch Direction',
        icon: Icons.swap_horiz_rounded,
        accent: LiveAccent.neutral,
        semanticLabel: 'Switch translation direction',
      ),
    ],
    isAtLiveEdge: true,
  );

  static const speakingPausedSession = LiveSessionViewData(
    routeLabel: 'English -> Japanese',
    elapsedLabel: '00:06:12',
    mode: LiveSessionMode.speaking,
    fromLanguage: LanguageSelectorData(
      eyebrow: 'From',
      primaryLabel: 'English',
      secondaryLabel: '(US)',
      icon: Icons.graphic_eq_rounded,
      accent: LiveAccent.amber,
    ),
    toLanguage: LanguageSelectorData(
      eyebrow: 'To',
      primaryLabel: 'Japanese',
      secondaryLabel: '(JP)',
      icon: Icons.volume_up_rounded,
      accent: LiveAccent.amber,
    ),
    features: [
      FeatureChipData(
        label: 'Translate Text',
        icon: Icons.text_fields_rounded,
        accent: LiveAccent.amber,
        isEnabled: true,
      ),
      FeatureChipData(
        label: 'Read Aloud',
        icon: Icons.volume_up_rounded,
        accent: LiveAccent.amber,
        isEnabled: true,
      ),
      FeatureChipData(
        label: 'Speaker Active',
        icon: Icons.volume_up_rounded,
        accent: LiveAccent.amber,
        isPassive: true,
      ),
    ],
    queueBanner: QueueBannerData(
      title: 'Read aloud is paused',
      detail: 'Translated audio will queue while paused.',
      primaryActionLabel: 'Resume',
      secondaryActionLabel: 'Skip to Live',
      accent: LiveAccent.amber,
    ),
    transcriptEntries: [],
    bottomControls: [
      BottomControlActionData(
        label: 'Stop Listening',
        icon: Icons.stop_rounded,
        accent: LiveAccent.red,
        semanticLabel: 'Stop listening',
      ),
      BottomControlActionData(
        label: 'Resume Read Aloud',
        icon: Icons.play_arrow_rounded,
        accent: LiveAccent.amber,
        semanticLabel: 'Resume read aloud',
      ),
      BottomControlActionData(
        label: 'Switch Direction',
        icon: Icons.swap_horiz_rounded,
        accent: LiveAccent.neutral,
        semanticLabel: 'Switch translation direction',
      ),
    ],
    isAtLiveEdge: true,
  );
}
