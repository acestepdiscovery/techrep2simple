// PDF « professionnel » (présentation par défaut) — 2026-10-20 : il n'affichait
// ni l'équipement, ni le titre de l'intervention, ni le téléphone, ni le n° de
// contrat, ni les champs du métier, pourtant saisis (vu au test sur émulateur).
import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';
import 'package:reportnew1cld/shared/services/pdf_service.dart';

final _report = ReportModel(
  id: 'pro-details-1',
  reportNumber: 7,
  clientName: 'Harbor View Apartments',
  clientPhone: '+1 206 555 0147',
  contractNumber: 'CT-2026-118',
  interventionType: 'Remplacement du circulateur',
  equipmentType: 'Chaudière murale gaz',
  equipmentBrand: 'Vaillant',
  equipmentModel: 'ecoTEC plus',
  equipmentSerial: 'VT-2291-554',
  sector: SectorTemplate.plomberie,
  sectorFields: const {'type_tuyauterie': 'Cuivre', 'vide': ''},
  description: 'Circulateur remplacé.',
  date: DateTime(2026, 10, 20),
  createdAt: DateTime(2026, 10, 20),
  updatedAt: DateTime(2026, 10, 20),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting();
    Localization.load(const Locale('fr'),
        translations: Translations(json.decode(
            File('assets/translations/fr.json').readAsStringSync()) as Map<String, dynamic>));
  });

  test('bloc INFOS : téléphone et n° de contrat', () {
    final rows = PdfService.proExtraInfoRows(_report);
    expect(rows.map((r) => r.$2), containsAll(['+1 206 555 0147', 'CT-2026-118']));
  });

  test('blocs Intervention, Équipement et champs du métier (valeurs vides ignorées)', () {
    final blocks = PdfService.proDetailBlocks(_report);
    final values = [for (final b in blocks) for (final r in b.$2) r.$2];
    expect(values, containsAll(['Remplacement du circulateur', 'Chaudière murale gaz', 'Vaillant',
        'ecoTEC plus', 'VT-2291-554', 'Cuivre']));
    expect(values, isNot(contains('')));
    expect(blocks.map((b) => b.$1), contains('ÉQUIPEMENT'));
  });

  test('rien à afficher → aucun bloc (pas de titre vide)', () {
    final vide = ReportModel(id: 'v', clientName: 'X', date: DateTime(2026),
        createdAt: DateTime(2026), updatedAt: DateTime(2026));
    expect(PdfService.proDetailBlocks(vide), isEmpty);
    expect(PdfService.proExtraInfoRows(vide), isEmpty);
  });

  test('le PDF professionnel se génère avec ces blocs', () async {
    final bytes = await PdfService().generateReport(_report, pdfTemplate: 'professionnel');
    expect(bytes.length, greaterThan(1000));
    final dir = Platform.environment['PDF_DUMP_DIR'];
    if (dir != null) File('$dir/pro_details.pdf').writeAsBytesSync(bytes);
  });

  // (2026-10-20) Durée remplie par l'IA mais aucun prix : le PDF du client
  // affichait « 2,25 h × 0,00 €/h = 0,00 € » et « TOTAL : 0,00 € ».
  test('facturation : sans aucun prix, seulement les heures (pas de 0,00 ni de total)', () async {
    ReportModel r({double? rate, List<MaterialItem> mats = const []}) => ReportModel(
        id: 'b', clientName: 'X', laborHours: 2.25, laborRate: rate, materials: mats,
        date: DateTime(2026), createdAt: DateTime(2026), updatedAt: DateTime(2026));
    expect(PdfService.billingHasPrices(r()), isFalse);
    expect(PdfService.billingHasPrices(r(rate: 0)), isFalse);
    expect(PdfService.billingHasPrices(r(rate: 45)), isTrue);
    expect(PdfService.billingHasPrices(r(mats: const [
      MaterialItem(reference: 'J1', label: 'Joint', quantity: 2, unitPrice: 3.5)])), isTrue);
    for (final (name, report) in [('heures_sans_prix', r()), ('heures_avec_taux', r(rate: 45))]) {
      final bytes = await PdfService().generateReport(report, pdfTemplate: 'professionnel');
      expect(bytes.length, greaterThan(1000));
      final dir = Platform.environment['PDF_DUMP_DIR'];
      if (dir != null) File('$dir/$name.pdf').writeAsBytesSync(bytes);
    }
  });
}
