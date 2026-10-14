// OUTIL DE RELECTURE VISUELLE des PDF (ajouté 2026-10-14).
// Génère des PDF « pièges » (rapport chargé : secteur, champs perso, photos,
// signatures, logo, 40 articles, texte très long, mots sans espace…) dans les
// 8 langues, pour les REGARDER (bugs invisibles aux tests : € blanc, texte
// coupé, libellé non traduit…). Signale aussi les plantages de génération.
//
// Ne fait rien sans la variable PDF_DUMP_DIR (donc inoffensif dans `flutter test`).
//   PowerShell : $env:PDF_DUMP_DIR="C:\temp\pdfdump"; flutter test test/pdf_visual_dump_test.dart
// Puis convertir en images (ex. PyMuPDF) et relire page par page.
import 'dart:async';
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
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';
import 'package:reportnew1cld/shared/services/pdf_service.dart';
import 'package:reportnew1cld/shared/services/validation_pdf_service.dart';

const langs = ['fr', 'en', 'de', 'es', 'it', 'nl', 'pl', 'pt'];

Map<String, dynamic> _json(String code) =>
    json.decode(File('assets/translations/$code.json').readAsStringSync())
        as Map<String, dynamic>;

void _useLanguage(String lang) {
  Localization.load(
    Locale(lang),
    translations: Translations(_json(lang)),
    fallbackTranslations: Translations(_json('fr')),
    ignorePluralRules: false,
  );
  Intl.defaultLocale = lang;
}

Uint8List _signaturePng() {
  final im = img.Image(width: 400, height: 160, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 0));
  for (var x = 20; x < 380; x++) {
    final y = 80 + (40 * (x % 90 - 45) / 45).round();
    img.fillCircle(im, x: x, y: y, radius: 2, color: img.ColorRgba8(10, 10, 80, 255));
  }
  return Uint8List.fromList(img.encodePng(im));
}

Uint8List _photoJpg(int seed) {
  final im = img.Image(width: 1200, height: 900);
  img.fill(im, color: img.ColorRgb8(60 + seed * 40, 120, 180 - seed * 30));
  img.fillRect(im, x1: 200, y1: 200, x2: 900, y2: 700, color: img.ColorRgb8(240, 200, 60));
  return Uint8List.fromList(img.encodeJpg(im, quality: 70));
}

Uint8List _logoPng() {
  final im = img.Image(width: 300, height: 120);
  img.fill(im, color: img.ColorRgb8(21, 101, 192));
  img.fillRect(im, x1: 20, y1: 20, x2: 120, y2: 100, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(im));
}

const _para =
    'Remplacement du circulateur… coût 120,50 € • garantie 2 ans. Prévoir l’entretien — Ø 22 mm, 3 bar, ±5 %. '
    'Le client « Côte » signale un bruit intermittent ; contrôle des raccords, purge du réseau, essai sous pression. ';

