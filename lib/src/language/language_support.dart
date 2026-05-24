enum TranslationRouteType { realtime, directOpenAiFallback }

enum TranslationRouteAvailability { available, requiresLocalCredential }

class TranslationLanguage {
  const TranslationLanguage({
    required this.code,
    required this.name,
    required this.regionLabel,
    required this.supportsSource,
    required this.supportsRealtimeTarget,
    required this.supportsDirectFallback,
  });

  final String code;
  final String name;
  final String regionLabel;
  final bool supportsSource;
  final bool supportsRealtimeTarget;
  final bool supportsDirectFallback;

  String get displayLabel {
    if (regionLabel.isEmpty) {
      return name;
    }

    return '$name $regionLabel';
  }
}

class TranslationRoutePlan {
  const TranslationRoutePlan({
    required this.source,
    required this.target,
    required this.type,
    required this.availability,
    required this.userMessage,
  });

  final TranslationLanguage source;
  final TranslationLanguage target;
  final TranslationRouteType type;
  final TranslationRouteAvailability availability;
  final String userMessage;

  bool get usesRealtime => type == TranslationRouteType.realtime;

  bool get isAvailableNow =>
      availability == TranslationRouteAvailability.available;
}

abstract final class LanguageSupport {
  static const verifiedDate = '2026-05-24';
  static const realtimeDocsUrl =
      'https://developers.openai.com/api/docs/guides/realtime-translation';
  static const realtimeModelUrl =
      'https://developers.openai.com/api/docs/models/gpt-realtime-translate';
  static const translationClientSecretUrl =
      'https://developers.openai.com/api/reference/resources/realtime/subresources/translations/subresources/client_secrets/methods/create';

  static const autoDetectSource = TranslationLanguage(
    code: 'auto',
    name: 'Auto-detect',
    regionLabel: '',
    supportsSource: true,
    supportsRealtimeTarget: false,
    supportsDirectFallback: false,
  );

  static const languages = [
    autoDetectSource,
    TranslationLanguage(
      code: 'en',
      name: 'English',
      regionLabel: '(US)',
      supportsSource: true,
      supportsRealtimeTarget: true,
      supportsDirectFallback: true,
    ),
    TranslationLanguage(
      code: 'es',
      name: 'Spanish',
      regionLabel: '(ES)',
      supportsSource: true,
      supportsRealtimeTarget: true,
      supportsDirectFallback: true,
    ),
    TranslationLanguage(
      code: 'fr',
      name: 'French',
      regionLabel: '(FR)',
      supportsSource: true,
      supportsRealtimeTarget: true,
      supportsDirectFallback: true,
    ),
    TranslationLanguage(
      code: 'ja',
      name: 'Japanese',
      regionLabel: '(JP)',
      supportsSource: true,
      supportsRealtimeTarget: false,
      supportsDirectFallback: true,
    ),
    TranslationLanguage(
      code: 'de',
      name: 'German',
      regionLabel: '(DE)',
      supportsSource: true,
      supportsRealtimeTarget: false,
      supportsDirectFallback: true,
    ),
    TranslationLanguage(
      code: 'pt',
      name: 'Portuguese',
      regionLabel: '(BR)',
      supportsSource: true,
      supportsRealtimeTarget: false,
      supportsDirectFallback: true,
    ),
    TranslationLanguage(
      code: 'zh',
      name: 'Chinese',
      regionLabel: '(Mandarin)',
      supportsSource: true,
      supportsRealtimeTarget: false,
      supportsDirectFallback: true,
    ),
    TranslationLanguage(
      code: 'ko',
      name: 'Korean',
      regionLabel: '(KR)',
      supportsSource: true,
      supportsRealtimeTarget: false,
      supportsDirectFallback: true,
    ),
    TranslationLanguage(
      code: 'ar',
      name: 'Arabic',
      regionLabel: '',
      supportsSource: true,
      supportsRealtimeTarget: false,
      supportsDirectFallback: true,
    ),
    TranslationLanguage(
      code: 'hi',
      name: 'Hindi',
      regionLabel: '',
      supportsSource: true,
      supportsRealtimeTarget: false,
      supportsDirectFallback: true,
    ),
  ];

  static List<TranslationLanguage> get sourceLanguages {
    return [
      for (final language in languages)
        if (language.supportsSource) language,
    ];
  }

  static List<TranslationLanguage> get realtimeTargetLanguages {
    return [
      for (final language in languages)
        if (language.supportsRealtimeTarget) language,
    ];
  }

  static List<TranslationLanguage> get fallbackTargetLanguages {
    return [
      for (final language in languages)
        if (!language.supportsRealtimeTarget && language.supportsDirectFallback)
          language,
    ];
  }

  static TranslationLanguage languageByCode(String code) {
    final normalized = code.trim().toLowerCase();
    for (final language in languages) {
      if (language.code == normalized) {
        return language;
      }
    }

    throw ArgumentError.value(code, 'code', 'Unsupported language code');
  }

  static TranslationRoutePlan planRoute({
    required String sourceCode,
    required String targetCode,
  }) {
    final source = languageByCode(sourceCode);
    final target = languageByCode(targetCode);
    if (!source.supportsSource || target.code == 'auto') {
      throw ArgumentError(
        'Route requires a supported source and explicit target language.',
      );
    }

    if (target.supportsRealtimeTarget) {
      return TranslationRoutePlan(
        source: source,
        target: target,
        type: TranslationRouteType.realtime,
        availability: TranslationRouteAvailability.available,
        userMessage: '${target.name} is available in the realtime target list.',
      );
    }

    return TranslationRoutePlan(
      source: source,
      target: target,
      type: TranslationRouteType.directOpenAiFallback,
      availability: TranslationRouteAvailability.requiresLocalCredential,
      userMessage:
          '${target.name} requires the phone-only direct OpenAI fallback path.',
    );
  }
}
