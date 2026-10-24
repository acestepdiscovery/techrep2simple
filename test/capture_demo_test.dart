import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';
import 'package:reportnew1cld/shared/dev/capture_demo.dart';

/// (2026-10-24) Données de démo pour les captures des stores.
void main() {
  final now = DateTime(2026, 10, 24, 15, 0);
  final day = DateTime(2026, 10, 24);
  final base = ReportModel(
    id: 'sample-plomberie',
    reportNumber: 1,
    clientName: 'Client',
    sector: SectorTemplate.plomberie,
    date: day,
    startTime: day.add(const Duration(hours: 8, minutes: 30)),
    endTime: day.add(const Duration(hours: 10, minutes: 30)),
    laborHours: 2,
    laborRate: 55,
    materials: const [MaterialItem(reference: 'A', label: 'Pièce', quantity: 1, unitPrice: 10)],
    signatureClientData: 'c2ln',
    signatureTechData: 'c2ln',
    technicianName: 'Julien Martin',
    status: ReportStatus.validated,
    createdAt: now,
    updatedAt: now,
  );

  test('le bouton de démo est ABSENT des builds normaux (store)', () {
    expect(kCaptureTools, isFalse);
  });

  test('rapport perso : statut, numéro, dates décalées, photos, signature retirée', () {
    const item = CaptureDemoItem(SectorTemplate.plomberie, ReportStatus.draft, 2, 23,
        signed: false);
    final r = captureDemoReport(base, item,
        id: 'capture-local-plomberie', now: now, photos: ['/a.jpg', '/b.jpg']);
    expect(r.id, 'capture-local-plomberie');
    expect(r.reportNumber, 23);
    expect(r.status, ReportStatus.draft);
    expect(r.date, DateTime(2026, 10, 22));
    expect(r.startTime, DateTime(2026, 10, 22, 8, 30));
    expect(r.photosPaths, ['/a.jpg', '/b.jpg']);
    expect(r.signatureClientData, isNull);
    expect(r.signatureTechData, isNull);
    expect(r.companyId, isNull);
    expect(r.laborHours, 2); // montant conservé (facture)
    expect(r.materials, hasLength(1));
    expect(r.updatedAt.isBefore(now.subtract(const Duration(days: 2))), isTrue);
  });

  test('rapport d\'équipe : technicien fictif, équipe, signé', () {
    const item = CaptureDemoItem(SectorTemplate.plomberie, ReportStatus.submitted, 0, 47);
    final r = captureDemoReport(base, item,
        id: 'capture-team-plomberie',
        now: now,
        photos: ['photo_1.jpg', 'photo_2.jpg'],
        technicianId: 'capture-tech-1',
        technicianName: 'Lucas Moreau',
        companyId: 'team1');
    final m = r.toMap();
    expect(m['status'], 'submitted');
    expect(m['technician_name'], 'Lucas Moreau');
    expect(m['technician_id'], 'capture-tech-1');
    expect(m['company_id'], 'team1');
    expect(jsonDecode(m['photos'] as String), hasLength(2));
    expect(r.signatureClientData, 'c2ln');
  });

  test('ordre de la liste : le plus grand numéro est le plus récent', () {
    DateTime at(CaptureDemoItem i) =>
        captureDemoReport(base, i, id: 'x', now: now).updatedAt;
    for (final plan in [captureLocalPlan, captureTeamPlan]) {
      for (var i = 1; i < plan.length; i++) {
        expect(at(plan[i - 1]).isAfter(at(plan[i])), isTrue,
            reason: '${plan[i - 1].sector} avant ${plan[i].sector}');
      }
    }
  });

  test('le 1er rapport perso sert au formulaire / signature / facture', () {
    final first = captureLocalPlan.first;
    expect(first.status, ReportStatus.draft);
    expect(first.signed, isFalse);
    expect(first.daysAgo, 0);
    expect(captureTeamPlan.where((i) => i.status == ReportStatus.submitted), isNotEmpty);
  });
}
