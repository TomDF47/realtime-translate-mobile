/// Lightweight deterministic language detection for live source segmentation.
///
/// This is not a general-purpose language detector. It is a privacy-safe,
/// dependency-free fallback for the app's supported language set when the
/// realtime wire does not include language metadata. Script-based languages
/// are detected first; Latin-script languages use small marker sets.
String? detectLocalLanguageCode(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final scriptCode = _detectScriptLanguage(trimmed);
  if (scriptCode != null) {
    return scriptCode;
  }

  final tokens = _latinTokens(trimmed);
  if (tokens.isEmpty) {
    return null;
  }

  final tokenSet = tokens.toSet();
  final scores = <String, int>{
    for (final entry in _latinMarkers.entries)
      entry.key: _markerScore(tokens, tokenSet, entry.value),
  };

  var bestCode = '';
  var bestScore = 0;
  var tiedBestScore = false;
  for (final entry in scores.entries) {
    if (entry.value > bestScore) {
      bestCode = entry.key;
      bestScore = entry.value;
      tiedBestScore = false;
    } else if (entry.value == bestScore && entry.value > 0) {
      tiedBestScore = true;
    }
  }

  if (bestScore <= 0 || tiedBestScore) {
    return null;
  }

  if (bestScore >= _minimumLocalLanguageScore) {
    return bestCode;
  }

  final englishScore = scores['en'] ?? 0;
  final hasDistinctiveMarker =
      bestCode != 'en' &&
      englishScore == 0 &&
      _hasDistinctiveMarker(tokenSet, _latinMarkers[bestCode] ?? const []);
  return hasDistinctiveMarker ? bestCode : null;
}

String? _detectScriptLanguage(String text) {
  var hasKana = false;
  var hasHan = false;
  var hasHangul = false;
  var hasCyrillic = false;
  var hasArabic = false;
  var hasDevanagari = false;

  for (final rune in text.runes) {
    hasKana = hasKana || _inRange(rune, 0x3040, 0x30ff);
    hasHan =
        hasHan ||
        _inRange(rune, 0x3400, 0x4dbf) ||
        _inRange(rune, 0x4e00, 0x9fff) ||
        _inRange(rune, 0x20000, 0x2a6df);
    hasHangul =
        hasHangul ||
        _inRange(rune, 0x1100, 0x11ff) ||
        _inRange(rune, 0x3130, 0x318f) ||
        _inRange(rune, 0xac00, 0xd7af);
    hasCyrillic = hasCyrillic || _inRange(rune, 0x0400, 0x04ff);
    hasArabic =
        hasArabic ||
        _inRange(rune, 0x0600, 0x06ff) ||
        _inRange(rune, 0x0750, 0x077f) ||
        _inRange(rune, 0x08a0, 0x08ff);
    hasDevanagari = hasDevanagari || _inRange(rune, 0x0900, 0x097f);
  }

  if (hasKana) {
    return 'ja';
  }
  if (hasHangul) {
    return 'ko';
  }
  if (hasDevanagari) {
    return 'hi';
  }
  if (hasArabic) {
    return 'ar';
  }
  if (hasCyrillic) {
    return 'ru';
  }
  if (hasHan) {
    return 'zh';
  }
  return null;
}

bool _inRange(int rune, int start, int end) => rune >= start && rune <= end;

List<String> _latinTokens(String text) {
  final tokens = <String>[];
  final current = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    if (_isLatinLetter(rune)) {
      current.writeCharCode(rune);
    } else if (current.isNotEmpty) {
      tokens.add(current.toString());
      current.clear();
    }
  }
  if (current.isNotEmpty) {
    tokens.add(current.toString());
  }
  return tokens;
}

bool _isLatinLetter(int rune) {
  return _inRange(rune, 0x0061, 0x007a) ||
      _inRange(rune, 0x00c0, 0x00ff) ||
      _inRange(rune, 0x0100, 0x024f) ||
      _inRange(rune, 0x1e00, 0x1eff);
}

