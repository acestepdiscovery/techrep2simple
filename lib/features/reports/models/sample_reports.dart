import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart' show XFile;

import 'currency_options.dart';
import 'report_model.dart';

/// Rapports d'EXEMPLE fictifs, un par métier (2026-10-14).
///
/// Montrent à un nouvel utilisateur le PDF qu'il va obtenir (dans SA langue,
/// avec des noms / villes de son pays, sa devise), puis l'aident à démarrer son
/// propre rapport réglé sur ce métier. Toujours marqués « EXEMPLE » (filigrane)
/// et jamais enregistrés ni comptés dans le quota d'exports.
class SampleReports {
  static const sectors = [
    SectorTemplate.plomberie,
    SectorTemplate.incendie,
    SectorTemplate.maintenance,
    SectorTemplate.it,
    SectorTemplate.nettoyage,
    SectorTemplate.btp,
    SectorTemplate.transport,
  ];

  /// (2026-10-20) 2 photos par métier (vue générale + détail) : images
  /// FICTIVES générées par IA (fournies par le user), JPEG 1024×768 ≈ 100 Ko
  /// (14 photos ≈ 1,4 Mo dans l'app). Sources : tool/sample_photos_sources.md.
  static Future<List<XFile>> photos(SectorTemplate s) async => [
        for (final i in [1, 2])
          XFile.fromData(
            (await rootBundle.load('assets/samples/photo_${s.name}_$i.jpg')).buffer.asUint8List(),
            mimeType: 'image/jpeg',
            name: 'photo_${s.name}_$i.jpg',
          ),
      ];

  static Future<String> _asset(String name) async =>
      base64Encode((await rootBundle.load('assets/samples/$name')).buffer.asUint8List());

