import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/language/language_support.dart';

void main() {
  test('realtime target table matches the 13 documented output languages', () {
    final targetCodes = [
      for (final language in LanguageSupport.realtimeTargetLanguages)
        language.code,
    ];

    // The 13 official Realtime Translation output languages.
    expect(
      targetCodes,
      containsAll([
        'en',
        'es',
        'fr',
        'it',
        'ja',
        'ru',
        'zh',
        'de',
        'ko',
        'hi',
        'id',
        'vi',
        'pt',
      ]),
    );
    // Arabic is auto-detected as a source but is not a realtime output target.
    expect(targetCodes, isNot(contains('ar')));
    expect(
      [for (final language in LanguageSupport.targetLanguages) language.code],
      containsAll(['en', 'es', 'fr', 'it', 'ja', 'de', 'pt', 'zh', 'ko', 'ar']),
    );
    expect(LanguageSupport.verifiedDate, '2026-06-01');
    expect(LanguageSupport.realtimeDocsUrl, startsWith('https://'));
    expect(LanguageSupport.realtimeCookbookUrl, startsWith('https://'));
  });

  test('routes non-output targets to direct OpenAI fallback only', () {
    final realtimePlan = LanguageSupport.planRoute(
      sourceCode: 'auto',
      targetCode: 'en',
    );
    expect(realtimePlan.type, TranslationRouteType.realtime);
    expect(realtimePlan.availability, TranslationRouteAvailability.available);
    expect(realtimePlan.usesRealtime, isTrue);

    // Arabic is not one of the 13 output languages, so it still routes to the
    // phone-only direct OpenAI text fallback.
    final fallbackPlan = LanguageSupport.planRoute(
      sourceCode: 'en',
      targetCode: 'ar',
    );
    expect(fallbackPlan.type, TranslationRouteType.directOpenAiFallback);
    expect(
      fallbackPlan.availability,
      TranslationRouteAvailability.requiresLocalCredential,
    );
    expect(fallbackPlan.usesRealtime, isFalse);
    expect(fallbackPlan.userMessage, contains('phone-only direct OpenAI'));
  });

  test('routes Italian output through the realtime path', () {
    final plan = LanguageSupport.planRoute(sourceCode: 'en', targetCode: 'it');

    expect(plan.type, TranslationRouteType.realtime);
    expect(plan.usesRealtime, isTrue);
    expect(plan.availability, TranslationRouteAvailability.available);
  });
}
