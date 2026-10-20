// Modèles de rapport (2026-10-20) : la fenêtre « Enregistrer comme modèle »
// annonce que les infos client ne sont pas copiées — elles l'étaient (vu au
// test sur émulateur : nom, adresse, téléphone du client précédent repris).
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';

const _client = ['client_id', 'client_name', 'client_address', 'client_phone',
    'client_contact', 'contract_number', 'client_business_id', 'equipment_serial'];

void main() {
  final source = ReportModel(
    id: 'src',
    clientId: 'c1',
    clientName: 'Harbor View Apartments',
    clientAddress: '250 Pine Street',
    clientPhone: '+1 206 555 0147',
    clientContact: 'Mr Lewis',
    contractNumber: 'CT-1',
    clientBusinessId: 'FR123',
    interventionType: 'Remplacement circulateur',
    equipmentBrand: 'Vaillant',
    equipmentSerial: 'VT-2291-554',
    description: 'Circulateur remplacé',
    date: DateTime(2026, 10, 20),
    createdAt: DateTime(2026, 10, 20),
    updatedAt: DateTime(2026, 10, 20),
  );

  test('enregistrer un modèle : ni infos client ni n° de série', () {
    final data = ReportPreset.fromReport(source);
    for (final k in _client) {
      expect(data.containsKey(k), isFalse, reason: k);
    }
    expect(data['intervention_type'], 'Remplacement circulateur');
    expect(data['equipment_brand'], 'Vaillant');
    expect(data['description'], 'Circulateur remplacé');
  });

  test('modèles DÉJÀ enregistrés (2 anciens formats) : infos client retirées au chargement', () {
    final snake = ReportPreset.forNewReport(source.toMap());
    final camel = ReportPreset.forNewReport({
      'clientName': 'Ancien Client', 'clientPhone': '0600', 'interventionType': 'Entretien',
      'equipmentSerial': 'SN-1',
    });
    for (final m in [snake, camel]) {
      for (final k in _client) {
        expect(m.containsKey(k), isFalse, reason: k);
      }
    }
    expect(camel['intervention_type'], 'Entretien');
    expect(snake['description'], 'Circulateur remplacé');
  });
}
