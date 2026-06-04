import 'package:flutter/material.dart';

enum LiveAccent { teal, blue, amber, red, neutral }

enum LiveSessionMode { listening, speaking, readAloudPaused }

extension LiveSessionModeLabels on LiveSessionMode {
  String get statusLabel {
    return switch (this) {
      LiveSessionMode.listening => 'Listening',
      LiveSessionMode.speaking => 'Speaking',
      LiveSessionMode.readAloudPaused => 'Read aloud paused',
    };
  }

  LiveAccent get accent {
    return switch (this) {
      LiveSessionMode.listening => LiveAccent.teal,
      LiveSessionMode.speaking => LiveAccent.amber,
      LiveSessionMode.readAloudPaused => LiveAccent.amber,
    };
  }
}

enum AiChatScope { thisMeeting, allMeetings }

extension AiChatScopeLabels on AiChatScope {
  String get label {
    return switch (this) {
      AiChatScope.thisMeeting => 'This meeting',
      AiChatScope.allMeetings => 'All meetings',
    };
  }

  String get inputPlaceholder {
    return switch (this) {
      AiChatScope.thisMeeting => 'Ask about this meeting...',
      AiChatScope.allMeetings => 'Ask across meetings...',
    };
  }

  String get privacyLabel {
    return switch (this) {
      AiChatScope.thisMeeting =>
        'Responses are based on this local meeting only.',
      AiChatScope.allMeetings =>
        'Responses are based on local meeting history only.',
    };
  }
}

enum TranscriptPlaybackState { none, playable, speaking }

enum ExportType { transcript, summary, both }

extension ExportTypeLabels on ExportType {
  String get label {
    return switch (this) {
      ExportType.transcript => 'Transcript',
      ExportType.summary => 'Summary',
      ExportType.both => 'Both',
    };
  }
}

class LocalSetupActionData {
  const LocalSetupActionData({
    required this.label,
    required this.icon,
    required this.semanticLabel,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final String semanticLabel;
  final bool isPrimary;
}

class FooterBadgeData {
  const FooterBadgeData({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class LanguageSelectorData {
  const LanguageSelectorData({
    required this.eyebrow,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.icon,
    required this.accent,
    this.spokenOutputEnabled = false,
  });

  final String eyebrow;
  final String primaryLabel;
  final String secondaryLabel;
  final IconData icon;
  final LiveAccent accent;
  final bool spokenOutputEnabled;
}

class FeatureChipData {
  const FeatureChipData({
    required this.label,
    required this.icon,
    required this.accent,
    this.isEnabled = false,
    this.isPassive = false,
  });

  final String label;
  final IconData icon;
  final LiveAccent accent;
  final bool isEnabled;
  final bool isPassive;
}

class TranscriptEntryData {
  const TranscriptEntryData({
    required this.languageCode,
    required this.originalText,
    required this.translatedText,
    required this.timestamp,
    required this.accent,
    this.statusLabel,
    this.speakerLabel,
    this.playbackState = TranscriptPlaybackState.playable,
  });

  final String languageCode;
  final String originalText;
  final String translatedText;
  final String timestamp;
  final LiveAccent accent;
  final String? statusLabel;
  final String? speakerLabel;
  final TranscriptPlaybackState playbackState;
}

class QueueBannerData {
  const QueueBannerData({
    required this.title,
    required this.detail,
    required this.primaryActionLabel,
    required this.secondaryActionLabel,
    required this.accent,
  });

  final String title;
  final String detail;
  final String primaryActionLabel;
  final String secondaryActionLabel;
  final LiveAccent accent;
}

class BottomControlActionData {
  const BottomControlActionData({
    required this.label,
    required this.icon,
    required this.accent,
    required this.semanticLabel,
    this.isEnabled = true,
  });

  final String label;
  final IconData icon;
  final LiveAccent accent;
  final String semanticLabel;
  final bool isEnabled;
}

class PromptChipData {
  const PromptChipData({required this.label, this.icon});

  final String label;
  final IconData? icon;
}

class LiveSessionViewData {
  const LiveSessionViewData({
    required this.routeLabel,
    required this.elapsedLabel,
    required this.mode,
    required this.fromLanguage,
    required this.toLanguage,
    required this.features,
    required this.transcriptEntries,
    required this.bottomControls,
    this.queueBanner,
    this.isAtLiveEdge = true,
    this.showLanguageControls = true,
    this.statusLabel,
    this.statusAccent,
    this.languageRouteNotice,
  });

  final String routeLabel;
  final String elapsedLabel;
  final LiveSessionMode mode;
  final LanguageSelectorData fromLanguage;
  final LanguageSelectorData toLanguage;
  final List<FeatureChipData> features;
  final List<TranscriptEntryData> transcriptEntries;
  final List<BottomControlActionData> bottomControls;
  final QueueBannerData? queueBanner;
  final bool isAtLiveEdge;
  final bool showLanguageControls;
  final String? statusLabel;
  final LiveAccent? statusAccent;
  final String? languageRouteNotice;

  LiveSessionViewData copyWith({
    String? routeLabel,
    String? elapsedLabel,
    LiveSessionMode? mode,
    LanguageSelectorData? fromLanguage,
    LanguageSelectorData? toLanguage,
    List<FeatureChipData>? features,
    List<TranscriptEntryData>? transcriptEntries,
    List<BottomControlActionData>? bottomControls,
    QueueBannerData? queueBanner,
    bool? isAtLiveEdge,
    bool? showLanguageControls,
    String? statusLabel,
    LiveAccent? statusAccent,
    String? languageRouteNotice,
  }) {
    return LiveSessionViewData(
      routeLabel: routeLabel ?? this.routeLabel,
      elapsedLabel: elapsedLabel ?? this.elapsedLabel,
      mode: mode ?? this.mode,
      fromLanguage: fromLanguage ?? this.fromLanguage,
      toLanguage: toLanguage ?? this.toLanguage,
      features: features ?? this.features,
      transcriptEntries: transcriptEntries ?? this.transcriptEntries,
      bottomControls: bottomControls ?? this.bottomControls,
      queueBanner: queueBanner ?? this.queueBanner,
      isAtLiveEdge: isAtLiveEdge ?? this.isAtLiveEdge,
      showLanguageControls: showLanguageControls ?? this.showLanguageControls,
      statusLabel: statusLabel ?? this.statusLabel,
      statusAccent: statusAccent ?? this.statusAccent,
      languageRouteNotice: languageRouteNotice ?? this.languageRouteNotice,
    );
  }
}
