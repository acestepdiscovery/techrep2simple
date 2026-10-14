/// Partie « nom du client » d'un nom de fichier (2026-10-14).
///
/// Avant : `[^\w]` (ASCII seulement) supprimait les lettres accentuées →
/// « Müller » → « Mller », « Société Générale » → « Socit_Gnrale », « Łukasz »
/// → « ukasz ». Ici on retire les accents (é → e, ü → u, ł → l, ß → ss…), puis
/// on ne garde que lettres, chiffres, « - » et « _ » (noms sûrs pour les
/// e-mails et tous les systèmes de fichiers).
String fileSlug(String input, {int maxLength = 40}) {
  final b = StringBuffer();
  for (final r in input.trim().runes) {
    final ch = String.fromCharCode(r);
    b.write(_fold[ch] ?? ch);
  }
  var s = b
      .toString()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (s.length > maxLength) s = s.substring(0, maxLength).replaceAll(RegExp(r'_$'), '');
  return s;
}

/// Texte « comparable » pour la recherche (2026-10-14) : minuscules et SANS
/// accents → « societe » trouve « Société », « muller » trouve « Müller ».
String searchFold(String input) {
  final b = StringBuffer();
  for (final r in input.runes) {
    final ch = String.fromCharCode(r);
    b.write(_fold[ch] ?? ch);
  }
  return b.toString().toLowerCase();
}

const Map<String, String> _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ą': 'a',
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A', 'Ą': 'A',
  'æ': 'ae', 'Æ': 'AE', 'œ': 'oe', 'Œ': 'OE', 'ß': 'ss',
  'ç': 'c', 'ć': 'c', 'č': 'c', 'Ç': 'C', 'Ć': 'C', 'Č': 'C',
  'ď': 'd', 'Ď': 'D', 'đ': 'd', 'Đ': 'D',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ę': 'e', 'ě': 'e',
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', 'Ę': 'E', 'Ě': 'E',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
  'ł': 'l', 'Ł': 'L', 'ľ': 'l', 'Ľ': 'L',
  'ñ': 'n', 'ń': 'n', 'ň': 'n', 'Ñ': 'N', 'Ń': 'N', 'Ň': 'N',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ø': 'O',
  'ř': 'r', 'Ř': 'R', 'ś': 's', 'š': 's', 'Ś': 'S', 'Š': 'S', 'ť': 't', 'Ť': 'T',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ů': 'u', 'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U', 'Ů': 'U',
  'ý': 'y', 'ÿ': 'y', 'Ý': 'Y', 'ź': 'z', 'ż': 'z', 'ž': 'z', 'Ź': 'Z', 'Ż': 'Z', 'Ž': 'Z',
};
