// Vérifie que les PDF savent dessiner tous les caractères courants.
// La police par défaut du package pdf (Helvetica) ne couvre que les codes 0–255 :
// sans police de secours, « € », « — », « ’ » (apostrophe auto de l'iPhone) ou
// les lettres polonaises sortent EN BLANC dans le PDF (le package l'écrit en log).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:reportnew1cld/shared/services/pdf_fonts.dart';

/// Construit un PDF avec [text] et renvoie les caractères que la police n'a pas su dessiner.
Future<List<String>> missingGlyphs(String text, {pw.ThemeData? theme}) async {
  final missing = <String>[];
  await runZoned(
    () async {
      final doc = pw.Document(theme: theme);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(children: [
          pw.Text(text),
          pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ]),
      ));
      await doc.save();
    },
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      final m = RegExp(r'Unable to find a font to draw "(.+?)"').firstMatch(line);
      if (m != null) missing.add(m.group(1)!);
    }),
  );
  return missing;
}

const sample = 'Total : 120,00 € — l’eau chaude… « OK » • Kraków: zażółć gęślą jaźń';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // pour charger les polices (assets)

  test('police par défaut (Helvetica seule) : caractères perdus', () async {
    final missing = await missingGlyphs(sample);
    // ignore: avoid_print
    print('Helvetica seule → ${missing.toSet().join(' ')}');
    expect(missing, isNotEmpty); // documente le défaut d'origine
  });

  for (final lang in ['fr', 'en', 'de', 'es', 'it', 'nl', 'pt', 'pl']) {
    test('thème PDF de l\'app ($lang) : aucun caractère perdu', () async {
      final missing = await missingGlyphs(sample, theme: await PdfFonts.theme(language: lang));
      expect(missing, isEmpty, reason: 'caractères perdus : ${missing.toSet()}');
    });
  }

  test('polonais = Noto partout ; autres langues = Helvetica (aspect inchangé)', () async {
    final pl = await PdfFonts.theme(language: 'pl');
    final fr = await PdfFonts.theme(language: 'fr');
    expect(pl.defaultTextStyle.font, same(await PdfFonts.regular()));
    expect(fr.defaultTextStyle.font, isNot(same(await PdfFonts.regular())));
  });
}
