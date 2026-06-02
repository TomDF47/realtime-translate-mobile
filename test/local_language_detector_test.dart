import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/language/local_language_detector.dart';

void main() {
  test('detects Latin-script supported languages from markers', () {
    expect(detectLocalLanguageCode('Hello, how are you?'), 'en');
    expect(detectLocalLanguageCode('Hola, gracias por venir.'), 'es');
    expect(detectLocalLanguageCode('Bonjour, merci pour la r\u00e9union.'), 'fr');
    expect(detectLocalLanguageCode('Mi piace il calcio.'), 'it');
    expect(detectLocalLanguageCode('Hallo, danke f\u00fcr den Termin.'), 'de');
    expect(detectLocalLanguageCode('Ol\u00e1, obrigado. Tudo bem?'), 'pt');
    expect(detectLocalLanguageCode('Terima kasih, selamat pagi.'), 'id');
    expect(
      detectLocalLanguageCode('Xin ch\u00e0o, c\u1ea3m \u01a1n b\u1ea1n.'),
      'vi',
    );
  });

  test('detects script-based supported languages', () {
    expect(
      detectLocalLanguageCode(
        '\u3053\u3093\u306b\u3061\u306f\u3001'
        '\u3042\u308a\u304c\u3068\u3046\u3054\u3056\u3044\u307e\u3059\u3002',
      ),
      'ja',
    );
    expect(
      detectLocalLanguageCode('\u4f60\u597d\uff0c\u8c22\u8c22\u3002'),
      'zh',
    );
    expect(
      detectLocalLanguageCode(
        '\uc548\ub155\ud558\uc138\uc694 '
        '\uac10\uc0ac\ud569\ub2c8\ub2e4.',
      ),
      'ko',
    );
    expect(
      detectLocalLanguageCode(
        '\u041f\u0440\u0438\u0432\u0435\u0442, '
        '\u0441\u043f\u0430\u0441\u0438\u0431\u043e.',
      ),
      'ru',
    );
    expect(
      detectLocalLanguageCode(
        '\u0928\u092e\u0938\u094d\u0924\u0947 '
        '\u0927\u0928\u094d\u092f\u0935\u093e\u0926\u0964',
      ),
      'hi',
    );
    expect(
      detectLocalLanguageCode(
        '\u0645\u0631\u062d\u0628\u0627 \u0634\u0643\u0631\u0627.',
      ),
      'ar',
    );
  });

  test('returns null for ambiguous or empty text', () {
    expect(detectLocalLanguageCode(''), isNull);
    expect(detectLocalLanguageCode('OK 42.'), isNull);
  });
}
