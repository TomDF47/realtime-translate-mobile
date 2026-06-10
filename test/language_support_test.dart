import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/language/language_support.dart';

void main() {
  test('Gemini live target table covers the current app languages', () {
    final targetCodes = [
      for (final language in LanguageSupport.realtimeTargetLanguages)
        language.code,
    ];

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
        'ar',
      ]),
    );
    expect(
      [for (final language in LanguageSupport.targetLanguages) language.code],
      containsAll(['en', 'es', 'fr', 'it', 'ja', 'de', 'pt', 'zh', 'ko', 'ar']),
    );
    expect(LanguageSupport.verifiedDate, '2026-06-10');
    expect(LanguageSupport.realtimeDocsUrl, startsWith('https://'));
    expect(LanguageSupport.realtimeCookbookUrl, startsWith('https://'));
  });

  test('routes current app targets through Gemini live translation', () {
    final realtimePlan = LanguageSupport.planRoute(
      sourceCode: 'auto',
      targetCode: 'en',
    );
    expect(realtimePlan.type, TranslationRouteType.realtime);
    expect(realtimePlan.availability, TranslationRouteAvailability.available);
    expect(realtimePlan.usesRealtime, isTrue);

    final arabicPlan = LanguageSupport.planRoute(
      sourceCode: 'en',
      targetCode: 'ar',
    );
    expect(arabicPlan.type, TranslationRouteType.realtime);
    expect(arabicPlan.availability, TranslationRouteAvailability.available);
    expect(arabicPlan.usesRealtime, isTrue);
    expect(arabicPlan.userMessage, contains('Gemini Live Translate'));
    expect(LanguageSupport.fallbackTargetLanguages, isEmpty);
  });

  test('routes Italian output through the realtime path', () {
    final plan = LanguageSupport.planRoute(sourceCode: 'en', targetCode: 'it');

    expect(plan.type, TranslationRouteType.realtime);
    expect(plan.usesRealtime, isTrue);
    expect(plan.availability, TranslationRouteAvailability.available);
  });
}
