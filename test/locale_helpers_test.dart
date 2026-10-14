// Anti-régression (2026-10-14) : lecture des nombres tapés, ponctuation
// « libellé : valeur », libellés des champs métier, n° de facture stable.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/reports/models/currency_options.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';
import 'package:reportnew1cld/features/reports/models/sector_options.dart';
import 'package:reportnew1cld/shared/services/pdf_service.dart';
import 'package:reportnew1cld/shared/utils/file_slug.dart';

void _useLanguage(String lang) {
  final m = json.decode(File('assets/translations/$lang.json').readAsStringSync())
      as Map<String, dynamic>;
  Localization.load(Locale(lang), translations: Translations(m), ignorePluralRules: false);
  Intl.defaultLocale = lang;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parseLocalNumber : toutes les écritures courantes', () {
    const cases = {
      '12': 12.0,
      '12,5': 12.5,
      '12.5': 12.5,
      ' 1 234,50 ': 1234.5,
      '1\u00A0234,50': 1234.5, // espace insécable (clavier FR)
      '1\u202F234,50': 1234.5, // espace fine insécable
      '1.234,50': 1234.5, // DE / ES / IT / NL / PT
      '1,234.50': 1234.5, // EN
      "1'234.50": 1234.5, // CH
      '1.234.567': 1234567.0,
      '1,234,567': 1234567.0,
      '-3,5': -3.5,
    };
    cases.forEach((input, expected) =>
        expect(parseLocalNumber(input), expected, reason: input));
    expect(parseLocalNumber(''), isNull);
    expect(parseLocalNumber('abc'), isNull);
    expect(parseLocalNumber(null), isNull);
  });

  test('labelSep : espace avant « : » seulement en français', () {
    expect(labelSep(locale: 'fr'), ' : ');
    expect(labelSep(locale: 'fr_FR'), ' : ');
    for (final l in ['en', 'de', 'es', 'it', 'nl', 'pl', 'pt']) {
      expect(labelSep(locale: l), ': ', reason: l);
    }
  });

  test('sectorFieldLabel : traduit (plus de « Type Tuyauterie » partout)', () {
    _useLanguage('de');
    expect(sectorFieldLabel('type_tuyauterie'), 'Rohrleitungstyp');
    expect(sectorFieldLabel('pression_testee_bar'), isNot(contains('_')));
    expect(sectorFieldLabel('champ_inconnu'), 'Champ inconnu'); // repli lisible
    _useLanguage('en');
    expect(sectorFieldLabel('type_tuyauterie'), 'Pipe type');
  });

  test('n° de facture : stable, basé sur la date de fin d’intervention', () {
    _useLanguage('fr');
    final r = ReportModel(
      id: 'x',
      reportNumber: 7,
      clientName: 'C',
      date: DateTime(2026, 12, 30),
      endDate: DateTime(2027, 1, 2),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(PdfService.invoiceNumber(r), endsWith('-007-2027'));
    final single = ReportModel(
        id: 'y', reportNumber: 8, clientName: 'C', date: DateTime(2026, 12, 30),
        createdAt: DateTime(2026), updatedAt: DateTime(2026));
    expect(PdfService.invoiceNumber(single), endsWith('-008-2026'));
  });

  test('fileSlug : accents retirés, pas de lettres perdues', () {
    expect(fileSlug('Müller GmbH'), 'Muller_GmbH');
    expect(fileSlug('Société Générale'), 'Societe_Generale');
    expect(fileSlug('Łukasz Żółć'), 'Lukasz_Zolc');
    expect(fileSlug("l’Hôtel « Côte » & Fils"), 'l_Hotel_Cote_Fils');
    expect(fileSlug('Dupont/Fils:SA'), 'Dupont_Fils_SA');
    expect(fileSlug(''), '');
    expect(fileSlug('a' * 100).length, lessThanOrEqualTo(40));
  });
}
