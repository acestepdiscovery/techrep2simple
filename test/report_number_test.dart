// Numéro de rapport (2026-10-19) : imprimé sur les PDF. Les accents ne doivent
// plus faire disparaître de lettres, et les EXEMPLES suivent la langue.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/shared/services/pdf_service.dart';

void _lang(String l) => Localization.load(Locale(l),
    translations: Translations(json.decode(
        File('assets/translations/$l.json').readAsStringSync()) as Map<String, dynamic>));

void main() {
  final d = DateTime(2026, 10, 19);
  String n(String pattern, {String? client, String? company, String? tech}) =>
      PdfService.resolveReportNumber(7, pattern,
          clientName: client, companyName: company, technicianName: tech, date: d);

  test('motifs de base', () {
    expect(n('{num}'), '007');
    expect(n('{year}-{num}'), '2026-007');
    expect(n('{year}/{month}/{day}/{num}'), '2026/10/19/007');
    expect(n('{client}-{num}'), 'CLI-007', reason: 'client vide');
    expect(n('{tech}-{num}', tech: 'Jean  Paul Martin'), 'JPM-007');
  });

  test('accents : aucune lettre perdue', () {
    expect(n('{client}-{num}', client: 'Müller'), 'MULLER-007');
    expect(n('{client}-{num}', client: 'Société Générale'), 'SOCIETEGENERALE-007');
    expect(n('{client}-{num}', client: 'Łukasz Wiśniewski'), 'LUKASZWISNIEWSKI-007');
    expect(n('{client}-{num}', client: 'Weißbach'), 'WEISSBACH-007');
    expect(n('{company}/{num}', company: 'Œuvres & Fils'), 'OEUVRESFILS/007');
  });

  test('exemples dans la langue de l\'app', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    _lang('de');
    final de = PdfService.exampleReportNumber('{client}-{company}-{num}', date: d);
    expect(de, contains('WEBER'));
    expect(de, isNot(contains('DUPONT')));
    _lang('pl');
    expect(PdfService.exampleReportNumber('{client}-{num}', date: d), 'NOWAK-001');
    _lang('fr');
    expect('ex_company'.tr(), isNotEmpty);
  });
}
