import '../language/language_support.dart';

class InterpreterLanguage {
  const InterpreterLanguage({required this.code, required this.label});

  final String code;
  final String label;
}

class BidirectionalInterpreterDirection {
  const BidirectionalInterpreterDirection({
    required this.source,
    required this.target,
    required this.routePlan,
  });

  final InterpreterLanguage source;
  final InterpreterLanguage target;
  final TranslationRoutePlan routePlan;

  String get sourceLanguageCode => source.code;
  String get targetLanguageCode => target.code;
}

class BidirectionalInterpreterRuntime {
  final List<InterpreterLanguage> _languages = <InterpreterLanguage>[];

  List<String> get languageCodes => [
    for (final language in _languages) language.code,
  ];

  bool get isPairLocked => _languages.length >= 2;

  String get routeLabel {
    if (_languages.length >= 2) {
      return '${_languages[0].label} <-> ${_languages[1].label}';
    }
    if (_languages.length == 1) {
      return 'Heard ${_languages.single.label}. Waiting for the other language...';
    }
    return 'Listening for languages...';
  }

  bool recordDetectedLanguage({required String code, required String label}) {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty || contains(normalized) || _languages.length >= 2) {
      return false;
    }

    _languages.add(
      InterpreterLanguage(
        code: normalized,
        label: label.trim().isEmpty ? normalized.toUpperCase() : label.trim(),
      ),
    );
    return true;
  }

  bool contains(String code) {
    final normalized = code.trim().toLowerCase();
    return _languages.any((language) => language.code == normalized);
  }

  BidirectionalInterpreterDirection? directionForSource(String sourceCode) {
    if (!isPairLocked) {
      return null;
    }

    final normalized = sourceCode.trim().toLowerCase();
    InterpreterLanguage? source;
    InterpreterLanguage? target;
    for (final language in _languages.take(2)) {
      if (language.code == normalized) {
        source = language;
      } else {
        target ??= language;
      }
    }
    if (source == null || target == null) {
      return null;
    }

    return BidirectionalInterpreterDirection(
      source: source,
      target: target,
      routePlan: LanguageSupport.planRoute(
        sourceCode: source.code,
        targetCode: target.code,
      ),
    );
  }
}

String? detectInterpreterLanguageCode(String text) {
  final normalized = text.toLowerCase();
  if (normalized.trim().isEmpty) {
    return null;
  }

  final scores = <String, int>{
    'en': _languageScore(normalized, const [
      'the',
      'and',
      'you',
      'we',
      'can',
      'confirm',
      'plan',
      'begin',
      'hello',
      'meeting',
      'please',
    ]),
    'it': _languageScore(normalized, const [
      'ciao',
      'grazie',
      'possiamo',
      'confermare',
      'piano',
      'iniziare',
      'buongiorno',
      'italiano',
    ]),
    'es': _languageScore(normalized, const [
      'hola',
      'gracias',
      'podemos',
      'buenos',
      'dias',
      'acuerdo',
    ]),
    'fr': _languageScore(normalized, const [
      'bonjour',
      'merci',
      'pouvons',
      'commencer',
      'reunion',
    ]),
  };
  final best = scores.entries.reduce(
    (left, right) => right.value > left.value ? right : left,
  );
  return best.value <= 0 ? null : best.key;
}

int _languageScore(String normalized, List<String> markers) {
  var score = 0;
  for (final marker in markers) {
    if (normalized.contains(marker)) {
      score += 1;
    }
  }
  return score;
}
