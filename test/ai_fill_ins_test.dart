import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/ai/ai_fill_ins.dart';

// (2026-10-20) « Améliorer un rapport » + note audio « le contact c'était Mme Roux » :
// avant, le contact (et contrat / durée / horaires) trouvé par l'IA était ignoré.
void main() {
  Map<String, dynamic> base() => {
        'date': DateTime(2026, 10, 14).toIso8601String(),
        'client_contact': '',
        'contract_number': null,
        'labor_hours': null,
        'start_time': null,
        'end_time': null,
      };

  test('champs vides : repris depuis la réponse IA', () {
    final m = base();
    applyImproveFillIns(m, {
      'client_contact': 'Mme Roux',
      'contract_number': 'CM-2026-0042',
      'labor_hours': '2,25',
      'start_time': '13:30',
      'end_time': '15h45',
    });
    expect(m['client_contact'], 'Mme Roux');
    expect(m['contract_number'], 'CM-2026-0042');
    expect(m['labor_hours'], 2.25);
    expect(m['start_time'], DateTime(2026, 10, 14, 13, 30).toIso8601String());
    expect(m['end_time'], DateTime(2026, 10, 14, 15, 45).toIso8601String());
  });

  test('jamais d\'écrasement de ce que le technicien a saisi', () {
    final start = DateTime(2026, 10, 14, 8, 0).toIso8601String();
    final m = base()
      ..['client_contact'] = 'M. Martin'
      ..['contract_number'] = 'A-1'
      ..['labor_hours'] = 1.0
      ..['start_time'] = start;
    applyImproveFillIns(m, {
      'client_contact': 'Mme Roux',
      'contract_number': 'B-2',
      'labor_hours': '3',
      'start_time': '13:30',
    });
    expect(m['client_contact'], 'M. Martin');
    expect(m['contract_number'], 'A-1');
    expect(m['labor_hours'], 1.0);
    expect(m['start_time'], start);
  });

  test('valeurs IA vides ou invalides : rien ne change', () {
    final m = base();
    applyImproveFillIns(m, {'client_contact': '  ', 'labor_hours': 'deux', 'start_time': '25:00', 'end_time': ''});
    expect(m['client_contact'], '');
    expect(m['labor_hours'], isNull);
    expect(m['start_time'], isNull);
    expect(m['end_time'], isNull);
  });
}