ReportModel _report({required bool extreme}) {
  final sig = base64Encode(_signaturePng());
  return ReportModel(
    id: 'abcdef1234567890',
    reportNumber: 42,
    clientName: 'Łukasz Żółć — l’Hôtel « Côte » & Fils (Établissements Ünal-Øster)',
    clientAddress: '12 rue de l’Église, Bâtiment B, 3ᵉ étage, 75001 Paris',
    clientPhone: '+33 6 12 34 56 78',
    clientContact: 'Mme Ünal',
    contractNumber: 'CTR-2026-000123',
    interventionType: 'Dépannage chauffe-eau',
    sector: SectorTemplate.plomberie,
    sectorFields: const {
      'type_tuyauterie': 'copper',
      'pression_testee_bar': '3,5',
    },
    date: DateTime(2026, 10, 3),
    endDate: DateTime(2026, 10, 4),
    startTime: DateTime(2026, 10, 3, 8, 30),
    endTime: DateTime(2026, 10, 4, 11, 15),
    description: extreme
        ? List.filled(45, _para).join('\n')
        : List.filled(3, _para).join('\n'),
    observations: extreme
        ? 'contact: tres.long.email.sans.espace.pour.tester.le.retour.a.la.ligne@exemple-entreprise-du-batiment.fr '
            'https://www.exemple.fr/un/lien/tres/long/sans/aucun/espace/pour/voir/si/le/texte/deborde/de/la/page/ou/pas/123456789 '
            '${List.filled(10, _para).join()}'
        : 'Prévoir l’entretien — Ø 22 mm, 3 bar, ±5 %',
    equipmentType: 'Chaudière murale',
    equipmentBrand: 'Saunier Duval',
    equipmentModel: 'ThemaPlus Condens F25',
    equipmentSerial: 'SN-2026/Ä1',
    status: ReportStatus.draft,
    signatureClientStartData: sig,
    signatureTechStartData: sig,
    signatureClientData: sig,
    signatureTechData: sig,
    laborHours: 2.5,
    laborRate: 55,
    materials: [
      const MaterialItem(reference: 'CIRC-25', label: 'Circulateur ’Wilo’', quantity: 1, unitPrice: 189.9),
      const MaterialItem(reference: 'TUB-CU22', label: 'Tube cuivre Ø 22 mm', quantity: 2.5, unitPrice: 12.4),
      if (extreme)
        for (var i = 0; i < 40; i++)
          MaterialItem(
              reference: 'REF-${1000 + i}',
              label: 'Raccord laiton ¾" n°$i — très long libellé pour tester le retour à la ligne dans le tableau',
              quantity: (i % 3) + 1,
              unitPrice: 1234.5 + i),
    ],
    sousContrat: true,
    customFields: const {'Référence chantier': 'Ch-77 « Œuvre »', 'Accès': 'Code 1234 — badge'},
    createdAt: DateTime(2026, 10, 3),
    updatedAt: DateTime(2026, 10, 3),
  );
}

