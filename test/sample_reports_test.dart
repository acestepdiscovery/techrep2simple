// Rapports d'EXEMPLE (2026-10-14) : les 7 métiers × 8 langues se génèrent en
// PDF (avec filigrane), sans caractère perdu ni clé de traduction manquante.
// Option : PDF_DUMP_DIR=... → écrit les PDF pour relecture visuelle.
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
import 'package:reportnew1cld/features/reports/models/sample_reports.dart';
import 'package:reportnew1cld/shared/services/pdf_service.dart';

const langs = ['fr', 'en', 'de', 'es', 'it', 'nl', 'pl', 'pt'];

void _useLanguage(String lang) {
  final m = json.decode(File('assets/translations/$lang.json').readAsStringSync())
      as Map<String, dynamic>;
  Localization.load(Locale(lang), translations: Translations(m), ignorePluralRules: false);
  Intl.defaultLocale = lang;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting());
  final dump = Platform.environment['PDF_DUMP_DIR'];

  for (final lang in langs) {
    test('exemples ($lang) : 7 métiers, PDF complets', () async {
      _useLanguage(lang);
      for (final s in SampleReports.sectors) {
        final r = await SampleReports.build(s);
        // Aucune clé brute (« ex_... ») : tout est traduit.
        for (final v in [r.clientName, r.interventionType, r.description, r.observations,
          r.equipmentType, 'ex_address'.tr(), ...r.materials.map((m) => m.label),
          ...r.sectorFields.values.map((v) => '$v')]) {
          expect(v.startsWith('ex_'), isFalse, reason: '$lang/${s.name} : $v');
        }
        expect(r.signatureClientData, isNotEmpty);
        final missing = <String>{};
        final bytes = await runZoned(
          () => PdfService().generateReport(r,
              companyName: 'ex_company'.tr(),
              technicianName: 'ex_technician'.tr(),
              pdfTemplate: s.index.isEven ? 'professionnel' : 'simple',
              watermark: 'ex_watermark'.tr()),
          zoneSpecification: ZoneSpecification(print: (a, b, c, line) {
            final m = RegExp(r'Unable to find a font to draw "(.+?)"').firstMatch(line);
            if (m != null) missing.add(m.group(1)!);
          }),
        );
        expect(missing, isEmpty, reason: '$lang/${s.name}');
        expect(bytes.length, greaterThan(5000));
        if (dump != null && dump.isNotEmpty) {
          Directory(dump).createSync(recursive: true);
          File('$dump/ex_${lang}_${s.name}.pdf').writeAsBytesSync(bytes);
        }
      }
      // Point de départ : métier + type, rien de fictif dans le client.
      final st = SampleReports.starter(SectorTemplate.plomberie);
      expect(st.data['sector'], 'plomberie');
      expect(st.data['client_name'], '');
    });
  }
}
