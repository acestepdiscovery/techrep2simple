// Traductions (2026-10-19) : vérifie à chaque `flutter test` ce qui était
// vérifié à la main jusqu'ici.
//  1. Les 8 langues ont exactement les mêmes clés.
//  2. Toute clé utilisée dans le code (`'cle'.tr()` / `.plural()`) existe.
//  3. Même nombre de « {} » (arguments) dans chaque langue qu'en français :
//     sinon le nom du client / le montant ne s'affiche pas, ou « {} » reste
//     visible à l'écran.
//  4. Aucune valeur vide.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const langs = ['fr', 'en', 'de', 'es', 'it', 'nl', 'pl', 'pt'];

Map<String, dynamic> _load(String lang) =>
    json.decode(File('assets/translations/$lang.json').readAsStringSync())
        as Map<String, dynamic>;

/// Toutes les chaînes d'une valeur (texte simple, ou pluriel {one, other…}).
Iterable<String> _texts(dynamic v) sync* {
  if (v is String) {
    yield v;
  } else if (v is Map) {
    for (final x in v.values) {
      yield* _texts(x);
    }
  }
}

int _args(dynamic v) {
  var max = 0;
  for (final t in _texts(v)) {
    final n = '{}'.allMatches(t).length;
    if (n > max) max = n;
  }
  return max;
}

void main() {
  final all = {for (final l in langs) l: _load(l)};
  final fr = all['fr']!;

  test('les 8 langues ont les mêmes clés', () {
    for (final l in langs) {
      final keys = all[l]!.keys.toSet();
      expect(keys.difference(fr.keys.toSet()), isEmpty, reason: '$l : en trop');
      expect(fr.keys.toSet().difference(keys), isEmpty, reason: '$l : manquantes');
    }
  });

  test('toutes les clés utilisées dans le code existent', () {
    final used = <String>{};
    final re = RegExp(r"'([a-z][a-z0-9_]+)'\s*\.\s*(?:tr|plural)\(");
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        used.addAll(re.allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
      }
    }
    expect(used.difference(fr.keys.toSet()), isEmpty);
  });

  test('même nombre d\'arguments {} dans chaque langue', () {
    final bad = <String>[];
    for (final k in fr.keys) {
      final ref = _args(fr[k]);
      for (final l in langs) {
        final n = _args(all[l]![k]);
        if (n != ref) bad.add('$l/$k : $n au lieu de $ref');
      }
    }
    expect(bad, isEmpty);
  });

  test('aucune traduction vide', () {
    final bad = <String>[];
    for (final l in langs) {
      all[l]!.forEach((k, v) {
        if (_texts(v).any((t) => t.trim().isEmpty)) bad.add('$l/$k');
      });
    }
    expect(bad, isEmpty);
  });
}
