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
  ];

  static const footerBadges = [
    FooterBadgeData(label: 'Secure & Private', icon: Icons.shield_outlined),
    FooterBadgeData(label: 'Android MVP', icon: Icons.android_rounded),
  ];

  static const assistantPrompts = [
    PromptChipData(label: 'Summarise action items'),
    PromptChipData(label: 'What do they need from me?'),
    PromptChipData(label: 'Regenerate', icon: Icons.refresh_rounded),
  ];

  static const listeningSession = LiveSessionViewData(
    routeLabel: 'Auto-detect Spanish -> English',
    elapsedLabel: '00:05:23',
    mode: LiveSessionMode.listening,
    fromLanguage: LanguageSelectorData(
      eyebrow: 'From',
      primaryLabel: 'Auto-detect',
      secondaryLabel: 'Spanish',
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
    transcriptEntries: [
      TranscriptEntryData(
        languageCode: 'ES',
        originalText: '¿Podemos reunirnos el martes a las 10 de la mañana?',
        translatedText: 'Can we meet on Tuesday at 10 AM?',
        timestamp: '10:37 AM',
        accent: LiveAccent.teal,
      ),
      TranscriptEntryData(
        languageCode: 'EN',
        originalText: 'Sí, eso debería funcionar para mí.',
        translatedText: 'Yes, that should work for me.',
        timestamp: '10:38 AM',
        accent: LiveAccent.blue,
      ),
      TranscriptEntryData(
        languageCode: 'ES',
        originalText:
            'Perfecto. Revisaremos los entregables y el cronograma del proyecto.',
        translatedText:
            "Perfect. We'll review the deliverables and project timeline.",
        timestamp: '10:38 AM',
        accent: LiveAccent.teal,
      ),
    ],
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
    isAtLiveEdge: false,
  );

  static const speakingPausedSession = LiveSessionViewData(
    routeLabel: 'English -> Japanese',
    elapsedLabel: '00:06:12',
    mode: LiveSessionMode.readAloudPaused,
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
        icon: Icons.spatial_audio_off_rounded,
        accent: LiveAccent.amber,
        isPassive: true,
      ),
    ],
    queueBanner: QueueBannerData(
      title: 'Read aloud is paused',
      detail: 'Queued: 4 lines (00:12 behind)',
      primaryActionLabel: 'Resume',
      secondaryActionLabel: 'Skip to Live',
      accent: LiveAccent.amber,
    ),
    transcriptEntries: [
      TranscriptEntryData(
        languageCode: 'EN',
        speakerLabel: 'You',
        originalText:
            "Thanks everyone. I'd like to walk through the next steps for the project.",
        translatedText:
            "Thanks everyone. I'd like to walk through the next steps for the project.",
        timestamp: '10:37 AM',
        accent: LiveAccent.amber,
        playbackState: TranscriptPlaybackState.speaking,
      ),
      TranscriptEntryData(
        languageCode: 'JA',
        originalText: 'ありがとうございます。プロジェクトの次のステップについて説明します。',
        translatedText: 'ありがとうございます。プロジェクトの次のステップについて説明します。',
        timestamp: '10:37 AM',
        accent: LiveAccent.amber,
      ),
      TranscriptEntryData(
        languageCode: 'EN',
        speakerLabel: 'You',
        originalText:
            'We are targeting a draft by end of day Friday. Does that timeline work for you?',
        translatedText:
            'We are targeting a draft by end of day Friday. Does that timeline work for you?',
        timestamp: '10:38 AM',
        accent: LiveAccent.amber,
        playbackState: TranscriptPlaybackState.speaking,
      ),
    ],
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
    isAtLiveEdge: false,
  );
}