  /// Rapport d'exemple complet (signé) pour [s], dans la langue courante.
  static Future<ReportModel> build(SectorTemplate s) async {
    final sigClient = await _asset('signature_client.png');
    final sigTech = await _asset('signature_tech.png');
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    String t(String f) => 'ex_${s.name}_$f'.tr();
    final d = _data[s]!;
    final start = day.add(d.start);
    final end = (d.twoDays ? day.add(const Duration(days: 1)) : day).add(d.end);
    return ReportModel(
      id: 'sample-${s.name}',
      reportNumber: 1,
      clientName: t('client'),
      clientAddress: 'ex_address'.tr(),
      clientContact: 'ex_contact'.tr(),
      interventionType: t('type'),
      sector: s,
      date: day,
      endDate: d.twoDays ? day.add(const Duration(days: 1)) : null,
      startTime: start,
      endTime: end,
      description: t('desc'),
      observations: t('obs'),
      equipmentType: t('equip'),
      equipmentBrand: d.brand,
      equipmentModel: d.model,
      equipmentSerial: d.serial,
      sectorFields: d.fields(t),
      laborHours: d.hours,
      laborRate: d.rate,
      materials: [
        MaterialItem(reference: d.ref1, label: t('mat1'), quantity: d.q1, unitPrice: d.p1),
        MaterialItem(reference: d.ref2, label: t('mat2'), quantity: d.q2, unitPrice: d.p2),
      ],
      signatureClientData: sigClient,
      signatureTechData: sigTech,
      technicianName: 'ex_technician'.tr(),
      status: ReportStatus.validated,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Point de départ pour SON rapport : métier + type d'intervention de
  /// l'exemple ; client, textes et montants vides (rien de fictif ne passe
  /// dans un vrai rapport).
  static ReportPreset starter(SectorTemplate s) => ReportPreset(
        id: 'starter-${s.name}',
        name: s.label,
        createdAt: DateTime.now(),
        data: {
          'client_name': '',
          'sector': s.name,
          'intervention_type': 'ex_${s.name}_type'.tr(),
        },
      );

  static final Map<SectorTemplate, _Sample> _data = {
    SectorTemplate.plomberie: _Sample(
      brand: 'Saunier Duval', model: 'ThemaPlus Condens F25', serial: 'SD-2241-087',
      ref1: 'CIRC-2570', q1: 1, p1: 189.90, ref2: 'JF-34', q2: 4, p2: 1.20,
      hours: 2, rate: 55, start: const Duration(hours: 8, minutes: 30), end: const Duration(hours: 10, minutes: 30),
      fields: (t) => {
        'type_tuyauterie': 'copper',
        'diametre_mm': '22',
        'longueur_m': formatQuantity(3),
        'pression_testee_bar': formatQuantity(1.5),
        'remarques_specifiques': t('note'),
      },
    ),
    SectorTemplate.incendie: _Sample(
      brand: 'Sicli', model: 'EP6', serial: 'LOT-2026-03',
      ref1: 'REC-ABC6', q1: 1, p1: 38.00, ref2: 'SCL-01', q2: 12, p2: 0.80,
      hours: 1.5, rate: 48, start: const Duration(hours: 9), end: const Duration(hours: 10, minutes: 30),
      fields: (t) => {
        'reference_extincteur': 'EXT-07',
        'type_agent': 'powder_abc',
        'pression_manometre': '15',
        'date_prochaine_verif':
            DateFormat.yMd().format(DateTime.now().add(const Duration(days: 365))),
      },
    ),
    SectorTemplate.maintenance: _Sample(
      brand: 'Atlas Copco', model: 'GA 11', serial: 'AC-11-4471',
      ref1: 'KIT-GA11', q1: 1, p1: 86.50, ref2: 'OIL-5L', q2: 1, p2: 42.00,
      hours: 3, rate: 58, start: const Duration(hours: 8), end: const Duration(hours: 11),
      fields: (t) => {
        'numero_machine': 'C-02',
        'type_entretien': 'preventive',
        'heures_machine': formatQuantity(12450),
        'pieces_remplacees': t('parts'),
      },
    ),
    SectorTemplate.it: _Sample(
      brand: 'Netgear', model: 'GS724T', serial: 'NG-5539-221',
      ref1: 'SW-24G', q1: 1, p1: 219.00, ref2: 'RJ45-C6-2', q2: 6, p2: 4.50,
      hours: 2.5, rate: 65, start: const Duration(hours: 14), end: const Duration(hours: 16, minutes: 30),
      fields: (t) => {
        'nom_machine': 'SW-01',
        'adresse_ip': '192.168.1.2',
        'systeme_exploitation': 'Firmware 6.0.8',
        'ticket_reference': 'TCK-2026-0412',
        'actions_effectuees': t('actions'),
      },
    ),
    SectorTemplate.nettoyage: _Sample(
      brand: 'Kärcher', model: 'BD 50/50', serial: 'KR-50-3318',
      ref1: 'DET-5L', q1: 1, p1: 24.90, ref2: 'SAC-100', q2: 2, p2: 7.50,
      hours: 6, rate: 32, start: const Duration(hours: 7), end: const Duration(hours: 13),
      fields: (t) => {
        'surface_m2': '240',
        'produits_utilises': t('products'),
        'frequence': 'once',
      },
    ),
    SectorTemplate.btp: _Sample(
      brand: 'Jacob Delafon', model: 'Flight 90 × 120', serial: '',
      ref1: 'FAI-M2', q1: 12, p1: 32.00, ref2: 'MC-25', q2: 3, p2: 18.50,
      hours: 16, rate: 45, start: const Duration(hours: 8), end: const Duration(hours: 17),
      twoDays: true,
      fields: (t) => {
        'reference_chantier': 'CH-2026-031',
        'nature_travaux': t('nature'),
        'surface_ou_volume': '12',
        'materiaux_utilises': t('materials'),
      },
    ),
    SectorTemplate.transport: _Sample(
      brand: 'Renault', model: 'Master', serial: 'VF1MA-4521',
      ref1: 'BAT-95', q1: 1, p1: 149.00, ref2: 'DEP-01', q2: 1, p2: 45.00,
      hours: 1, rate: 60, start: const Duration(hours: 15, minutes: 30), end: const Duration(hours: 16, minutes: 30),
      fields: (t) => {
        'type_vehicule': 'van',
        'immatriculation': 'AB-123-CD',
        'kilometrage': formatQuantity(148500),
        'trajet': 'ex_route'.tr(),
        'type_intervention': 'breakdown',
        'chargement': t('load'),
      },
    ),
  };
}

class _Sample {
  final String brand, model, serial, ref1, ref2;
  final double q1, p1, q2, p2, hours, rate;
  final Duration start, end;
  final bool twoDays;
  final Map<String, dynamic> Function(String Function(String) t) fields;

  const _Sample({
    required this.brand,
    required this.model,
    required this.serial,
    required this.ref1,
    required this.q1,
    required this.p1,
    required this.ref2,
    required this.q2,
    required this.p2,
    required this.hours,
    required this.rate,
    required this.start,
    required this.end,
    required this.fields,
    this.twoDays = false,
  });
}
