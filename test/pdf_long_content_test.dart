// Anti-régression (2026-10-14) : un rapport long ne doit JAMAIS faire planter
// la génération PDF, et une grosse facture doit continuer sur plusieurs pages.
// Avant : texte > ~6 000 caractères ou > ~40 articles → plantage (« won't fit
// into the page » / TooManyPagesException) ; facture en page unique → lignes ET
// totaux HT/TVA/TTC coupés en silence au-delà d'une douzaine d'articles.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';
import 'package:reportnew1cld/shared/services/pdf_service.dart';

const _para =
    'Remplacement du circulateur… coût 120,50 € • garantie 2 ans. Prévoir l’entretien — Ø 22 mm, 3 bar, ±5 %. '
    'Le client « Côte » signale un bruit intermittent ; contrôle des raccords, purge du réseau, essai sous pression. ';

/// Nombre de pages d'un PDF produit par le paquet `pdf` (dictionnaires de page
/// non compressés).
int _pageCount(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length;

ReportModel _report({int paragraphs = 1, int items = 1}) => ReportModel(
      id: 'x',
      clientName: 'Client',
      date: DateTime(2026, 10, 14),
      description: List.filled(paragraphs, _para).join('\n'),
      observations: List.filled(paragraphs, _para).join('\n'),
      laborHours: 1.5,
      laborRate: 50,
      materials: [
        for (var i = 0; i < items; i++)
          MaterialItem(reference: 'R$i', label: 'Article $i', quantity: 1, unitPrice: 10),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting();
    final m = json.decode(File('assets/translations/fr.json').readAsStringSync())
        as Map<String, dynamic>;
    Localization.load(const Locale('fr'),
        translations: Translations(m), ignorePluralRules: false);
    Intl.defaultLocale = 'fr';
  });

  for (final tpl in ['simple', 'professionnel']) {
    test('rapport $tpl : 60 paragraphes + 180 articles → pas de plantage', () async {
      final bytes = await PdfService().generateReport(
          _report(paragraphs: 60, items: 180),
          pdfTemplate: tpl,
          currencyCode: 'EUR');
      expect(_pageCount(bytes), greaterThan(3));
    });
  }

  test('facture : 1 article = 1 page ; 60 articles = plusieurs pages', () async {
    final small = await PdfService().generateInvoice(_report(), currencyCode: 'EUR');
    expect(_pageCount(small), 1);
    final big = await PdfService().generateInvoice(_report(items: 60), currencyCode: 'EUR');
    expect(_pageCount(big), greaterThan(1));
  });
}
