// Anti-régression (2026-10-14) : mise à jour de la base locale d'un utilisateur
// de la 1.0.0 (base v9) vers la 1.2.0 (base v11). C'est ce qui tourne au
// PREMIER lancement de la mise à jour chez tous les utilisateurs existants :
// aucun rapport, client ni réglage ne doit être perdu, et les valeurs de menus
// stockées en français (« Cuivre ») doivent devenir des clés (« copper »).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reportnew1cld/shared/services/local_db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Schéma EXACT de la 1.0.0+14 (commit e3e907d, base version 9).
const _v9Reports = '''
  CREATE TABLE reports (
    id TEXT PRIMARY KEY, report_number INTEGER DEFAULT 0, client_id TEXT,
    client_name TEXT NOT NULL, client_address TEXT, client_phone TEXT,
    client_contact TEXT, contract_number TEXT, intervention_type TEXT,
    sector TEXT DEFAULT 'generic', date TEXT NOT NULL, end_date TEXT,
    start_time TEXT, end_time TEXT, description TEXT, observations TEXT,
    equipment_type TEXT, equipment_brand TEXT, equipment_model TEXT,
    equipment_serial TEXT, sector_fields TEXT DEFAULT '{}',
    status TEXT DEFAULT 'draft', photos TEXT DEFAULT '[]',
    signature_client_start_data TEXT, signature_tech_start_data TEXT,
    signature_client_data TEXT, signature_tech_data TEXT, pdf_local_path TEXT,
    cloud_url TEXT, technician_id TEXT, technician_name TEXT, company_id TEXT,
    labor_hours REAL, labor_rate REAL, materials TEXT DEFAULT '[]',
    pdf_template TEXT, report_number_format TEXT, rejection_comment TEXT,
    signed_remotely INTEGER DEFAULT 0, ai_enhanced INTEGER DEFAULT 0,
    sous_contrat INTEGER DEFAULT 0, custom_fields TEXT,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  )''';
const _v9Clients = '''
  CREATE TABLE clients (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, address TEXT, phone TEXT,
    email TEXT, contact_person TEXT, contract_number TEXT, notes TEXT,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  )''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Dossier de base propre à CE test (les fichiers de test tournent en parallèle).
  setUp(() async => databaseFactory.setDatabasesPath(
      Directory.systemTemp.createTempSync('techreport_mig_').path));

  test('base 1.0.0 (v9) → 1.2.0 (v11) : rien n’est perdu', () async {
    final path = p.join(await getDatabasesPath(), 'techreport.db');
    if (File(path).existsSync()) File(path).deleteSync();

    // 1) Base telle qu'un utilisateur de la 1.0.0 l'a sur son téléphone.
    final old = await openDatabase(path, version: 9, onCreate: (db, v) async {
      await db.execute(_v9Reports);
      await db.execute(_v9Clients);
      await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
      await db.execute('CREATE TABLE report_presets (id TEXT PRIMARY KEY, name TEXT NOT NULL, '
          'created_at TEXT NOT NULL, data TEXT NOT NULL, is_archived INTEGER DEFAULT 0)');
    });
    await old.insert('reports', {
      'id': 'r-old-1',
      'report_number': 7,
      'client_name': 'Mme Dupont',
      'sector': 'plomberie',
      'date': '2026-06-10T00:00:00.000',
      'description': 'Fuite réparée',
      // menu en FRANÇAIS (ancien stockage) + champ libre qui contient « Cuivre »
      'sector_fields': jsonEncode({'type_tuyauterie': 'Cuivre', 'remarques': 'Cuivre'}),
      'status': 'completed',
      'signature_client_data': 'AAAA',
      'labor_hours': 2.5,
      'labor_rate': 50.0,
      'materials': jsonEncode([
        {'reference': 'R1', 'label': 'Raccord', 'quantity': 2.0, 'unitPrice': 3.5}
      ]),
      'custom_fields': jsonEncode({'Accès': 'Code 1234'}),
      'signed_remotely': 1,
      'created_at': '2026-06-10T08:00:00.000',
      'updated_at': '2026-06-10T09:00:00.000',
    });
    await old.insert('clients', {
      'id': 'c1', 'name': 'Mme Dupont', 'created_at': '2026-06-10', 'updated_at': '2026-06-10',
    });
    await old.insert('settings', {'key': 'company_name', 'value': 'Plomberie Martin'});
    await old.close();

    // 2) La 1.2.0 ouvre la base → migration v9 → v11.
    final dbs = LocalDbService();
    final reports = await dbs.getAllReports();
    expect(reports, hasLength(1));
    final r = reports.single;
    expect(r.reportNumber, 7);
    expect(r.clientName, 'Mme Dupont');
    expect(r.description, 'Fuite réparée');
    expect(r.sectorFields['type_tuyauterie'], 'copper', reason: 'menu → clé stable');
    expect(r.sectorFields['remarques'], 'Cuivre', reason: 'champ libre JAMAIS converti');
    expect(r.materials.single.label, 'Raccord');
    expect(r.materials.single.total, 7.0);
    expect(r.laborHours, 2.5);
    expect(r.customFields['Accès'], 'Code 1234');
    expect(r.signatureClientData, 'AAAA');
    expect(r.signedRemotely, isTrue);
    expect(r.taxRate, isNull, reason: 'pas de taxe propre → suit le défaut des Réglages');
    expect((await dbs.getAllClients()).single.name, 'Mme Dupont');
    expect(await dbs.getSetting('company_name'), 'Plomberie Martin');

    // 3) Les nouvelles colonnes (v11) sont utilisables.
    await dbs.updateReport(r.copyWith(taxRate: 10, taxLabel: 'TVA'));
    final again = await dbs.getReport('r-old-1');
    expect(again!.taxRate, 10);
    expect(again.taxLabel, 'TVA');
    expect(again.sectorFields['type_tuyauterie'], 'copper');
  });
}
