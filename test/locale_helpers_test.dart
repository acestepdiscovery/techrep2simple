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
import 'package:reportnew1cld/features/reports/models/tax_options.dart';
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

  test('facture : les montants affichés s’additionnent au centime près', () {
    expect(roundMoney(1.005), 1.01);
    expect(roundMoney(4.995), 5.0);
    expect(roundMoney(-1.005), -1.01);
    final r = ReportModel(
      id: 'z', clientName: 'C', date: DateTime(2026),
      materials: const [
        MaterialItem(reference: '', label: 'a', quantity: 1.5, unitPrice: 3.33),
        MaterialItem(reference: '', label: 'b', quantity: 1.5, unitPrice: 3.33),
        MaterialItem(reference: '', label: 'c', quantity: 1.5, unitPrice: 3.33),
      ],
      createdAt: DateTime(2026), updatedAt: DateTime(2026));
    final t = PdfService.invoiceTotals(r, 20);
    expect(t.subtotal, 15.0); // 3 × 5,00 (lignes arrondies)
    expect(t.tax, 3.0);
    expect(t.total, 18.0);
    expect(roundMoney(t.subtotal + t.tax), t.total);
  });

  // (2026-10-21) Canada : TPS + TVQ (Québec) et GST + PST / RST sur 2 lignes séparées.
  test('taxe composée : composantes reconnues (libellé + taux exacts)', () {
    expect(taxComponents('TPS + TVQ', 14.975), [('TPS', 5.0), ('TVQ', 9.975)]);
    expect(taxComponents(' tps + tvq ', 14.975), isNotNull, reason: 'casse / espaces');
    expect(taxComponents('GST + PST', 12), [('GST', 5.0), ('PST', 7.0)]);
    expect(taxComponents('GST + PST', 11), [('GST', 5.0), ('PST', 6.0)]);
    expect(taxComponents('TPS + TVQ', 15), isNull, reason: 'taux modifié à la main → 1 ligne');
    expect(taxComponents('TVA', 20), isNull);
    expect(formatTaxRate(9.975, locale: 'fr'), '9,975', reason: 'TVQ affichée en entier');
    expect(formatTaxRate(5.5, locale: 'fr'), '5,5');
    expect(formatTaxRate(20, locale: 'fr'), '20');
    // Chaque préréglage composé du Canada est bien décomposable.
    final ca = taxCountryByCode('CA')!;
    for (final p in ca.presets.where((p) => p.label.contains('+'))) {
      expect(taxComponents(p.label, p.rate), isNotNull, reason: '${p.label} ${p.rate}');
    }
    expect(ca.presets.any((p) => p.label == 'TPS + TVQ' && p.rate == 14.975), isTrue);
  });

  test('taxe composée : chaque ligne arrondie, la taxe totale = leur somme', () {
    final r = ReportModel(
      id: 'q', clientName: 'C', date: DateTime(2026),
      laborHours: 1, laborRate: 123.45,
      createdAt: DateTime(2026), updatedAt: DateTime(2026));
    final t = PdfService.invoiceTotals(r, 14.975, taxLabel: 'TPS + TVQ');
    expect(t.subtotal, 123.45);
    expect(t.parts, [('TPS', 5.0, 6.17), ('TVQ', 9.975, 12.31)]);
    expect(t.tax, 18.48, reason: '6,17 + 12,31 (un seul taux donnerait 18,49)');
    expect(t.total, 141.93);
    final simple = PdfService.invoiceTotals(r, 20, taxLabel: 'TVA');
    expect(simple.parts, isEmpty);
    expect(simple.tax, 24.69);
  });

  // (2026-10-21) Pays francophones ajoutés (téléchargements vus au Maroc et au Bénin).
  test('Maroc, Tunisie, Afrique de l\'Ouest : taxe, devise et format par défaut', () {
    expect(defaultCurrencyCode(region: 'MA'), 'MAD');
    expect(defaultCurrencyCode(region: 'TN'), 'TND');
    for (final r in ['SN', 'CI', 'BJ']) {
      expect(defaultCurrencyCode(region: r), 'XOF', reason: r);
      expect(defaultTaxConfig(region: r).rate, 18, reason: r);
    }
    expect(defaultTaxConfig(region: 'MA').rate, 20);
    expect(defaultTaxConfig(region: 'TN').rate, 19);
    // Franc CFA sans centimes, dinar tunisien à 3 décimales.
    final xof = formatMoney(12500, code: 'XOF', locale: 'fr');
    expect(xof.contains(','), isFalse, reason: xof);
    expect(xof, contains('F CFA'));
    expect(formatMoney(1.5, code: 'TND', locale: 'fr'), contains('1,500'));
    expect(formatMoney(10, code: 'MAD', locale: 'fr'), contains('10,00'));
    for (final c in ['MAD', 'TND', 'XOF']) {
      expect(kCurrencyCodes, contains(c));
    }
  });

  test('searchFold : recherche sans accents ni majuscules', () {
    expect(searchFold('Société Générale').contains(searchFold('societe')), isTrue);
    expect(searchFold('Müller GmbH').contains('muller'), isTrue);
    expect(searchFold('ŁUKASZ Żółć'), 'lukasz zolc');
  });
}
