import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/language/language_support.dart';

void main() {
  test('keeps realtime target language table conservative and typed', () {
    final targetCodes = [
      for (final language in LanguageSupport.realtimeTargetLanguages)
        language.code,
    ];

    expect(targetCodes, containsAll(['en', 'es', 'fr']));
    expect(targetCodes, isNot(contains('ja')));
    expect(LanguageSupport.verifiedDate, '2026-05-24');
    expect(LanguageSupport.realtimeDocsUrl, startsWith('https://'));
  });

  test('routes unsupported targets to direct OpenAI fallback only', () {
    final realtimePlan = LanguageSupport.planRoute(
      sourceCode: 'auto',
      targetCode: 'en',
    );
    expect(realtimePlan.type, TranslationRouteType.realtime);
    expect(realtimePlan.availability, TranslationRouteAvailability.available);
    expect(realtimePlan.usesRealtime, isTrue);

    final fallbackPlan = LanguageSupport.planRoute(
      sourceCode: 'en',
      targetCode: 'ja',
    );
    expect(fallbackPlan.type, TranslationRouteType.directOpenAiFallback);
    expect(
      fallbackPlan.availability,
      TranslationRouteAvailability.pendingCredentialDecision,
    );
    expect(fallbackPlan.usesRealtime, isFalse);
    expect(fallbackPlan.userMessage, contains('phone-only direct OpenAI'));
  });
}