void main() {
  final dir = Platform.environment['PDF_DUMP_DIR'];
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting());

  test('dump visuel des PDF', () async {
    if (dir == null || dir.isEmpty) {
      markTestSkipped('PDF_DUMP_DIR non défini');
      return;
    }
    Directory(dir).createSync(recursive: true);
    final photos = [for (var i = 0; i < 3; i++) XFile.fromData(_photoJpg(i), name: 'p$i.jpg')];
    final logo = _logoPng();
    final problems = <String>[];
    for (final lang in langs) {
      _useLanguage(lang);
      final currency = lang == 'pl' ? 'PLN' : 'EUR';
      for (final extreme in [false, true]) {
        final r = _report(extreme: extreme);
        final tag = extreme ? 'extreme' : 'riche';
        Future<void> run(String name, Future<Uint8List> Function() gen) async {
          final missing = <String>{};
          try {
            final bytes = await runZoned(gen,
                zoneSpecification: ZoneSpecification(print: (s, p, z, line) {
              final m = RegExp(r'Unable to find a font to draw "(.+?)"').firstMatch(line);
              if (m != null) missing.add(m.group(1)!);
            }));
            File('$dir/${lang}_${tag}_$name.pdf').writeAsBytesSync(bytes);
            if (missing.isNotEmpty) problems.add('$lang/$tag/$name : caractères perdus $missing');
          } catch (e) {
            problems.add('$lang/$tag/$name : PLANTAGE ${e.toString().split('\n').first}');
          }
        }

        for (final tpl in ['simple', 'professionnel']) {
          await run(tpl, () => PdfService().generateReport(r,
              photos: photos,
              companyName: 'Société Démo & Cie',
              technicianName: 'Jean Ünal',
              logoBytes: logo,
              companyAddress: '5 avenue de l’Île, 69002 Lyon',
              companyPhone: '+33 4 00 00 00 00',
              companyEmail: 'contact@societe-demo.fr',
              companySiret: '123 456 789 00012',
              companyTva: 'FR12345678900',
              pdfTemplate: tpl,
              currencyCode: currency));
        }
        await run('facture', () => PdfService().generateInvoice(r,
            companyName: 'Société Démo & Cie',
            companyAddress: '5 avenue de l’Île, 69002 Lyon',
            companyPhone: '+33 4 00 00 00 00',
            companyEmail: 'contact@societe-demo.fr',
            companySiret: '123 456 789 00012',
            logoBytes: logo,
            taxRate: 20,
            taxLabel: 'TVA',
            taxMention: 'Mention — test « ok »',
            currencyCode: currency));
      }
    }

    // ── Cas supplémentaires (2026-10-14) : rapport presque vide, alphabets non
    // latins, nom d'entreprise très long, 12 photos, PDF de validation équipe.
    for (final lang in ['fr', 'de', 'pl']) {
      _useLanguage(lang);
      Future<void> run(String name, Future<Uint8List> Function() gen) async {
        final missing = <String>{};
        try {
          final bytes = await runZoned(gen,
              zoneSpecification: ZoneSpecification(print: (s, p, z, line) {
            final m = RegExp(r'Unable to find a font to draw "(.+?)"').firstMatch(line);
            if (m != null) missing.add(m.group(1)!);
          }));
          File('$dir/x_${lang}_$name.pdf').writeAsBytesSync(bytes);
          if (missing.isNotEmpty) problems.add('x/$lang/$name : caractères perdus $missing');
        } catch (e) {
          problems.add('x/$lang/$name : PLANTAGE ${e.toString().split('\n').first}');
        }
      }

      final vide = ReportModel(
          id: 'vide0000', clientName: '', date: DateTime(2026, 10, 14),
          createdAt: DateTime(2026), updatedAt: DateTime(2026));
      await run('vide_simple', () => PdfService().generateReport(vide, pdfTemplate: 'simple'));
      await run('vide_pro', () => PdfService().generateReport(vide, pdfTemplate: 'professionnel'));
      await run('vide_facture', () => PdfService().generateInvoice(vide));

      final monde = _report(extreme: false).copyWith(
        clientName: 'Иван Петров · Γιώργος Παπαδόπουλος · محمد · 王伟 · Đặng',
        clientAddress: 'ул. Ленина 5, Москва — Αθήνα — Hà Nội',
      );
      final photos12 = [
        for (var i = 0; i < 12; i++) XFile.fromData(_photoJpg(i % 4), name: 'p$i.jpg')
      ];
      const longCompany =
          'Établissements Dupont-Moreau & Fils — Plomberie, Chauffage, Climatisation, Dépannage 24h/24';
      for (final tpl in ['simple', 'professionnel']) {
        await run('monde_$tpl', () => PdfService().generateReport(monde,
            photos: photos12,
            companyName: longCompany,
            technicianName: 'Jean-Baptiste de La Rochefoucauld-Montmorency',
            logoBytes: _logoPng(),
            pdfTemplate: tpl));
      }
      await run('monde_facture',
          () => PdfService().generateInvoice(monde, companyName: longCompany, logoBytes: _logoPng()));

      final ext = _report(extreme: true);
      final snap = <String, dynamic>{
        ...ext.toMap(),
        'date': ext.date.toIso8601String(),
        'materials': [
          for (final m in ext.materials)
            {'label': m.label, 'quantity': m.quantity, 'unitPrice': m.unitPrice}
        ],
        'sector_fields': ext.sectorFields,
        'photo_count': 5,
        'signature_client': ext.signatureClientData,
        'signature_tech': ext.signatureTechData,
      };
      await run('validation', () => ValidationPdfService.generate(snap,
          currencyCode: lang == 'pl' ? 'PLN' : 'EUR'));
    }
    File('$dir/_problemes.txt').writeAsStringSync(problems.join('\n'));
    // ignore: avoid_print
    print('PROBLEMES (${problems.length}):\n${problems.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