int _markerScore(
  List<String> tokens,
  Set<String> tokenSet,
  List<String> markers,
) {
  var score = 0;
  for (final marker in markers) {
    final markerTokens = marker.split(' ');
    if (markerTokens.length == 1) {
      if (tokenSet.contains(marker)) {
        score += 1;
      }
      continue;
    }
    for (var i = 0; i <= tokens.length - markerTokens.length; i++) {
      if (_matchesAt(tokens, markerTokens, i)) {
        score += 1;
        break;
      }
    }
  }
  return score;
}

bool _matchesAt(List<String> tokens, List<String> markerTokens, int index) {
  for (var i = 0; i < markerTokens.length; i++) {
    if (tokens[index + i] != markerTokens[i]) {
      return false;
    }
  }
  return true;
}

bool _hasDistinctiveMarker(Set<String> tokenSet, List<String> markers) {
  return markers.any(
    (marker) =>
        !marker.contains(' ') &&
        !_ambiguousSingleMarkers.contains(marker) &&
        tokenSet.contains(marker),
  );
}

const _minimumLocalLanguageScore = 2;

const _latinMarkers = <String, List<String>>{
  'en': [
    'the',
    'and',
    'you',
    'we',
    'what',
    'how',
    'are',
    'going',
    'hello',
    'thank',
    'thanks',
    'meeting',
    'timeline',
    'please',
    'okay',
    'continue',
  ],
  'es': [
    'hola',
    'gracias',
    'buenos',
    'dias',
    'd\u00edas',
    'estas',
    'est\u00e1s',
    'esta',
    'est\u00e1',
    'que',
    'qu\u00e9',
    'por',
    'favor',
    'hablo',
    'espanol',
    'espa\u00f1ol',
    'podemos',
    'acuerdo',
  ],
  'fr': [
    'bonjour',
    'merci',
    'salut',
    'avec',
    'pourquoi',
    'parle',
    'francais',
    'fran\u00e7ais',
    'nous',
    'vous',
    'etre',
    '\u00eatre',
    'oui',
    'non',
    'r\u00e9union',
    'reunion',
    'commencer',
  ],
  'it': [
    'ciao',
    'grazie',
    'buongiorno',
    'buonasera',
    'allora',
    'cosa',
    'perche',
    'perch\u00e8',
    'perch\u00e9',
    'sono',
    'siamo',
    'mi',
    'piace',
    'calcio',
    'buono',
    'buona',
    'questo',
    'questa',
    'quello',
    'quella',
    'parlo',
    'italiano',
    'come',
    'stai',
    'sta',
    'bene',
    'tutti',
    'tutto',
    'sei',
    'molto',
    'anche',
  ],
  'de': [
    'hallo',
    'danke',
    'guten',
    'tag',
    'bitte',
    'spreche',
    'deutsch',
    'wir',
    'k\u00f6nnen',
    'konnen',
    'plan',
    'beginnen',
    'termin',
    'besprechung',
  ],
  'pt': [
    'ol\u00e1',
    'ola',
    'obrigado',
    'obrigada',
    'bom',
    'boa',
    'dia',
    'tudo',
    'bem',
    'voce',
    'voc\u00ea',
    'por',
    'favor',
    'falo',
    'portugues',
    'portugu\u00eas',
    'podemos',
  ],
  'id': [
    'halo',
    'terima',
    'kasih',
    'selamat',
    'pagi',
    'siang',
    'sore',
    'malam',
    'apa',
    'kabar',
    'saya',
    'kita',
    'bisa',
    'rapat',
  ],
  'vi': [
    'xin',
    'ch\u00e0o',
    'chao',
    'c\u1ea3m',
    'cam',
    '\u01a1n',
    'ban',
    'b\u1ea1n',
    'toi',
    't\u00f4i',
    'ch\u00fang',
    'chung',
    'ta',
    'cu\u1ed9c',
    'cuoc',
    'h\u1ecdp',
    'hop',
  ],
};

const _ambiguousSingleMarkers = <String>{
  'come',
  'mi',
  'que',
  'por',
  'favor',
  'dia',
  'plan',
  'tag',
  'ta',
};
