// Génère de VRAIS PDF avec le code de l'app (rapport simple, rapport pro, facture)
// dans les 8 langues, avec des données réalistes (accents, €, apostrophes iPhone,
// nom polonais…). Échoue si un caractère est perdu ou si une génération plante.
// Vérifie aussi les pluriels polonais (1 / 2-4 / 5+).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

const langs = ['fr', 'en', 'de', 'es', 'it', 'nl', 'pl', 'pt'];

Map<String, dynamic> _json(String code) =>
    json.decode(File('assets/translations/$code.json').readAsStringSync())
        as Map<String, dynamic>;

void _useLanguage(String lang) {
  Localization.load(
    Locale(lang),
    translations: Translations(_json(lang)),
    fallbackTranslations: Translations(_json('fr')),
    ignorePluralRules: false, // comme l'app (main.dart)
  );
  Intl.defaultLocale = lang;
}

final _report = ReportModel(
  id: 'abcdef1234567890',
  reportNumber: 42,
  clientName: 'Łukasz Żółć — l’Hôtel « Côte »',
  clientAddress: '12 rue de l’Église, 75001 Paris',
  clientContact: 'Mme Ünal',
  interventionType: 'Dépannage chauffe-eau',
  description: 'Remplacement du circulateur… coût 120,50 € • garantie 2 ans',
  observations: 'Prévoir l’entretien — Ø 22 mm, 3 bar, ±5 %',
  equipmentBrand: 'Saunier Duval',
  equipmentSerial: 'SN-2026/Ä1',
  date: DateTime(2026, 10, 3),
  startTime: DateTime(2026, 10, 3, 8, 30),
  endTime: DateTime(2026, 10, 3, 11, 15),
  laborHours: 2.5,
  laborRate: 55,
  materials: const [
    MaterialItem(reference: 'CIRC-25', label: 'Circulateur ’Wilo’', quantity: 1, unitPrice: 189.9),
  ],
  createdAt: DateTime(2026, 10, 3),
  updatedAt: DateTime(2026, 10, 3),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting());

  for (final lang in langs) {
    test('PDF complets ($lang) : rapport simple + pro + facture', () async {
      _useLanguage(lang);
      final missing = <String>[];
      await runZoned(
        () async {
          for (final tpl in ['simple', 'professionnel']) {
            final bytes = await PdfService().generateReport(
              _report,
              companyName: 'Société Démo',
              technicianName: 'Jean Ünal',
              companySiret: '123 456 789 00012',
              companyTva: 'FR12345678900',
              pdfTemplate: tpl,
              currencyCode: lang == 'pl' ? 'PLN' : 'EUR',
            );
            expect(bytes.length, greaterThan(1000));
          }
          final invoice = await PdfService().generateInvoice(
            _report,
            companyName: 'Société Démo',
            taxRate: 20,
            taxLabel: 'TVA',
            taxMention: 'Mention — test « ok »',
            currencyCode: lang == 'pl' ? 'PLN' : 'EUR',
          );
          expect(invoice.length, greaterThan(1000));
        },
        zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
          final m = RegExp(r'Unable to find a font to draw "(.+?)"').firstMatch(line);
          if (m != null) missing.add(m.group(1)!);
        }),
      );
      expect(missing, isEmpty, reason: 'caractères perdus : ${missing.toSet()}');
    });
  }

  test('pluriels polonais : 1 / 2-4 / 5+ / 22', () {
    _useLanguage('pl');
    expect('quota_this_month'.plural(1), contains('1 eksport w'));
    expect('quota_this_month'.plural(3), contains('3 eksporty'));
    expect('quota_this_month'.plural(5), contains('5 eksportów'));
    expect('quota_this_month'.plural(22), contains('22 eksporty'));
  });

  test('pluriels des autres langues : 1 / 5', () {
    for (final lang in ['fr', 'en', 'de', 'es', 'it', 'nl', 'pt']) {
      _useLanguage(lang);
      final one = 'quota_this_month'.plural(1);
      final five = 'quota_this_month'.plural(5);
      expect(one, isNot(equals(five)), reason: lang);
      expect(five, contains('5'), reason: lang);
    }
  });
}
